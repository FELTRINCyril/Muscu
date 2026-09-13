import Foundation

/// Une seance vue par le planificateur. Volontairement minimale : le moteur
/// ne connait ni SwiftData ni l'interface.
public struct PlannedSlot: Hashable, Sendable, Identifiable {
    public let id: UUID
    public let date: Date
    public let title: String
    /// Muscles principaux vises, pour juger la recuperation. Vide = inconnu,
    /// et on ne suppose alors aucun conflit de recuperation.
    public let primaryMuscles: Set<String>
    /// Une seance terminee ne peut plus entrer en conflit : l'effort a eu lieu.
    public let isSettled: Bool

    public init(
        id: UUID,
        date: Date,
        title: String,
        primaryMuscles: Set<String> = [],
        isSettled: Bool = false
    ) {
        self.id = id
        self.date = date
        self.title = title
        self.primaryMuscles = primaryMuscles
        self.isSettled = isSettled
    }
}

/// Un conflit de planning. C'est une INFORMATION, jamais un blocage :
/// l'utilisateur peut vouloir deux seances le meme jour.
public struct ScheduleConflict: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case sameDay
        case insufficientRecovery(hours: Int, muscles: [String])
    }

    public let first: UUID
    public let second: UUID
    public let kind: Kind

    public init(first: UUID, second: UUID, kind: Kind) {
        self.first = first
        self.second = second
        self.kind = kind
    }
}

public enum ScheduleConflictDetector {
    /// Recuperation minimale conseillee entre deux sollicitations du meme
    /// groupe musculaire. Valeur indicative, alignee sur les 48 h
    /// couramment retenues pour un groupe travaille lourdement.
    public static let defaultRecoveryHours = 48

    public static func conflicts(
        among slots: [PlannedSlot],
        calendar: Calendar,
        recoveryHours: Int = defaultRecoveryHours
    ) -> [ScheduleConflict] {
        let candidates = slots.filter { !$0.isSettled }.sorted { $0.date < $1.date }
        var found: [ScheduleConflict] = []

        for index in candidates.indices {
            for other in candidates.index(after: index)..<candidates.endIndex {
                let left = candidates[index]
                let right = candidates[other]

                if calendar.isDate(left.date, inSameDayAs: right.date) {
                    found.append(ScheduleConflict(first: left.id, second: right.id, kind: .sameDay))
                    continue
                }

                let shared = left.primaryMuscles.intersection(right.primaryMuscles)
                guard !shared.isEmpty else { continue }

                let gap = right.date.timeIntervalSince(left.date) / 3600
                guard gap < Double(recoveryHours) else { continue }
                found.append(ScheduleConflict(
                    first: left.id,
                    second: right.id,
                    kind: .insufficientRecovery(hours: Int(gap.rounded()), muscles: shared.sorted())
                ))
            }
        }

        return found
    }
}

/// Proposition de replanification d'une seance manquee. Le moteur PROPOSE ;
/// l'ecrit n'est fait qu'apres confirmation explicite de l'utilisateur.
public struct RescheduleProposal: Hashable, Sendable {
    public let workoutId: UUID
    public let originalDate: Date
    public let proposedDate: Date
    /// Explication affichable, deja factuelle et sans jargon.
    public let rationale: String
    /// Conflits subsistant a la date proposee. Une proposition peut en
    /// porter : on prefere le dire que le cacher.
    public let remainingConflicts: [ScheduleConflict]

    public init(
        workoutId: UUID,
        originalDate: Date,
        proposedDate: Date,
        rationale: String,
        remainingConflicts: [ScheduleConflict] = []
    ) {
        self.workoutId = workoutId
        self.originalDate = originalDate
        self.proposedDate = proposedDate
        self.rationale = rationale
        self.remainingConflicts = remainingConflicts
    }
}

public enum RescheduleAdvisor {
    /// Une seance est consideree manquee quand sa date est passee et qu'elle
    /// n'a ete ni commencee, ni terminee, ni explicitement ignoree.
    public static func missedSlots(
        among slots: [PlannedSlot],
        now: Date,
        calendar: Calendar,
        graceHours: Int = 12
    ) -> [PlannedSlot] {
        let limit = now.addingTimeInterval(-Double(graceHours) * 3600)
        return slots
            .filter { !$0.isSettled && $0.date < limit }
            .sorted { $0.date < $1.date }
    }

    /// Propose la prochaine date libre pour une seance manquee.
    ///
    /// Priorite aux jours de la recurrence quand il y en a une : replanifier
    /// hors des jours habituels casserait le rythme choisi. A defaut, le
    /// premier jour libre.
    public static func proposal(
        for missed: PlannedSlot,
        among slots: [PlannedSlot],
        preferredWeekdays: Set<Int>,
        now: Date,
        calendar: Calendar,
        searchDays: Int = 14
    ) -> RescheduleProposal? {
        guard searchDays > 0 else { return nil }

        let others = slots.filter { $0.id != missed.id }
        let busyDays = Set(others.map { calendar.startOfDay(for: $0.date) })
        let time = timeOfDay(of: missed.date, calendar: calendar)

        var fallback: Date?
        var day = calendar.startOfDay(for: now)

        for _ in 0..<searchDays {
            defer { day = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400) }

            guard let candidate = calendar.date(
                bySettingHour: time.hour, minute: time.minute, second: 0, of: day
            ), candidate > now else { continue }

            let isFree = !busyDays.contains(calendar.startOfDay(for: candidate))
            guard isFree else { continue }

            if preferredWeekdays.isEmpty || preferredWeekdays.contains(calendar.component(.weekday, from: candidate)) {
                return makeProposal(missed: missed, date: candidate, others: others, calendar: calendar, onPreferredDay: !preferredWeekdays.isEmpty)
            }
            if fallback == nil { fallback = candidate }
        }

        guard let fallback else { return nil }
        return makeProposal(missed: missed, date: fallback, others: others, calendar: calendar, onPreferredDay: false)
    }

    private static func makeProposal(
        missed: PlannedSlot,
        date: Date,
        others: [PlannedSlot],
        calendar: Calendar,
        onPreferredDay: Bool
    ) -> RescheduleProposal {
        let moved = PlannedSlot(
            id: missed.id,
            date: date,
            title: missed.title,
            primaryMuscles: missed.primaryMuscles,
            isSettled: false
        )
        let conflicts = ScheduleConflictDetector
            .conflicts(among: others + [moved], calendar: calendar)
            .filter { $0.first == missed.id || $0.second == missed.id }

        let rationale = onPreferredDay
            ? "Premier jour habituel libre après la séance manquée."
            : "Premier jour libre : aucun jour habituel n’était disponible."

        return RescheduleProposal(
            workoutId: missed.id,
            originalDate: missed.date,
            proposedDate: date,
            rationale: rationale,
            remainingConflicts: conflicts
        )
    }

    private static func timeOfDay(of date: Date, calendar: Calendar) -> TimeOfDay {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return TimeOfDay(hour: components.hour ?? 18, minute: components.minute ?? 0)
    }
}
