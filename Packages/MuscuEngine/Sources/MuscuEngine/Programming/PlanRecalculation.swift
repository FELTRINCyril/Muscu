import Foundation

/// Etat d'une semaine de plan, tel que le recalcul a besoin de le lire.
public struct PlanWeekState: Equatable, Sendable {
    public let number: Int
    public let blockKind: BlockKind
    public let startDate: Date
    public let volumeMultiplier: Double
    public let intensityMultiplier: Double
    /// Semaine deja entamee, terminee ou explicitement ignoree. Elle n'est
    /// JAMAIS recalculee : l'effort a eu lieu, le reecrire serait faux.
    public let isSettled: Bool

    public init(
        number: Int,
        blockKind: BlockKind,
        startDate: Date,
        volumeMultiplier: Double,
        intensityMultiplier: Double,
        isSettled: Bool
    ) {
        self.number = number
        self.blockKind = blockKind
        self.startDate = startDate
        self.volumeMultiplier = volumeMultiplier
        self.intensityMultiplier = intensityMultiplier
        self.isSettled = isSettled
    }
}

/// Ce qui changerait pour une semaine donnee.
public struct PlanWeekChange: Equatable, Sendable, Identifiable {
    public let number: Int
    public let previousStartDate: Date
    public let newStartDate: Date
    public let previousVolumeMultiplier: Double
    public let newVolumeMultiplier: Double
    public let previousIntensityMultiplier: Double
    public let newIntensityMultiplier: Double
    /// Decalage en jours applique aux seances de la semaine.
    public let dayShift: Int

    public var id: Int { number }

    public init(
        number: Int,
        previousStartDate: Date,
        newStartDate: Date,
        previousVolumeMultiplier: Double,
        newVolumeMultiplier: Double,
        previousIntensityMultiplier: Double,
        newIntensityMultiplier: Double,
        dayShift: Int
    ) {
        self.number = number
        self.previousStartDate = previousStartDate
        self.newStartDate = newStartDate
        self.previousVolumeMultiplier = previousVolumeMultiplier
        self.newVolumeMultiplier = newVolumeMultiplier
        self.previousIntensityMultiplier = previousIntensityMultiplier
        self.newIntensityMultiplier = newIntensityMultiplier
        self.dayShift = dayShift
    }

    public var movesDates: Bool { dayShift != 0 }

    public var changesLoad: Bool {
        previousVolumeMultiplier != newVolumeMultiplier
            || previousIntensityMultiplier != newIntensityMultiplier
    }

    public var changesAnything: Bool { movesDates || changesLoad }
}

/// Apercu d'un recalcul : ce qui BOUGERAIT, et ce qui ne bougera pas.
public struct PlanRecalculationPreview: Equatable, Sendable {
    public let changes: [PlanWeekChange]
    /// Numeros des semaines laissees intactes parce qu'elles sont passees.
    public let settledWeekNumbers: [Int]
    public let rationale: [String]

    public init(changes: [PlanWeekChange], settledWeekNumbers: [Int], rationale: [String]) {
        self.changes = changes
        self.settledWeekNumbers = settledWeekNumbers
        self.rationale = rationale
    }

    public var hasChanges: Bool { changes.contains { $0.changesAnything } }
}

/// Recalcul des semaines A VENIR d'un plan.
///
/// Deux garanties tenues ici :
/// 1. une semaine deja entamee ou terminee n'est jamais recalculee ;
/// 2. rien n'est applique : la fonction produit un APERCU, que l'appelant
///    n'ecrit qu'apres confirmation explicite.
public enum PlanRecalculation {
    public static func preview(
        weeks: [PlanWeekState],
        style: PeriodizationStyle,
        deloadEveryWeeks: Int?,
        goal: Goal,
        experience: Experience,
        firstFutureWeekStart: Date,
        calendar: Calendar
    ) -> PlanRecalculationPreview {
        let ordered = weeks.sorted { $0.number < $1.number }
        let settled = ordered.filter(\.isSettled)
        let future = ordered.filter { !$0.isSettled }

        guard !future.isEmpty else {
            return PlanRecalculationPreview(
                changes: [],
                settledWeekNumbers: settled.map(\.number),
                rationale: ["Aucune semaine à venir : le plan est terminé."]
            )
        }

        // Les multiplicateurs sont re-derives de la periodisation, pour le
        // MEME nombre total de semaines : le recalcul reajuste le plan, il
        // ne le raccourcit pas dans le dos de l'utilisateur.
        let planned = Periodization.weeks(
            PeriodizationInput(
                totalWeeks: ordered.count,
                style: style,
                deloadEveryWeeks: deloadEveryWeeks,
                goal: goal,
                experience: experience
            )
        )
        let plannedByNumber = Dictionary(planned.map { ($0.number, $0) }, uniquingKeysWith: { first, _ in first })

        let anchor = startOfWeek(for: firstFutureWeekStart, calendar: calendar)
        var changes: [PlanWeekChange] = []

        for (offset, week) in future.enumerated() {
            let newStart = calendar.date(byAdding: .weekOfYear, value: offset, to: anchor) ?? week.startDate
            let target = plannedByNumber[week.number]
            let shift = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: week.startDate),
                to: calendar.startOfDay(for: newStart)
            ).day ?? 0

            changes.append(PlanWeekChange(
                number: week.number,
                previousStartDate: week.startDate,
                newStartDate: newStart,
                previousVolumeMultiplier: week.volumeMultiplier,
                newVolumeMultiplier: target?.volumeMultiplier ?? week.volumeMultiplier,
                previousIntensityMultiplier: week.intensityMultiplier,
                newIntensityMultiplier: target?.intensityMultiplier ?? week.intensityMultiplier,
                dayShift: shift
            ))
        }

        return PlanRecalculationPreview(
            changes: changes,
            settledWeekNumbers: settled.map(\.number),
            rationale: rationale(settled: settled.count, changes: changes)
        )
    }

    private static func rationale(settled: Int, changes: [PlanWeekChange]) -> [String] {
        var lines: [String] = []
        if settled > 0 {
            lines.append("\(settled) semaine(s) déjà entamée(s) ou terminée(s) : laissées intactes.")
        }
        let moved = changes.filter(\.movesDates).count
        if moved > 0 {
            lines.append("\(moved) semaine(s) replanifiée(s) à partir de la semaine choisie.")
        }
        let reloaded = changes.filter(\.changesLoad).count
        if reloaded > 0 {
            lines.append("\(reloaded) semaine(s) dont le volume ou l’intensité est réaligné sur la périodisation.")
        }
        if lines.isEmpty {
            lines.append("Le plan est déjà aligné : rien à recalculer.")
        }
        return lines
    }

    static func startOfWeek(for date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }
}
