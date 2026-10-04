import Foundation

/// Serie d'une seance passee, telle que « Refaire » la lit.
public struct ReplaySourceSet: Equatable, Sendable {
    public var exerciseId: String
    public var displayName: String
    public var orderIndex: Int
    public var subSetIndex: Int
    /// Serie de travail prescrite (ni echauffement, ni approche, ni
    /// supplementaire).
    public var isPrescribedWorkingSet: Bool
    public var weightKilograms: Double
    public var reps: Int
    public var durationSeconds: Int?
    public var distanceMeters: Double?
    public var loadKind: LoadKind
    public var side: SideConvention

    public init(
        exerciseId: String,
        displayName: String,
        orderIndex: Int,
        subSetIndex: Int = 0,
        isPrescribedWorkingSet: Bool = true,
        weightKilograms: Double = 0,
        reps: Int = 0,
        durationSeconds: Int? = nil,
        distanceMeters: Double? = nil,
        loadKind: LoadKind = .unknown,
        side: SideConvention = .bilateral
    ) {
        self.exerciseId = exerciseId
        self.displayName = displayName
        self.orderIndex = orderIndex
        self.subSetIndex = subSetIndex
        self.isPrescribedWorkingSet = isPrescribedWorkingSet
        self.weightKilograms = weightKilograms
        self.reps = reps
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.loadKind = loadKind
        self.side = side
    }
}

/// « Refaire » une seance passee : un deroule de seance libre construit
/// depuis ses series.
///
/// Idee reprise d'Iron (GPL — idee seulement, aucun code). Chaque exercice
/// devient un exercice seul au format classique, dans l'ordre de la seance :
/// les groupes (superset, circuit) et les formats specialises ne sont pas
/// reconstruits — leur configuration (paliers, minutage) n'est pas
/// conservee par les series realisees. Le nombre de series est celui des
/// series de travail principales realisees.
public enum SessionReplay {
    public enum Mode: Sendable {
        /// Charges et repetitions realisees reprises comme cibles.
        case withTargets
        /// Memes exercices, memes nombres de series, aucune valeur.
        case empty
    }

    /// Fourchette proposee quand aucune valeur n'est reprise : la meme que
    /// pour un exercice ajoute en seance.
    public static let defaultRepsLower = 8
    public static let defaultRepsUpper = 12

    public static func plan(
        from sets: [ReplaySourceSet],
        mode: Mode,
        restSeconds: (String) -> Int = { _ in 90 }
    ) -> WorkoutPlan {
        let byOrder = Dictionary(grouping: sets, by: \.orderIndex)
        var nodes: [WorkoutNode] = []
        for orderIndex in byOrder.keys.sorted() {
            guard let group = byOrder[orderIndex], let first = group.first else { continue }
            let main = group.filter { $0.isPrescribedWorkingSet && $0.subSetIndex == 0 }
            nodes.append(.single(exercise(
                from: main,
                first: first,
                mode: mode,
                restSeconds: restSeconds(first.exerciseId)
            )))
        }
        return WorkoutPlan(nodes: nodes)
    }

    private static func exercise(
        from main: [ReplaySourceSet],
        first: ReplaySourceSet,
        mode: Mode,
        restSeconds: Int
    ) -> WorkoutExercisePlan {
        let reference = main.first ?? first
        var exercise = WorkoutExercisePlan(
            exerciseId: first.exerciseId,
            displayName: first.displayName,
            loadKind: reference.loadKind,
            side: reference.side,
            setCount: max(1, main.count),
            repsLower: defaultRepsLower,
            repsUpper: defaultRepsUpper,
            restSeconds: restSeconds
        )

        let measure = measure(of: main)
        if measure != .weightReps {
            exercise.measure = measure
            switch mode {
            case .withTargets:
                exercise.targetDurationSeconds = measure.measuresDuration
                    ? main.compactMap(\.durationSeconds).filter { $0 > 0 }.max() ?? SetMeasure.defaultTargetDurationSeconds
                    : nil
                exercise.targetDistanceMeters = measure.measuresDistance
                    ? main.compactMap(\.distanceMeters).filter { $0 > 0 && $0.isFinite }.max() ?? SetMeasure.defaultTargetDistanceMeters
                    : nil
            case .empty:
                exercise.targetDurationSeconds = measure.measuresDuration ? SetMeasure.defaultTargetDurationSeconds : nil
                exercise.targetDistanceMeters = measure.measuresDistance ? SetMeasure.defaultTargetDistanceMeters : nil
            }
            return exercise
        }

        guard mode == .withTargets else { return exercise }
        let reps = main.map(\.reps).filter { $0 > 0 }
        if let lower = reps.min(), let upper = reps.max() {
            exercise.repsLower = lower
            exercise.repsUpper = upper
        }
        exercise.targetWeight = usualWeight(of: main)
        return exercise
    }

    /// Charge la plus frequente des series de travail ; a egalite, la plus
    /// lourde. `nil` sans charge (poids du corps) : zero n'est pas une cible.
    static func usualWeight(of sets: [ReplaySourceSet]) -> Double? {
        let weights = sets.map(\.weightKilograms).filter { $0 > 0 && $0.isFinite }
        guard !weights.isEmpty else { return nil }
        let counts = Dictionary(grouping: weights, by: { $0 }).mapValues(\.count)
        return counts.max { lhs, rhs in
            lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key < rhs.key
        }?.key
    }

    /// Mesure deduite des series : sans repetitions mais avec une duree ou
    /// une distance, la serie etait mesuree.
    static func measure(of sets: [ReplaySourceSet]) -> SetMeasure {
        guard !sets.isEmpty, sets.allSatisfy({ $0.reps == 0 }) else { return .weightReps }
        let hasDuration = sets.contains { ($0.durationSeconds ?? 0) > 0 }
        let hasDistance = sets.contains { ($0.distanceMeters ?? 0) > 0 }
        switch (hasDuration, hasDistance) {
        case (true, true): return .durationAndDistance
        case (true, false): return .duration
        case (false, true): return .distance
        case (false, false): return .weightReps
        }
    }
}
