import Foundation
import SwiftData
import MuscuEngine

@Model
final class Program {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = ""
    var notes: String = ""
    var isActive: Bool = false
    var createdAt: Date = Date()
    // Metadonnees de synchronisation. `updatedAt` par defaut a la date de
    // creation : les programmes enregistres avant leur ajout obtiennent
    // cette valeur par la migration legere, ce qui reste coherent.
    var updatedAt: Date = Date()
    var deletedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \ProgramSession.program)
    var sessions: [ProgramSession] = []

    init(
        id: UUID = UUID(),
        name: String,
        notes: String = "",
        isActive: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil,
        sessions: [ProgramSession] = []
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.sessions = sessions
    }
}

extension Program {
    var syncMetadata: SyncMetadata {
        SyncMetadata(identifier: id, createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt)
    }

    var orderedSessions: [ProgramSession] { sessions.sorted { $0.orderIndex < $1.orderIndex } }

    func touch(now: Date = .now) { updatedAt = now }
}

@Model
final class ProgramSession {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = ""
    var orderIndex: Int = 0
    var warmupEnabled: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?

    var program: Program?

    @Relationship(deleteRule: .cascade, inverse: \PrescribedExercise.session)
    var exercises: [PrescribedExercise] = []

    // Supprimer une seance supprime ses groupes ; les prescriptions qu'ils
    // contiennent sont detachees (deleteRule .nullify cote ExerciseGroup),
    // jamais supprimees deux fois.
    @Relationship(deleteRule: .cascade, inverse: \ExerciseGroup.session)
    var groups: [ExerciseGroup] = []

    init(
        id: UUID = UUID(),
        name: String,
        orderIndex: Int,
        warmupEnabled: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil,
        exercises: [PrescribedExercise] = []
    ) {
        self.id = id
        self.name = name
        self.orderIndex = orderIndex
        self.warmupEnabled = warmupEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.exercises = exercises
    }
}

extension ProgramSession {
    var orderedExercises: [PrescribedExercise] { exercises.sorted { $0.orderIndex < $1.orderIndex } }

    var orderedGroups: [ExerciseGroup] { groups.sorted { $0.orderIndex < $1.orderIndex } }

    var syncMetadata: SyncMetadata {
        SyncMetadata(identifier: id, createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt)
    }

    func touch(now: Date = .now) {
        updatedAt = now
        program?.touch(now: now)
    }
}

@Model
final class PrescribedExercise {
    @Attribute(.unique) var id: UUID = UUID()
    var exerciseId: String = ""
    var displayName: String = ""
    var orderIndex: Int = 0
    var formatRaw: String = SetFormat.classic.rawValue
    var sets: Int = 0
    var repsLower: Int = 0
    var repsUpper: Int = 0
    var restSeconds: Int = 0
    var percentOneRepMax: Double?
    var percentMaxReps: Double?
    // Poids cible optionnel en mode de charge "Libre" : quand renseigne,
    // prefill prioritaire dans le runner (cf. WorkoutState.suggestedWeight),
    // avant le dernier poids logge. nil = comportement inchange.
    var targetWeight: Double?
    var pyramidReps: [Int] = []
    var pyramidMinRest: Int = 0
    var pyramidMaxRest: Int = 0
    var intervalWork: Int = 0
    var intervalRest: Int = 0
    var intervalRounds: Int = 0
    var amrapSeconds: Int = 0
    var notes: String = ""

    // MARK: - Champs v3 (tous facultatifs, migration legere)

    /// Position dans son groupe (superset, circuit...). Ignore hors groupe.
    var groupOrderIndex: Int = 0
    /// Tempo en quatre phases, notation `a-b-c-d`. Vide = non prescrit.
    var tempoNotation: String = ""
    /// Effort cible encode (`EffortRating`). nil = non prescrit.
    var targetEffortData: Data?
    /// Regle de progression encodee (`ProgressionRule`). nil = regle du profil.
    var progressionRuleData: Data?
    /// Type de charge prescrit. Vide = deduit du catalogue a l'execution.
    var loadKindRaw: String = ""
    /// Convention unilaterale explicite.
    var sideConventionRaw: String = SideConvention.bilateral.rawValue
    /// Duree ou distance cible pour les exercices qui ne se comptent pas en
    /// repetitions. Zero = non prescrit.
    var targetDurationSeconds: Int = 0
    var targetDistanceMeters: Double = 0

    // Dropset : paliers de baisse de charge apres la serie principale.
    // Valeurs en pourcentage de la charge de depart lorsque
    // `dropsetUsesPercent`, sinon en kilogrammes.
    var dropsetDrops: [Double] = []
    var dropsetUsesPercent: Bool = true
    var dropsetRestSeconds: Int = 0

    // Rest-pause : micro-repos et mini-series apres la serie principale.
    var restPauseMicroRestSeconds: Int = 0
    var restPauseMaxMiniSets: Int = 0
    /// Seuil d'arret : en dessous de ce nombre de repetitions, on arrete.
    var restPauseMinimumReps: Int = 0

    // Myo-reps : serie d'activation puis mini-series courtes.
    var myoRepsActivationLower: Int = 0
    var myoRepsActivationUpper: Int = 0
    var myoRepsTargetRepsInReserve: Int = 0
    var myoRepsMiniSetReps: Int = 0
    var myoRepsMaxMiniSets: Int = 0
    var myoRepsRestSeconds: Int = 0

    // Intervalles etendus : compte a rebours et preparation.
    var intervalCountdownSeconds: Int = 0
    /// For Time : plafond de temps en secondes. Zero = pas de plafond.
    var forTimeCapSeconds: Int = 0

    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?

