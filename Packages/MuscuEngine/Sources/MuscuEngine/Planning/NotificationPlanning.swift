import Foundation

/// Nature d'un rappel. Le type fait partie de l'identifiant : replanifier
/// une seance remplace son rappel au lieu d'en empiler un second.
public enum ReminderKind: String, Codable, CaseIterable, Sendable {
    /// Avant la seance, avec un delai configurable.
    case before
    /// Le matin meme, a une heure fixe.
    case dayOf
    /// Rappel de reprise apres une periode sans seance.
    case comeback
}

/// Reglages de rappel, configurables par programme.
public struct ReminderSettings: Codable, Hashable, Sendable {
    public var isEnabled: Bool
    /// Delai avant la seance, en minutes. Zero desactive ce rappel.
    public var leadMinutes: Int
    /// Heure du rappel du jour meme. `nil` desactive ce rappel.
    public var dayOfTime: TimeOfDay?
    /// Nombre de jours sans seance avant un rappel de reprise. Zero desactive.
    public var comebackAfterDays: Int
    public var isSoundEnabled: Bool
    /// Jours de semaine autorises (convention `Calendar`). Vide = tous.
    public var allowedWeekdays: Set<Int>

    public init(
        isEnabled: Bool = false,
        leadMinutes: Int = 60,
        dayOfTime: TimeOfDay? = nil,
        comebackAfterDays: Int = 0,
        isSoundEnabled: Bool = true,
        allowedWeekdays: Set<Int> = []
    ) {
        self.isEnabled = isEnabled
        self.leadMinutes = max(0, leadMinutes)
        self.dayOfTime = dayOfTime
        self.comebackAfterDays = max(0, comebackAfterDays)
        self.isSoundEnabled = isSoundEnabled
        self.allowedWeekdays = allowedWeekdays.filter { (1...7).contains($0) }
    }

    public static let disabled = ReminderSettings()
}

/// Un rappel a programmer. Le moteur decrit QUOI programmer ; l'application
/// s'occupe de `UNUserNotificationCenter`.
public struct PlannedNotification: Hashable, Sendable {
    public let identifier: String
    public let kind: ReminderKind
    public let fireDate: Date
    public let workoutId: UUID?
    public let title: String
    public let body: String
    public let isSoundEnabled: Bool

    public init(
        identifier: String,
        kind: ReminderKind,
        fireDate: Date,
        workoutId: UUID?,
        title: String,
        body: String,
        isSoundEnabled: Bool
    ) {
        self.identifier = identifier
        self.kind = kind
        self.fireDate = fireDate
        self.workoutId = workoutId
        self.title = title
        self.body = body
        self.isSoundEnabled = isSoundEnabled
    }

    /// Identifiant STABLE : meme seance + meme type = meme identifiant.
    /// Reprogrammer ne cree donc jamais de doublon.
    public static func identifier(workoutId: UUID, kind: ReminderKind) -> String {
        "muscu.reminder.\(workoutId.uuidString).\(kind.rawValue)"
    }

    public static let comebackIdentifier = "muscu.reminder.comeback"
}

/// Resultat d'une reconciliation : ce qu'il faut ajouter et ce qu'il faut
/// retirer du centre de notifications.
public struct NotificationReconciliation: Hashable, Sendable {
    public let toSchedule: [PlannedNotification]
    public let toCancel: [String]

    public init(toSchedule: [PlannedNotification], toCancel: [String]) {
        self.toSchedule = toSchedule
        self.toCancel = toCancel
    }

    public var isEmpty: Bool { toSchedule.isEmpty && toCancel.isEmpty }
}

