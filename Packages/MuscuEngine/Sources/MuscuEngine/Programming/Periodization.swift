import Foundation

/// Nature d'un bloc de periodisation, cote moteur.
public enum BlockKind: String, Codable, CaseIterable, Sendable {
    case accumulation
    case intensification
    case realization
    case deload
}

/// Style de periodisation propose.
public enum PeriodizationStyle: String, Codable, CaseIterable, Sendable {
    /// Volume eleve puis intensite croissante, bloc par bloc.
    case linear
    /// Alternance volume/intensite d'une semaine a l'autre.
    case undulating
    /// Aucun bloc : toutes les semaines sont identiques, hors decharge.
    case flat
}

/// Une semaine planifiee : ce qui change d'une semaine a l'autre est un
/// couple de multiplicateurs appliques au volume et a l'intensite, jamais une
/// reecriture des seances.
public struct PlannedWeek: Equatable, Sendable {
    /// Numero dans le PLAN (1-based).
    public var number: Int
    public var block: BlockKind
    public var volumeMultiplier: Double
    public var intensityMultiplier: Double
    /// Explication courte, affichable telle quelle.
    public var rationale: String

    public init(number: Int, block: BlockKind, volumeMultiplier: Double, intensityMultiplier: Double, rationale: String) {
        self.number = number
        self.block = block
        self.volumeMultiplier = volumeMultiplier
        self.intensityMultiplier = intensityMultiplier
        self.rationale = rationale
    }

    public var isDeload: Bool { block == .deload }
}

public struct PlannedBlock: Equatable, Sendable {
    public var kind: BlockKind
    public var orderIndex: Int
    public var weeks: [PlannedWeek]
    public var rationale: String

    public init(kind: BlockKind, orderIndex: Int, weeks: [PlannedWeek], rationale: String) {
        self.kind = kind
        self.orderIndex = orderIndex
        self.weeks = weeks
        self.rationale = rationale
    }
}

/// Parametres d'un plan pluri-semaines.
public struct PeriodizationInput: Equatable, Sendable {
    /// Duree totale, bornee a 4...16 semaines par la roadmap.
    public var totalWeeks: Int
    public var style: PeriodizationStyle
    /// Une semaine de decharge toutes les N semaines. `nil` = aucune.
    public var deloadEveryWeeks: Int?
    public var goal: Goal
    public var experience: Experience

    public init(
        totalWeeks: Int,
        style: PeriodizationStyle = .linear,
        deloadEveryWeeks: Int? = 4,
        goal: Goal = .hypertrophy,
        experience: Experience = .intermediate
    ) {
        self.totalWeeks = totalWeeks
        self.style = style
        self.deloadEveryWeeks = deloadEveryWeeks
        self.goal = goal
        self.experience = experience
    }
}

/// Construit la structure d'un plan : blocs, semaines, et ce que chaque
/// semaine change par rapport a la prescription de base.
///
/// Entierement deterministe : le meme `PeriodizationInput` donne toujours le
/// meme resultat.
public enum Periodization {
    public static let minimumWeeks = 4
    public static let maximumWeeks = 16

    /// Une decharge reduit REELLEMENT le volume, et l'intensite pour les
    /// objectifs ou elle est le facteur limitant.
    public static let deloadVolumeMultiplier = 0.5
    public static let deloadIntensityMultiplier = 0.9

    public static func plan(_ input: PeriodizationInput) -> [PlannedBlock] {
        let totalWeeks = min(max(input.totalWeeks, minimumWeeks), maximumWeeks)
        var weeks: [PlannedWeek] = []

        for number in 1...totalWeeks {
            let isDeload = isDeloadWeek(number: number, totalWeeks: totalWeeks, every: input.deloadEveryWeeks)
            if isDeload {
                weeks.append(
                    PlannedWeek(
                        number: number,
                        block: .deload,
                        volumeMultiplier: deloadVolumeMultiplier,
                        intensityMultiplier: deloadIntensityMultiplier,
                        rationale: "Décharge : volume réduit de moitié pour absorber le travail des semaines précédentes."
                    )
                )
                continue
            }
            weeks.append(week(number: number, totalWeeks: totalWeeks, input: input))
        }

        return blocks(from: weeks)
    }

    /// Semaines a plat, dans l'ordre du plan.
    public static func weeks(_ input: PeriodizationInput) -> [PlannedWeek] {
        plan(input).flatMap(\.weeks).sorted { $0.number < $1.number }
    }

