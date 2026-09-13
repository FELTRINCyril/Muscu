import Foundation
import SwiftData
import MuscuEngine

struct CalendarExportOutcome: Equatable, Sendable {
    var created: Int = 0
    var updated: Int = 0
    var removed: Int = 0
    var failed: Int = 0
    var authorization: CalendarAuthorization = .notDetermined

    var summary: String {
        "\(created) créé(s), \(updated) mis à jour, \(removed) retiré(s), \(failed) échec(s)."
    }
}

/// Export du planning vers l'application Calendrier.
///
/// Regle absolue : Muscu ne modifie QUE les evenements qu'il a crees, et il
/// les reconnait par le `CalendarLink` enregistre localement. Un evenement
/// externe qui tomberait au meme moment n'est jamais lu, modifie ni supprime.
@MainActor
enum CalendarExportService {
    static let defaultDurationMinutes = 60

    static func links(in context: ModelContext) -> [CalendarLink] {
        ((try? context.fetch(FetchDescriptor<CalendarLink>())) ?? []).filter { $0.deletedAt == nil }
    }

    static func link(for workoutId: UUID, in context: ModelContext) -> CalendarLink? {
        links(in: context).first { $0.scheduledWorkoutId == workoutId }
    }

    /// Demande l'acces uniquement quand l'utilisateur exporte : l'app
    /// fonctionne entierement sans permission Calendrier.
    static func ensureAccess(_ store: CalendarStoring) async -> CalendarAuthorization {
        let status = store.authorizationStatus()
        guard status == .notDetermined else { return status }
        return await store.requestAccess()
    }

    @discardableResult
    static func export(
        workouts: [ScheduledWorkout],
        to calendarId: String,
        store: CalendarStoring,
        in context: ModelContext,
        durationMinutes: Int = defaultDurationMinutes,
        now: Date = .now
    ) async -> CalendarExportOutcome {
        let status = await ensureAccess(store)
        guard status == .authorized else { return CalendarExportOutcome(authorization: status) }

        var outcome = CalendarExportOutcome(authorization: status)
        let existingLinks = Dictionary(
            links(in: context).map { ($0.scheduledWorkoutId, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for workout in workouts where workout.deletedAt == nil {
            let title = workout.displayName.isEmpty ? "Séance" : workout.displayName
            let start = workout.plannedDate
            let end = start.addingTimeInterval(Double(durationMinutes) * 60)
            let notes = workout.notes

            if let link = existingLinks[workout.id] {
                // On ne met a jour QUE si l'evenement lie existe encore. S'il
                // a ete supprime dans Calendrier, on retire le lien mort
                // plutot que d'en recreer un en double sans le dire.
                if store.event(identifier: link.eventIdentifier) != nil {
                    if store.updateEvent(identifier: link.eventIdentifier, title: title, start: start, end: end, notes: notes) {
                        link.updatedAt = now
                        outcome.updated += 1
                    } else {
                        outcome.failed += 1
                    }
                    continue
                }
                context.delete(link)
            }

            guard let identifier = store.createEvent(in: calendarId, title: title, start: start, end: end, notes: notes) else {
                outcome.failed += 1
                continue
            }
            context.insert(CalendarLink(
                scheduledWorkoutId: workout.id,
                eventIdentifier: identifier,
                calendarIdentifier: calendarId,
                exportedAt: now,
                updatedAt: now
            ))
            outcome.created += 1
        }

        _ = PersistenceSupport.save(context, action: "Export vers le calendrier")
        return outcome
    }

    /// Retire du calendrier les evenements crees par Muscu pour ces seances.
    @discardableResult
    static func remove(
        workouts: [ScheduledWorkout],
        store: CalendarStoring,
        in context: ModelContext
    ) async -> CalendarExportOutcome {
        let status = store.authorizationStatus()
        guard status == .authorized else { return CalendarExportOutcome(authorization: status) }

        var outcome = CalendarExportOutcome(authorization: status)
        let ids = Set(workouts.map(\.id))
        for link in links(in: context) where ids.contains(link.scheduledWorkoutId) {
            if store.removeEvent(identifier: link.eventIdentifier) {
                outcome.removed += 1
            } else {
                outcome.failed += 1
            }
            context.delete(link)
        }
        _ = PersistenceSupport.save(context, action: "Retrait des événements de calendrier")
        return outcome
    }

    /// Importe un creneau choisi par l'utilisateur en seance planifiee.
    ///
    /// On n'interprete JAMAIS un calendrier entier : c'est l'utilisateur qui
    /// designe l'evenement, et rien d'autre n'est lu.
    @discardableResult
    static func importSlot(
        title: String,
        date: Date,
        programSessionId: UUID?,
        in context: ModelContext,
        now: Date = .now
    ) -> ScheduledWorkout {
        let workout = ScheduledWorkout(
            plannedDate: date,
            programSessionId: programSessionId,
            displayName: title.isEmpty ? "Séance" : title,
            createdAt: now,
            updatedAt: now
        )
        context.insert(workout)
        _ = PersistenceSupport.save(context, action: "Import d’un créneau")
        return workout
    }
}