    var session: ProgramSession?
    var group: ExerciseGroup?

    init(
        id: UUID = UUID(),
        exerciseId: String,
        displayName: String,
        orderIndex: Int,
        formatRaw: String = SetFormat.classic.rawValue,
        sets: Int = 0,
        repsLower: Int = 0,
        repsUpper: Int = 0,
        restSeconds: Int = 0,
        percentOneRepMax: Double? = nil,
        percentMaxReps: Double? = nil,
        targetWeight: Double? = nil,
        pyramidReps: [Int] = [],
        pyramidMinRest: Int = 0,
        pyramidMaxRest: Int = 0,
        intervalWork: Int = 0,
        intervalRest: Int = 0,
        intervalRounds: Int = 0,
        amrapSeconds: Int = 0,
        notes: String = "",
        groupOrderIndex: Int = 0,
        tempoNotation: String = "",
        targetEffortData: Data? = nil,
        progressionRuleData: Data? = nil,
        loadKindRaw: String = "",
        sideConventionRaw: String = SideConvention.bilateral.rawValue,
        targetDurationSeconds: Int = 0,
        targetDistanceMeters: Double = 0,
        dropsetDrops: [Double] = [],
        dropsetUsesPercent: Bool = true,
        dropsetRestSeconds: Int = 0,
        restPauseMicroRestSeconds: Int = 0,
        restPauseMaxMiniSets: Int = 0,
        restPauseMinimumReps: Int = 0,
        myoRepsActivationLower: Int = 0,
        myoRepsActivationUpper: Int = 0,
        myoRepsTargetRepsInReserve: Int = 0,
        myoRepsMiniSetReps: Int = 0,
        myoRepsMaxMiniSets: Int = 0,
        myoRepsRestSeconds: Int = 0,
        intervalCountdownSeconds: Int = 0,
        forTimeCapSeconds: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.displayName = displayName
        self.orderIndex = orderIndex
        self.formatRaw = formatRaw
        self.sets = sets
        self.repsLower = repsLower
        self.repsUpper = repsUpper
        self.restSeconds = restSeconds
        self.percentOneRepMax = percentOneRepMax
        self.percentMaxReps = percentMaxReps
        self.targetWeight = targetWeight
        self.pyramidReps = pyramidReps
        self.pyramidMinRest = pyramidMinRest
        self.pyramidMaxRest = pyramidMaxRest
        self.intervalWork = intervalWork
        self.intervalRest = intervalRest
        self.intervalRounds = intervalRounds
        self.amrapSeconds = amrapSeconds
        self.notes = notes
        self.groupOrderIndex = groupOrderIndex
        self.tempoNotation = tempoNotation
        self.targetEffortData = targetEffortData
        self.progressionRuleData = progressionRuleData
        self.loadKindRaw = loadKindRaw
        self.sideConventionRaw = sideConventionRaw
        self.targetDurationSeconds = targetDurationSeconds
        self.targetDistanceMeters = targetDistanceMeters
        self.dropsetDrops = dropsetDrops
        self.dropsetUsesPercent = dropsetUsesPercent
        self.dropsetRestSeconds = dropsetRestSeconds
        self.restPauseMicroRestSeconds = restPauseMicroRestSeconds
        self.restPauseMaxMiniSets = restPauseMaxMiniSets
        self.restPauseMinimumReps = restPauseMinimumReps
        self.myoRepsActivationLower = myoRepsActivationLower
        self.myoRepsActivationUpper = myoRepsActivationUpper
        self.myoRepsTargetRepsInReserve = myoRepsTargetRepsInReserve
        self.myoRepsMiniSetReps = myoRepsMiniSetReps
        self.myoRepsMaxMiniSets = myoRepsMaxMiniSets
        self.myoRepsRestSeconds = myoRepsRestSeconds
        self.intervalCountdownSeconds = intervalCountdownSeconds
        self.forTimeCapSeconds = forTimeCapSeconds
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

extension PrescribedExercise {
    /// Tempo prescrit, ou `nil` si la notation est vide ou invalide : on ne
    /// devine jamais un tempo a partir d'une saisie incorrecte.
    var tempo: Tempo? {
        get { tempoNotation.isEmpty ? nil : Tempo(notation: tempoNotation) }
        set { tempoNotation = newValue?.notation ?? "" }
    }

    var targetEffort: EffortRating? {
        get {
            guard let data = targetEffortData,
                  let effort = try? JSONDecoder().decode(EffortRating.self, from: data),
                  effort.isValid else { return nil }
            return effort
        }
        set { targetEffortData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    /// Regle de progression propre a cette prescription. `nil` signifie
    /// « utiliser la regle par defaut du profil ».
    var progressionRule: ProgressionRule? {
        get {
            guard let data = progressionRuleData,
                  let rule = try? JSONDecoder().decode(ProgressionRule.self, from: data),
                  rule.isValid else { return nil }
            return rule
        }
        set { progressionRuleData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    /// Type de charge prescrit explicitement. `nil` = a deduire du catalogue.
    var prescribedLoadKind: LoadKind? {
        get { loadKindRaw.isEmpty ? nil : LoadKind(rawValue: loadKindRaw) }
        set { loadKindRaw = newValue?.rawValue ?? "" }
    }

    var sideConvention: SideConvention {
        get { SideConvention(rawValue: sideConventionRaw) ?? .bilateral }
        set { sideConventionRaw = newValue.rawValue }
    }

    var syncMetadata: SyncMetadata {
        SyncMetadata(identifier: id, createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt)
    }

    func touch(now: Date = .now) {
        updatedAt = now
        session?.touch(now: now)
    }
}