    // MARK: - Prive

    /// Decharge a chaque multiple de `every`, SAUF la derniere semaine du
    /// plan : un cycle se termine sur du travail reel, pas sur une semaine
    /// allegee dont on ne verrait jamais le benefice.
    private static func isDeloadWeek(number: Int, totalWeeks: Int, every: Int?) -> Bool {
        guard let every, every > 1 else { return false }
        guard number != totalWeeks else { return false }
        return number.isMultiple(of: every)
    }

    private static func week(number: Int, totalWeeks: Int, input: PeriodizationInput) -> PlannedWeek {
        switch input.style {
        case .flat:
            return PlannedWeek(
                number: number,
                block: .accumulation,
                volumeMultiplier: 1,
                intensityMultiplier: 1,
                rationale: "Semaine régulière : mêmes volumes et mêmes charges qu'à la semaine précédente."
            )

        case .undulating:
            // Alternance simple : une semaine orientee volume, la suivante
            // orientee intensite.
            let isVolumeWeek = number.isMultiple(of: 2) == false
            return PlannedWeek(
                number: number,
                block: isVolumeWeek ? .accumulation : .intensification,
                volumeMultiplier: isVolumeWeek ? 1.1 : 0.9,
                intensityMultiplier: isVolumeWeek ? 0.95 : 1.05,
                rationale: isVolumeWeek
                    ? "Semaine orientée volume : plus de séries, charges légèrement plus basses."
                    : "Semaine orientée intensité : moins de séries, charges légèrement plus hautes."
            )

        case .linear:
            let progress = Double(number - 1) / Double(max(1, totalWeeks - 1))
            let kind = linearBlock(progress: progress, goal: input.goal)
            switch kind {
            case .accumulation:
                return PlannedWeek(
                    number: number,
                    block: .accumulation,
                    volumeMultiplier: 1 + 0.1 * progress,
                    intensityMultiplier: 0.95,
                    rationale: "Accumulation : le volume monte progressivement pour construire la base de travail."
                )
            case .intensification:
                return PlannedWeek(
                    number: number,
                    block: .intensification,
                    volumeMultiplier: 0.9,
                    intensityMultiplier: 1 + 0.08 * progress,
                    rationale: "Intensification : moins de séries, charges plus lourdes."
                )
            case .realization:
                return PlannedWeek(
                    number: number,
                    block: .realization,
                    volumeMultiplier: 0.7,
                    intensityMultiplier: 1.1,
                    rationale: "Réalisation : volume bas et charges hautes pour exprimer les progrès du cycle."
                )
            case .deload:
                return PlannedWeek(
                    number: number,
                    block: .deload,
                    volumeMultiplier: deloadVolumeMultiplier,
                    intensityMultiplier: deloadIntensityMultiplier,
                    rationale: "Décharge : volume réduit de moitié."
                )
            }
        }
    }

    /// Repartition linéaire des blocs. Un objectif d'endurance ou de perte de
    /// poids ne passe pas par une phase de realisation : il n'y a pas de
    /// maximal a exprimer.
    private static func linearBlock(progress: Double, goal: Goal) -> BlockKind {
        switch goal {
        case .strength, .pullUpProgress:
            if progress < 0.5 { return .accumulation }
            if progress < 0.85 { return .intensification }
            return .realization
        case .hypertrophy, .calisthenics:
            return progress < 0.6 ? .accumulation : .intensification
        case .fatLoss, .endurance:
            return .accumulation
        }
    }

    private static func blocks(from weeks: [PlannedWeek]) -> [PlannedBlock] {
        var result: [PlannedBlock] = []
        for week in weeks {
            if var last = result.last, last.kind == week.block {
                last.weeks.append(week)
                result[result.count - 1] = last
            } else {
                result.append(
                    PlannedBlock(
                        kind: week.block,
                        orderIndex: result.count,
                        weeks: [week],
                        rationale: blockRationale(week.block)
                    )
                )
            }
        }
        return result
    }

    private static func blockRationale(_ kind: BlockKind) -> String {
        switch kind {
        case .accumulation:
            return "Construire du volume de travail tolérable avant d'augmenter les charges."
        case .intensification:
            return "Réduire le volume et monter les charges, en s'appuyant sur la base construite."
        case .realization:
            return "Volume bas et charges hautes, pour exprimer les progrès du cycle."
        case .deload:
            return "Semaine allégée : le volume redescend pour récupérer."
        }
    }
}
