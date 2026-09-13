import Foundation

/// Une seance placee a une date precise dans le plan.
public struct DraftScheduledWorkout: Codable, Equatable, Sendable {
    /// Index de la seance dans `DraftPlan.program.sessions`.
    public var sessionIndex: Int
    public var displayName: String
    public var date: Date

    public init(sessionIndex: Int, displayName: String, date: Date) {
        self.sessionIndex = sessionIndex
        self.displayName = displayName
        self.date = date
    }
}

/// Une semaine du plan : ce qu'elle change par rapport a la prescription de
/// base, et les seances qu'elle contient.
public struct DraftPlanWeek: Codable, Equatable, Sendable {
    public var number: Int
    public var blockRaw: String
    public var startDate: Date
    public var volumeMultiplier: Double
    public var intensityMultiplier: Double
    public var rationale: String
    public var workouts: [DraftScheduledWorkout]

    public init(
        number: Int,
        blockRaw: String,
        startDate: Date,
        volumeMultiplier: Double,
        intensityMultiplier: Double,
        rationale: String,
        workouts: [DraftScheduledWorkout]
    ) {
        self.number = number
        self.blockRaw = blockRaw
        self.startDate = startDate
        self.volumeMultiplier = volumeMultiplier
        self.intensityMultiplier = intensityMultiplier
        self.rationale = rationale
        self.workouts = workouts
    }

    public var block: BlockKind { BlockKind(rawValue: blockRaw) ?? .accumulation }
    public var isDeload: Bool { block == .deload }
}

/// Plan complet propose : un programme (les seances types) + un calendrier
/// de semaines datees. Le programme n'est jamais duplique par semaine : une
/// semaine ne porte que ses ecarts (volume, intensite) et ses dates.
public struct DraftPlan: Codable, Equatable, Sendable {
    public var name: String
    public var program: DraftProgram
    public var weeks: [DraftPlanWeek]
    /// Series hebdomadaires de travail par muscle principal, telles que
    /// produites par la semaine de reference (multiplicateur 1).
    public var weeklySetsByMuscle: [String: Int]
    /// Explications courtes des choix, affichables telles quelles.
    public var rationale: [String]

    public init(
        name: String,
        program: DraftProgram,
        weeks: [DraftPlanWeek],
        weeklySetsByMuscle: [String: Int],
        rationale: [String]
    ) {
        self.name = name
        self.program = program
        self.weeks = weeks
        self.weeklySetsByMuscle = weeklySetsByMuscle
        self.rationale = rationale
    }

    public var totalWorkouts: Int { weeks.reduce(0) { $0 + $1.workouts.count } }
}

/// Parametres de generation d'un plan pluri-semaines.
public struct PlanGeneratorInput: Equatable, Sendable {
    public var base: GeneratorInput
    public var totalWeeks: Int
    public var style: PeriodizationStyle
    public var deloadEveryWeeks: Int?
    public var startDate: Date
    /// Jours disponibles, convention `Calendar.weekday` (1 = dimanche).
    /// Vide = jours repartis automatiquement dans la semaine.
    public var availableWeekdays: [Int]

    public init(
        base: GeneratorInput,
        totalWeeks: Int = 8,
        style: PeriodizationStyle = .linear,
        deloadEveryWeeks: Int? = 4,
        startDate: Date,
        availableWeekdays: [Int] = []
    ) {
        self.base = base
        self.totalWeeks = totalWeeks
        self.style = style
        self.deloadEveryWeeks = deloadEveryWeeks
        self.startDate = startDate
        self.availableWeekdays = availableWeekdays
    }
}
