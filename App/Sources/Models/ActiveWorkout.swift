import Foundation
import SwiftData
import MuscuEngine

// Une seule instance au plus doit exister : la seance en cours, pour
// permettre la reprise apres interruption de l'app.
@Model
final class ActiveWorkout {
    var id: UUID = UUID()
    var startedAt: Date = Date()
    var programSessionId: UUID = UUID()
    var exerciseIndex: Int = 0
    var setIndex: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \CompletedSet.activeWorkout)
    var loggedSets: [CompletedSet] = []

    init(
        id: UUID = UUID(),
        startedAt: Date = Date(),
        programSessionId: UUID,
        exerciseIndex: Int = 0,
        setIndex: Int = 0,
        loggedSets: [CompletedSet] = []
    ) {
        self.id = id
        self.startedAt = startedAt
        self.programSessionId = programSessionId
        self.exerciseIndex = exerciseIndex
        self.setIndex = setIndex
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
