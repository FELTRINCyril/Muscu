import Foundation

/// Format d'execution d'un exercice, cote moteur. Miroir pur du format
/// persiste par l'application : le moteur ne connait ni SwiftData ni SwiftUI.
public enum WorkoutFormat: String, Codable, CaseIterable, Sendable {
    case classic
    case pyramid
    case dropset
    case restPause
    case myoReps
    case intervals
    case emom
    case amrap
    case forTime

    /// Un format chronometre mesure un resultat (temps, tours) plutot qu'une
    /// charge : il occupe un seul « creneau » dans le deroule de la seance.
    public var isTimed: Bool {
        switch self {
        case .intervals, .emom, .amrap, .forTime: return true
        case .classic, .pyramid, .dropset, .restPause, .myoReps: return false
        }
    }
}

/// Type de regroupement d'exercices, cote moteur.
public enum WorkoutGroupKind: String, Codable, CaseIterable, Sendable {
    case single
    case superset
    case triset
    case giantSet
    case circuit

    /// Nombre d'exercices accepte. `nil` = pas de borne haute stricte.
    public var expectedExerciseCount: ClosedRange<Int>? {
        switch self {
        case .single: return 1...1
        case .superset: return 2...2
        case .triset: return 3...3
        case .giantSet: return 4...12
        case .circuit: return 2...20
        }
    }

    public func accepts(exerciseCount: Int) -> Bool {
        guard let range = expectedExerciseCount else { return exerciseCount >= 1 }
        return range.contains(exerciseCount)
    }

    /// Un repos nul n'est valide qu'entre les exercices d'un groupe enchaine.
    public var allowsZeroRestBetweenExercises: Bool { self != .single }
}

/// Paliers de baisse de charge d'un dropset.
public struct DropsetPlan: Codable, Equatable, Sendable {
    /// Valeurs de baisse, en pourcentage de la charge de depart lorsque
    /// `usesPercent`, sinon en kilogrammes. 1 a 5 paliers.
    public var drops: [Double]
    public var usesPercent: Bool
    /// Repos entre paliers. Zero est valide et courant.
    public var restSeconds: Int

    public init(drops: [Double], usesPercent: Bool = true, restSeconds: Int = 0) {
        self.drops = drops
        self.usesPercent = usesPercent
        self.restSeconds = restSeconds
    }

    public var isValid: Bool {
        (1...5).contains(drops.count)
            && drops.allSatisfy { $0.isFinite && $0 > 0 && (usesPercent ? $0 < 100 : $0 <= 500) }
            && (0...600).contains(restSeconds)
    }

    /// Charge de chaque palier a partir de la charge de depart. Les valeurs
    /// sont cumulatives : chaque palier part de la charge du precedent.
    public func loads(startingFrom weight: Double, increment: Double = 2.5) -> [Double] {
        var current = weight
        return drops.map { drop in
            let next = usesPercent ? current * (1 - drop / 100) : current - drop
            current = max(0, Units.roundedToIncrement(next, increment: increment))
            return current
        }
    }
}

/// Serie principale puis mini-series apres un micro-repos.
public struct RestPausePlan: Codable, Equatable, Sendable {
    public var microRestSeconds: Int
    public var maximumMiniSets: Int
    /// Seuil d'arret : en dessous de ce nombre de repetitions, on s'arrete.
    public var minimumReps: Int

    public init(microRestSeconds: Int, maximumMiniSets: Int, minimumReps: Int) {
        self.microRestSeconds = microRestSeconds
        self.maximumMiniSets = maximumMiniSets
        self.minimumReps = minimumReps
    }

    public var isValid: Bool {
        (0...120).contains(microRestSeconds)
            && (1...10).contains(maximumMiniSets)
            && (0...100).contains(minimumReps)
    }
}

/// Serie d'activation puis mini-series courtes.
public struct MyoRepsPlan: Codable, Equatable, Sendable {
    public var activationRepsLower: Int
    public var activationRepsUpper: Int
    public var targetRepsInReserve: Int
    public var miniSetReps: Int
    public var maximumMiniSets: Int
    public var restSeconds: Int

