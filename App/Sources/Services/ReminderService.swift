import Foundation
import SwiftData
import MuscuEngine

/// Resultat d'une synchronisation des rappels, affichable tel quel.
struct ReminderSyncOutcome: Equatable, Sendable {
    var scheduled: Int = 0
    var cancelled: Int = 0
    var authorization: NotificationAuthorization = .notDetermined

    var isAuthorized: Bool { authorization == .authorized }
}

/// Tient les rappels systeme alignes sur le planning.
///
/// Deux invariants portes ici et nulle part ailleurs :
/// 1. rien n'est programme sans autorisation explicite ;
/// 2. un rappel supprime par l'utilisateur n'est jamais reprogramme, y
///    compris apres un redemarrage — c'est le role de `NotificationRecord`.
@MainActor
enum ReminderService {
    // MARK: - Autorisation

    /// Active les rappels d'une recurrence. C'est la SEULE porte qui demande
    /// l'autorisation systeme : l'utilisateur a cliqué pour cela.
    static func enableReminders(
        for schedule: PlanningSchedule,
        in context: ModelContext,
        scheduler: NotificationScheduling,
        catalog: ExerciseCatalog? = nil,
        calendar: Calendar = .current,
        now: Date = .now
    ) async -> ReminderSyncOutcome {
        var status = await scheduler.authorizationStatus()
        if status == .notDetermined {
            status = await scheduler.requestAuthorization()
        }

        guard status == .authorized else {
            schedule.remindersEnabled = false
            schedule.updatedAt = now
            _ = PersistenceSupport.save(context, action: "Activation des rappels")
            return ReminderSyncOutcome(authorization: status)
        }

        schedule.remindersEnabled = true
        schedule.updatedAt = now
        // Reactiver les rappels efface les suppressions precedentes : c'est
        // une demande explicite de repartir sur une base propre.
        clearDismissals(in: context)
        _ = PersistenceSupport.save(context, action: "Activation des rappels")

        return await refresh(in: context, scheduler: scheduler, catalog: catalog, calendar: calendar, now: now)
    }

    static func disableReminders(
        for schedule: PlanningSchedule,
        in context: ModelContext,
        scheduler: NotificationScheduling,
        catalog: ExerciseCatalog? = nil,
        calendar: Calendar = .current,
        now: Date = .now
    ) async -> ReminderSyncOutcome {
        schedule.remindersEnabled = false
        schedule.updatedAt = now
        _ = PersistenceSupport.save(context, action: "Désactivation des rappels")
        return await refresh(in: context, scheduler: scheduler, catalog: catalog, calendar: calendar, now: now)
    }

    /// Coupe TOUS les rappels, quelle que soit la recurrence.
    ///
    /// Interrupteur global demande par la roadmap : il doit exister un geste
    /// unique pour tout arreter, sans avoir a parcourir chaque recurrence.
    @discardableResult
    static func disableAllReminders(
        in context: ModelContext,
        scheduler: NotificationScheduling,
        now: Date = .now
    ) async -> ReminderSyncOutcome {
        for schedule in PlanningService.schedules(in: context) where schedule.remindersEnabled {
            schedule.remindersEnabled = false
            schedule.updatedAt = now
        }
        _ = PersistenceSupport.save(context, action: "Désactivation globale des rappels")

        let pending = await scheduler.pendingIdentifiers()
        await scheduler.cancel(identifiers: Array(pending.keys))
        purgeRecords(in: context)

        return ReminderSyncOutcome(
            cancelled: pending.count,
            authorization: await scheduler.authorizationStatus()
        )
    }

    /// Vrai des qu'une recurrence active a ses rappels allumes.
    static func hasEnabledReminders(in context: ModelContext) -> Bool {
        PlanningService.schedules(in: context).contains { $0.isEnabled && $0.remindersEnabled }
    }

    // MARK: - Synchronisation

    /// Recalcule les rappels et applique la difference.
    ///
    /// Appelee au lancement, apres un changement de planning, de programme,
    /// de fuseau horaire ou de permission : toutes ces situations ont la
    /// meme reponse, un recalcul complet a partir de l'etat courant.
    @discardableResult
    static func refresh(
        in context: ModelContext,
        scheduler: NotificationScheduling,
        catalog: ExerciseCatalog? = nil,
        calendar: Calendar = .current,
        now: Date = .now
    ) async -> ReminderSyncOutcome {
        let status = await scheduler.authorizationStatus()

        guard status == .authorized else {
            // Autorisation retiree : on nettoie ce qui restait, sans jamais
            // toucher aux donnees d'entrainement.
            let pending = await scheduler.pendingIdentifiers()
            await scheduler.cancel(identifiers: Array(pending.keys))
            purgeRecords(in: context)
            return ReminderSyncOutcome(cancelled: pending.count, authorization: status)
        }

        let desired = desiredNotifications(in: context, catalog: catalog, calendar: calendar, now: now)
        let pending = await scheduler.pendingIdentifiers()
        let dismissed = dismissedIdentifiers(in: context)

        let reconciliation = NotificationPlanner.reconcile(
            desired: desired,
            existing: pending,
            dismissedIdentifiers: dismissed
        )

        await scheduler.schedule(reconciliation.toSchedule)
        await scheduler.cancel(identifiers: reconciliation.toCancel)

        record(reconciliation.toSchedule, cancelled: reconciliation.toCancel, in: context, now: now)

        return ReminderSyncOutcome(
            scheduled: reconciliation.toSchedule.count,
            cancelled: reconciliation.toCancel.count,
            authorization: status
        )
    }

