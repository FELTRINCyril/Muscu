import Foundation
import SwiftData
import MuscuEngine

struct IntervalRuntimeState: Codable, Equatable {
    var exerciseId: String
    var index: Int
    var segmentEndDate: Date?
    var isPaused: Bool
    var pausedRemaining: TimeInterval
    var showingRepsEntry: Bool
    var totalReps: Int
}

struct AmrapRuntimeState: Codable, Equatable {
    var exerciseId: String
    var endDate: Date?
    var isFinished: Bool
    var counter: Int
}

struct WarmupRuntimeState: Codable, Equatable {
    var stepRaw: String = "choice"
    var endDate: Date?
    var startedAt: Date?
    var cardioMinutes: Int = Warmup.cardioMinutes
}

/// Bloc « For Time » : on mesure le TEMPS mis pour accomplir le travail,
/// avec un plafond facultatif. `startedAt` est une date absolue afin que le
/// chrono reste juste apres une mise en arriere-plan prolongee.
struct ForTimeRuntimeState: Codable, Equatable {
    var exerciseId: String
    var startedAt: Date?
    var finishedAt: Date?
    var completedRounds: Int = 0
    var extraReps: Int = 0
}

struct WorkoutRuntimeState: Codable, Equatable {
    var restEndDate: Date?
    var restTotalSeconds: Int = 0
    var interval: IntervalRuntimeState?
    var amrap: AmrapRuntimeState?
    var forTime: ForTimeRuntimeState?
    var warmup = WarmupRuntimeState()
}

// Une seule instance au plus doit exister : la seance en cours, pour
// permettre la reprise apres interruption de l'app.
@Model
final class ActiveWorkout {
    @Attribute(.unique) var id: UUID = UUID()
    var startedAt: Date = Date()
    var programSessionId: UUID = UUID()
    var exerciseIndex: Int = 0
    var setIndex: Int = 0

    // Phase de la seance ("warmup" ou "running", cf. RunnerPhase dans
    // WorkoutState.swift). Champ optionnel-par-defaut : les ActiveWorkout
    // deja persistees avant l'ajout de l'echauffement n'etaient jamais en
    // phase d'echauffement, "running" est donc un defaut correct pour elles.
    var phaseRaw: String = "running"

    // Snapshot JSON (encodage de [RunExercise], cf. WorkoutState.swift) des
    // exercices de la seance en cours, tels que mutes en memoire par
    // addSet/removeSet/replaceExercise. Sans ce snapshot, un kill+resume de
    // l'app reconstruirait les exercices depuis la ProgramSession source et
    // perdrait ces mutations, desynchronisant exerciseIndex/setIndex (deja
    // persistes) du contenu reel de la seance. Champ optionnel : les
    // ActiveWorkout deja persistees avant son ajout se contentent de nil et
    // retombent sur la reconstruction depuis le programme (cf. `resume`).
    var runExercisesData: Data?
    var runtimeStateData: Data?

    // Snapshot du deroule (WorkoutPlan) et position exacte dans ce deroule
    // (WorkoutPosition), tels que la machine a etats du moteur les manipule.
    // Champs optionnels : une ActiveWorkout persistee avant leur ajout
    // retombe sur `runExercisesData` + `exerciseIndex`/`setIndex`.
    var planData: Data?
    var positionData: Data?

    @Relationship(deleteRule: .cascade, inverse: \CompletedSet.activeWorkout)
    var loggedSets: [CompletedSet] = []

    init(
        id: UUID = UUID(),
        startedAt: Date = Date(),
        programSessionId: UUID,
        exerciseIndex: Int = 0,
        setIndex: Int = 0,
        phaseRaw: String = "running",
        runExercisesData: Data? = nil,
        runtimeStateData: Data? = nil,
        planData: Data? = nil,
        positionData: Data? = nil,
        loggedSets: [CompletedSet] = []
    ) {
        self.id = id
        self.startedAt = startedAt
        self.programSessionId = programSessionId
        self.exerciseIndex = exerciseIndex
        self.setIndex = setIndex
        self.phaseRaw = phaseRaw
        self.runExercisesData = runExercisesData
        self.runtimeStateData = runtimeStateData
        self.planData = planData
        self.positionData = positionData
        self.loggedSets = loggedSets
    }
}

extension DraftProgram {
    func toModel() -> Program {
        let sessionModels = sessions.enumerated().map { sessionIndex, draftSession -> ProgramSession in
            let exerciseModels = draftSession.exercises.enumerated().map { exerciseIndex, draftExercise -> PrescribedExercise in
                PrescribedExercise(
                    exerciseId: draftExercise.exerciseId,
                    displayName: draftExercise.displayName,
                    orderIndex: exerciseIndex,
                    formatRaw: SetFormat.classic.rawValue,
                    sets: draftExercise.sets,
                    repsLower: draftExercise.repsLower,
                    repsUpper: draftExercise.repsUpper,
                    restSeconds: draftExercise.restSeconds,
                    percentOneRepMax: draftExercise.percentOneRepMax
                )
            }
            return ProgramSession(
                name: draftSession.name,
                orderIndex: sessionIndex,
                warmupEnabled: draftSession.warmupEnabled,
                exercises: exerciseModels
            )
        }
        return Program(
            name: name,
            notes: notes,
            sessions: sessionModels
        )
    }
}