    public init(
        activationRepsLower: Int,
        activationRepsUpper: Int,
        targetRepsInReserve: Int,
        miniSetReps: Int,
        maximumMiniSets: Int,
        restSeconds: Int
    ) {
        self.activationRepsLower = activationRepsLower
        self.activationRepsUpper = activationRepsUpper
        self.targetRepsInReserve = targetRepsInReserve
        self.miniSetReps = miniSetReps
        self.maximumMiniSets = maximumMiniSets
        self.restSeconds = restSeconds
    }

    public var isValid: Bool {
        activationRepsLower > 0
            && activationRepsLower <= activationRepsUpper
            && activationRepsUpper <= 100
            && (0...10).contains(targetRepsInReserve)
            && (1...50).contains(miniSetReps)
            && (1...20).contains(maximumMiniSets)
            && (0...120).contains(restSeconds)
    }
}

/// Un exercice tel que le moteur doit le derouler. Copie autonome : une
/// modification du programme pendant la seance ne doit jamais reecrire ce
/// qui est en cours d'execution.
public struct WorkoutExercisePlan: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var exerciseId: String
    public var displayName: String
    public var format: WorkoutFormat
    public var loadKind: LoadKind
    public var side: SideConvention

    /// Nombre de series de travail (format classique).
    public var setCount: Int
    public var repsLower: Int
    public var repsUpper: Int
    /// Repos apres chaque serie de cet exercice, en secondes.
    public var restSeconds: Int
    public var tempo: Tempo?
    public var targetEffort: EffortRating?
    /// Charge cible saisie sur la prescription (mode « libre »).
    public var targetWeight: Double?
    /// Pilotage par pourcentage : du 1RM estime, ou du maximum de
    /// repetitions pour les exercices au poids du corps.
    public var percentOneRepMax: Double?
    public var percentMaxReps: Double?
    public var notes: String

    // Formats specialises. Un seul est pertinent a la fois, selon `format`.
    public var pyramidReps: [Int]
    public var pyramidMinRest: Int
    public var pyramidMaxRest: Int
    /// Repos choisi apres chaque palier (mode « Par palier »), aligne sur
    /// `pyramidReps`. Vide = repos adaptatif entre `pyramidMinRest` et
    /// `pyramidMaxRest`. Voir `Pyramid.restAfterStep`.
    public var pyramidRestSeconds: [Int]
    public var dropset: DropsetPlan?
    public var restPause: RestPausePlan?
    public var myoReps: MyoRepsPlan?
    public var intervalWorkSeconds: Int
    public var intervalRestSeconds: Int
    public var intervalRounds: Int
    public var countdownSeconds: Int
    public var amrapSeconds: Int
    public var capSeconds: Int

    /// Ce que mesure une serie classique. `nil` = poids x repetitions, ce
    /// qui garde lisibles les deroules persistes avant l'ajout de ce champ.
    public var measure: SetMeasure?
    /// Duree et distance visees par serie, quand la mesure les demande.
    public var targetDurationSeconds: Int?
    public var targetDistanceMeters: Double?

    public init(
        id: UUID = UUID(),
        exerciseId: String,
        displayName: String,
        format: WorkoutFormat = .classic,
        loadKind: LoadKind = .unknown,
        side: SideConvention = .bilateral,
        setCount: Int = 3,
        repsLower: Int = 8,
        repsUpper: Int = 12,
        restSeconds: Int = 90,
        tempo: Tempo? = nil,
        targetEffort: EffortRating? = nil,
        targetWeight: Double? = nil,
        percentOneRepMax: Double? = nil,
        percentMaxReps: Double? = nil,
        notes: String = "",
        pyramidReps: [Int] = [],
        pyramidMinRest: Int = 0,
        pyramidMaxRest: Int = 0,
        pyramidRestSeconds: [Int] = [],
        dropset: DropsetPlan? = nil,
        restPause: RestPausePlan? = nil,
        myoReps: MyoRepsPlan? = nil,
        intervalWorkSeconds: Int = 0,
        intervalRestSeconds: Int = 0,
        intervalRounds: Int = 0,
        countdownSeconds: Int = 0,
        amrapSeconds: Int = 0,
        capSeconds: Int = 0,
        measure: SetMeasure? = nil,
        targetDurationSeconds: Int? = nil,
        targetDistanceMeters: Double? = nil
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.displayName = displayName
        self.format = format
        self.loadKind = loadKind
        self.side = side
        self.setCount = setCount
        self.repsLower = repsLower
        self.repsUpper = repsUpper
        self.restSeconds = restSeconds
        self.tempo = tempo
        self.targetEffort = targetEffort
        self.targetWeight = targetWeight
        self.percentOneRepMax = percentOneRepMax
        self.percentMaxReps = percentMaxReps
        self.notes = notes
        self.pyramidReps = pyramidReps
        self.pyramidMinRest = pyramidMinRest
        self.pyramidMaxRest = pyramidMaxRest
        self.pyramidRestSeconds = pyramidRestSeconds
        self.dropset = dropset
        self.restPause = restPause
        self.myoReps = myoReps
        self.intervalWorkSeconds = intervalWorkSeconds
        self.intervalRestSeconds = intervalRestSeconds
        self.intervalRounds = intervalRounds
        self.countdownSeconds = countdownSeconds
        self.amrapSeconds = amrapSeconds
        self.capSeconds = capSeconds
        self.measure = measure
        self.targetDurationSeconds = targetDurationSeconds
        self.targetDistanceMeters = targetDistanceMeters
    }

    /// Objectif lisible du format, par exemple « Pyramide 2-4-6-4-2 » ou
    /// « 8 x 30 s / 30 s ». Vide pour le format classique, qui a sa propre
    /// presentation detaillee.
    public var objectiveLabel: String {
        switch format {
        case .classic:
            return ""
        case .pyramid:
            return "Pyramide " + pyramidReps.map(String.init).joined(separator: "-")
        case .dropset:
            guard let dropset else { return "Dropset" }
            let unit = dropset.usesPercent ? " %" : " kg"
            return "Dropset -" + dropset.drops.map { String(format: "%g", $0) }.joined(separator: " / -") + unit
        case .restPause:
            guard let restPause else { return "Rest-pause" }
            return "Rest-pause · \(restPause.maximumMiniSets) mini-séries · \(restPause.microRestSeconds) s"
        case .myoReps:
            guard let myoReps else { return "Myo-reps" }
            return "Myo-reps · activation \(myoReps.activationRepsLower)-\(myoReps.activationRepsUpper) · \(myoReps.miniSetReps) reps"
        case .intervals:
            return "\(intervalRounds) x \(intervalWorkSeconds) s / \(intervalRestSeconds) s"
        case .emom:
            return "EMOM \(intervalRounds) min"
        case .amrap:
            return "AMRAP \(amrapSeconds) s"
        case .forTime:
            return capSeconds > 0 ? "For Time (cap \(capSeconds) s)" : "For Time"
        }
    }

    /// Nombre de « creneaux » que compte cet exercice pour l'avancement :
    /// series pour le classique, paliers pour la pyramide, un seul bloc pour
    /// les formats chronometres.
    public var slotCount: Int {
        switch format {
        case .classic, .dropset, .restPause, .myoReps:
            return max(1, setCount)
        case .pyramid:
            return max(1, pyramidReps.count)
        case .intervals, .emom, .amrap, .forTime:
            return 1
        }
    }
}