    /// Rappels souhaites, toutes recurrences confondues.
    static func desiredNotifications(
        in context: ModelContext,
        catalog: ExerciseCatalog?,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> [PlannedNotification] {
        let schedules = PlanningService.schedules(in: context).filter { $0.isEnabled && $0.remindersEnabled }
        guard !schedules.isEmpty else { return [] }

        let allSlots = PlanningService.slots(in: context, catalog: catalog)
        let workoutsBySchedule = Dictionary(
            grouping: PlanningService.scheduledWorkouts(in: context),
            by: { $0.scheduleId }
        )
        let lastActivity = lastCompletedSessionDate(in: context)

        var planned: [PlannedNotification] = []
        var seen: Set<String> = []

        // Les seances ajoutees a la main n'appartiennent a aucune recurrence.
        // Elles suivent les reglages de la PREMIERE recurrence dont les
        // rappels sont actifs : sans cette regle, ajouter une seance ponctuelle
        // reviendrait a renoncer silencieusement au rappel.
        let standaloneIds = Set((workoutsBySchedule[nil] ?? []).map(\.id))

        for (index, schedule) in schedules.enumerated() {
            var ids = Set((workoutsBySchedule[schedule.id] ?? []).map(\.id))
            if index == 0 { ids.formUnion(standaloneIds) }
            let slots = allSlots.filter { ids.contains($0.id) }
            let notifications = NotificationPlanner.plan(
                slots: slots,
                settings: schedule.reminderSettings,
                isAuthorized: true,
                now: now,
                calendar: calendar,
                lastActivity: lastActivity
            )
            // Le rappel de reprise est unique : deux recurrences ne doivent
            // pas produire deux notifications identiques le meme jour.
            for notification in notifications where seen.insert(notification.identifier).inserted {
                planned.append(notification)
            }
        }

        return planned.sorted { $0.fireDate < $1.fireDate }
    }

    // MARK: - Suppression explicite

    /// Marque un rappel comme supprime par l'utilisateur et l'annule.
    static func dismiss(
        identifier: String,
        in context: ModelContext,
        scheduler: NotificationScheduling,
        now: Date = .now
    ) async {
        if let existing = record(for: identifier, in: context) {
            existing.dismissedAt = now
            existing.updatedAt = now
        } else {
            let created = NotificationRecord(identifier: identifier, dismissedAt: now)
            context.insert(created)
        }
        _ = PersistenceSupport.save(context, action: "Suppression du rappel")
        await scheduler.cancel(identifiers: [identifier])
    }

    static func dismissedIdentifiers(in context: ModelContext) -> Set<String> {
        Set(records(in: context).filter(\.isDismissed).map(\.identifier))
    }

    static func clearDismissals(in context: ModelContext) {
        for record in records(in: context) where record.isDismissed {
            context.delete(record)
        }
    }

    // MARK: - Journal interne

    private static func records(in context: ModelContext) -> [NotificationRecord] {
        (try? context.fetch(FetchDescriptor<NotificationRecord>())) ?? []
    }

    private static func record(for identifier: String, in context: ModelContext) -> NotificationRecord? {
        records(in: context).first { $0.identifier == identifier }
    }

    private static func record(
        _ scheduled: [PlannedNotification],
        cancelled: [String],
        in context: ModelContext,
        now: Date
    ) {
        var known = Dictionary(records(in: context).map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })

        for notification in scheduled {
            if let existing = known[notification.identifier] {
                existing.fireDate = notification.fireDate
                existing.updatedAt = now
            } else {
                let created = NotificationRecord(
                    identifier: notification.identifier,
                    workoutId: notification.workoutId,
                    kindRaw: notification.kind.rawValue,
                    fireDate: notification.fireDate,
                    createdAt: now,
                    updatedAt: now
                )
                context.insert(created)
                known[notification.identifier] = created
            }
        }

        for identifier in cancelled {
            guard let existing = known[identifier], !existing.isDismissed else { continue }
            context.delete(existing)
        }

        _ = PersistenceSupport.save(context, action: "Mise à jour des rappels")
    }

    /// Supprime les traces non dismissees : une suppression volontaire, elle,
    /// doit survivre a une revocation de permission.
    private static func purgeRecords(in context: ModelContext) {
        for record in records(in: context) where !record.isDismissed {
            context.delete(record)
        }
        _ = PersistenceSupport.save(context, action: "Nettoyage des rappels")
    }

    private static func lastCompletedSessionDate(in context: ModelContext) -> Date? {
        var descriptor = FetchDescriptor<CompletedSession>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first?.date
    }
}