public enum NotificationPlanner {
    /// Calcule les rappels souhaites.
    ///
    /// Sans autorisation explicite, le resultat est VIDE : la regle « ne
    /// jamais programmer sans permission » est ainsi verifiable sans dependre
    /// de l'appareil.
    public static func plan(
        slots: [PlannedSlot],
        settings: ReminderSettings,
        isAuthorized: Bool,
        now: Date,
        calendar: Calendar,
        lastActivity: Date? = nil,
        horizonDays: Int = 30
    ) -> [PlannedNotification] {
        guard isAuthorized, settings.isEnabled else { return [] }

        let horizon = calendar.date(byAdding: .day, value: horizonDays, to: now) ?? now
        var planned: [PlannedNotification] = []

        for slot in slots where !slot.isSettled && slot.date > now && slot.date <= horizon {
            if !settings.allowedWeekdays.isEmpty {
                let weekday = calendar.component(.weekday, from: slot.date)
                guard settings.allowedWeekdays.contains(weekday) else { continue }
            }

            if settings.leadMinutes > 0 {
                let fire = slot.date.addingTimeInterval(-Double(settings.leadMinutes) * 60)
                if fire > now {
                    planned.append(PlannedNotification(
                        identifier: PlannedNotification.identifier(workoutId: slot.id, kind: .before),
                        kind: .before,
                        fireDate: fire,
                        workoutId: slot.id,
                        title: slot.title,
                        body: leadBody(minutes: settings.leadMinutes),
                        isSoundEnabled: settings.isSoundEnabled
                    ))
                }
            }

            if let dayOf = settings.dayOfTime,
               let fire = calendar.date(bySettingHour: dayOf.hour, minute: dayOf.minute, second: 0, of: slot.date),
               fire > now, fire < slot.date {
                planned.append(PlannedNotification(
                    identifier: PlannedNotification.identifier(workoutId: slot.id, kind: .dayOf),
                    kind: .dayOf,
                    fireDate: fire,
                    workoutId: slot.id,
                    title: slot.title,
                    body: "Séance prévue aujourd’hui.",
                    isSoundEnabled: settings.isSoundEnabled
                ))
            }
        }

        if settings.comebackAfterDays > 0 {
            let reference = lastActivity ?? now
            if let fire = calendar.date(byAdding: .day, value: settings.comebackAfterDays, to: reference), fire > now {
                planned.append(PlannedNotification(
                    identifier: PlannedNotification.comebackIdentifier,
                    kind: .comeback,
                    fireDate: fire,
                    workoutId: nil,
                    title: "Reprendre l’entraînement",
                    body: "Aucune séance depuis \(settings.comebackAfterDays) jours.",
                    isSoundEnabled: settings.isSoundEnabled
                ))
            }
        }

        return planned.sorted { $0.fireDate < $1.fireDate }
    }

    /// Compare rappels souhaites et rappels deja programmes.
    ///
    /// `dismissedIdentifiers` porte les rappels que l'utilisateur a
    /// explicitement supprimes : ils ne sont JAMAIS reprogrammes, meme apres
    /// un redemarrage, tant que la seance visee n'a pas change de date.
    public static func reconcile(
        desired: [PlannedNotification],
        existing: [String: Date],
        dismissedIdentifiers: Set<String>
    ) -> NotificationReconciliation {
        let kept = desired.filter { !dismissedIdentifiers.contains($0.identifier) }
        let desiredById = Dictionary(kept.map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })

        let toSchedule = kept.filter { notification in
            guard let scheduled = existing[notification.identifier] else { return true }
            // Une seconde de tolerance : les dates persistees perdent les
            // sous-secondes, et reprogrammer pour un ecart invisible ferait
            // clignoter la file a chaque lancement.
            return abs(scheduled.timeIntervalSince(notification.fireDate)) > 1
        }

        let toCancel = existing.keys
            .filter { desiredById[$0] == nil }
            .sorted()

        return NotificationReconciliation(toSchedule: toSchedule, toCancel: toCancel)
    }

    private static func leadBody(minutes: Int) -> String {
        if minutes % 60 == 0, minutes >= 60 {
            let hours = minutes / 60
            return hours == 1 ? "Séance dans 1 heure." : "Séance dans \(hours) heures."
        }
        return "Séance dans \(minutes) minutes."
    }
}