/// Un noeud de la seance : un exercice seul, un groupe d'exercices enchaines
/// ou un repos explicite.
extension WorkoutExercisePlan {
    /// Decodage tolerant : un deroule persiste AVANT l'ajout des repos par
    /// palier (seance en cours au moment de la mise a jour) ne porte pas
    /// `pyramidRestSeconds` et doit rester lisible — en mode adaptatif.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            exerciseId: try container.decode(String.self, forKey: .exerciseId),
            displayName: try container.decode(String.self, forKey: .displayName),
            format: try container.decode(WorkoutFormat.self, forKey: .format),
            loadKind: try container.decode(LoadKind.self, forKey: .loadKind),
            side: try container.decode(SideConvention.self, forKey: .side),
            setCount: try container.decode(Int.self, forKey: .setCount),
            repsLower: try container.decode(Int.self, forKey: .repsLower),
            repsUpper: try container.decode(Int.self, forKey: .repsUpper),
            restSeconds: try container.decode(Int.self, forKey: .restSeconds),
            tempo: try container.decodeIfPresent(Tempo.self, forKey: .tempo),
            targetEffort: try container.decodeIfPresent(EffortRating.self, forKey: .targetEffort),
            targetWeight: try container.decodeIfPresent(Double.self, forKey: .targetWeight),
            percentOneRepMax: try container.decodeIfPresent(Double.self, forKey: .percentOneRepMax),
            percentMaxReps: try container.decodeIfPresent(Double.self, forKey: .percentMaxReps),
            notes: try container.decode(String.self, forKey: .notes),
            pyramidReps: try container.decode([Int].self, forKey: .pyramidReps),
            pyramidMinRest: try container.decode(Int.self, forKey: .pyramidMinRest),
            pyramidMaxRest: try container.decode(Int.self, forKey: .pyramidMaxRest),
            pyramidRestSeconds: try container.decodeIfPresent([Int].self, forKey: .pyramidRestSeconds) ?? [],
            dropset: try container.decodeIfPresent(DropsetPlan.self, forKey: .dropset),
            restPause: try container.decodeIfPresent(RestPausePlan.self, forKey: .restPause),
            myoReps: try container.decodeIfPresent(MyoRepsPlan.self, forKey: .myoReps),
            intervalWorkSeconds: try container.decode(Int.self, forKey: .intervalWorkSeconds),
            intervalRestSeconds: try container.decode(Int.self, forKey: .intervalRestSeconds),
            intervalRounds: try container.decode(Int.self, forKey: .intervalRounds),
            countdownSeconds: try container.decode(Int.self, forKey: .countdownSeconds),
            amrapSeconds: try container.decode(Int.self, forKey: .amrapSeconds),
            capSeconds: try container.decode(Int.self, forKey: .capSeconds),
            measure: try container.decodeIfPresent(SetMeasure.self, forKey: .measure),
            targetDurationSeconds: try container.decodeIfPresent(Int.self, forKey: .targetDurationSeconds),
            targetDistanceMeters: try container.decodeIfPresent(Double.self, forKey: .targetDistanceMeters)
        )
    }
}

