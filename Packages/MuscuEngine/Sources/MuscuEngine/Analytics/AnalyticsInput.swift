import Foundation

/// Une serie realisee, telle que les analyses ont besoin de la lire.
///
/// Elle porte sa mesure (`SetMetricsInput`, deja utilisee par les records et
/// le tonnage) et le contexte necessaire aux agregations : exercice, muscles
/// sollicites, effort declare.
public struct AnalyticsSet: Equatable, Sendable {
    public var exerciseId: String
    public var displayName: String
    public var metrics: SetMetricsInput
    /// Muscles principaux, cles EN du catalogue. Vide si l'exercice est
    /// inconnu : la serie compte alors dans les totaux mais dans aucun muscle.
    public var primaryMuscles: [String]
    public var effort: EffortRating?
    public var reachedFailure: Bool

    public init(
        exerciseId: String,
        displayName: String,
        metrics: SetMetricsInput,
        primaryMuscles: [String] = [],
        effort: EffortRating? = nil,
        reachedFailure: Bool = false
    ) {
        self.exerciseId = exerciseId
        self.displayName = displayName
        self.metrics = metrics
        self.primaryMuscles = primaryMuscles
        self.effort = effort
        self.reachedFailure = reachedFailure
    }

    public var isWorkingSet: Bool { !metrics.isWarmup }

    /// Une serie est « difficile » quand un signal EXPLICITE le dit : effort
    /// declare a 2 repetitions en reserve ou moins, ou echec marque.
    ///
    /// Une serie sans effort saisi n'est jamais supposee difficile : ce
    /// serait confondre « pas de donnee » et « facile ».
    public var isHardSet: Bool {
        guard isWorkingSet else { return false }
        if reachedFailure { return true }
        guard let repsInReserve = effort?.repsInReserve else { return false }
        return repsInReserve <= TrainingAnalytics.hardSetRepsInReserveThreshold
    }

    /// La serie porte-t-elle une information d'effort exploitable ?
    public var hasDeclaredEffort: Bool { effort?.repsInReserve != nil || reachedFailure }
}

/// Une seance terminee, reduite a ce dont les analyses ont besoin.
public struct AnalyticsSession: Equatable, Sendable {
    public var id: UUID
    public var date: Date
    public var durationSeconds: Int
    public var programSessionId: UUID?
    public var sets: [AnalyticsSet]

    public init(
        id: UUID = UUID(),
        date: Date,
        durationSeconds: Int = 0,
        programSessionId: UUID? = nil,
        sets: [AnalyticsSet]
    ) {
        self.id = id
        self.date = date
        self.durationSeconds = durationSeconds
        self.programSessionId = programSessionId
        self.sets = sets
    }

    public var workingSets: [AnalyticsSet] { sets.filter(\.isWorkingSet) }
}

/// Total accompagne du nombre de series dont la valeur etait inconnue.
///
/// Indispensable pour ne jamais confondre « zero » et « donnee manquante » :
/// un tonnage de 0 kg avec 12 series inconnues ne veut pas dire « aucun
/// travail », mais « poids de corps non renseigne ».
public struct MeasuredTotal: Equatable, Sendable {
    public var value: Double
    public var unknownSets: Int

    public init(value: Double, unknownSets: Int = 0) {
        self.value = value
        self.unknownSets = unknownSets
    }

    public static let zero = MeasuredTotal(value: 0)

    public var isComplete: Bool { unknownSets == 0 }

    public static func + (lhs: MeasuredTotal, rhs: MeasuredTotal) -> MeasuredTotal {
        MeasuredTotal(value: lhs.value + rhs.value, unknownSets: lhs.unknownSets + rhs.unknownSets)
    }
}