public struct WorkoutNode: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var kind: WorkoutGroupKind
    public var exercises: [WorkoutExercisePlan]
    /// Nombre de tours du groupe. Toujours 1 pour un exercice seul.
    public var rounds: Int
    public var restBetweenExercisesSeconds: Int
    public var restBetweenRoundsSeconds: Int
    public var transitionSeconds: Int

    public init(
        id: UUID = UUID(),
        kind: WorkoutGroupKind,
        exercises: [WorkoutExercisePlan],
        rounds: Int = 1,
        restBetweenExercisesSeconds: Int = 0,
        restBetweenRoundsSeconds: Int = 0,
        transitionSeconds: Int = 0
    ) {
        self.id = id
        self.kind = kind
        self.exercises = exercises
        self.rounds = max(1, rounds)
        self.restBetweenExercisesSeconds = restBetweenExercisesSeconds
        self.restBetweenRoundsSeconds = restBetweenRoundsSeconds
        self.transitionSeconds = transitionSeconds
    }

    public static func single(_ exercise: WorkoutExercisePlan) -> WorkoutNode {
        WorkoutNode(kind: .single, exercises: [exercise], rounds: 1)
    }

    public var isGroup: Bool { kind != .single }

    /// Un groupe derive son nombre de tours de sa configuration ; un exercice
    /// seul derive le sien du nombre de creneaux de l'exercice.
    public var effectiveRounds: Int {
        isGroup ? rounds : (exercises.first?.slotCount ?? 1)
    }
}

/// Le deroule complet d'une seance.
public struct WorkoutPlan: Codable, Equatable, Sendable {
    public var nodes: [WorkoutNode]

    public init(nodes: [WorkoutNode]) {
        self.nodes = nodes
    }

    public var isEmpty: Bool { nodes.allSatisfy { $0.exercises.isEmpty } }

    public var allExercises: [WorkoutExercisePlan] { nodes.flatMap(\.exercises) }
}
