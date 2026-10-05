import Foundation
import SwiftData

/// Premiere version du schema reellement ecrite sur disque. Ces types sont
/// FIGES : ils decrivent l'etat d'un store existant et ne doivent jamais
/// suivre l'evolution des modeles courants, sous peine de rendre la
/// migration impossible (« Cannot use staged migration with an unknown model
/// version »).
///
/// Aucun code applicatif n'utilise ces types en dehors du plan de migration
/// et de ses tests.
enum MuscuSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Program.self,
            ProgramSession.self,
            PrescribedExercise.self,
            CompletedSession.self,
            CompletedSet.self,
            ExerciseRecord.self,
            CustomExercise.self,
            ActiveWorkout.self,
        ]
    }

    @Model
    final class Program {
        var id: UUID = UUID()
        var name: String = ""
        var notes: String = ""
        var isActive: Bool = false
        var createdAt: Date = Date()

        @Relationship(deleteRule: .cascade, inverse: \ProgramSession.program)
        var sessions: [ProgramSession] = []

        init(id: UUID = UUID(), name: String, notes: String = "", isActive: Bool = false, createdAt: Date = Date()) {
            self.id = id
            self.name = name
            self.notes = notes
            self.isActive = isActive
            self.createdAt = createdAt
        }
    }

    @Model
    final class ProgramSession {
        var id: UUID = UUID()
        var name: String = ""
        var orderIndex: Int = 0
        var warmupEnabled: Bool = false

        var program: Program?

        @Relationship(deleteRule: .cascade, inverse: \PrescribedExercise.session)
        var exercises: [PrescribedExercise] = []

        init(id: UUID = UUID(), name: String, orderIndex: Int, warmupEnabled: Bool = false) {
            self.id = id
            self.name = name
            self.orderIndex = orderIndex
            self.warmupEnabled = warmupEnabled
        }
    }

    @Model
    final class PrescribedExercise {
        var id: UUID = UUID()
        var exerciseId: String = ""
        var displayName: String = ""
        var orderIndex: Int = 0
        var formatRaw: String = "classic"
        var sets: Int = 0
        var repsLower: Int = 0
        var repsUpper: Int = 0
        var restSeconds: Int = 0
        var percentOneRepMax: Double?
        var percentMaxReps: Double?
        var targetWeight: Double?
        var pyramidReps: [Int] = []
        var pyramidMinRest: Int = 0
        var pyramidMaxRest: Int = 0
        var intervalWork: Int = 0
        var intervalRest: Int = 0
        var intervalRounds: Int = 0
        var amrapSeconds: Int = 0
        var notes: String = ""

        var session: ProgramSession?

        init(id: UUID = UUID(), exerciseId: String, displayName: String, orderIndex: Int) {
            self.id = id
            self.exerciseId = exerciseId
            self.displayName = displayName
            self.orderIndex = orderIndex
        }
    }

    @Model
    final class CompletedSession {
        var id: UUID = UUID()
        var date: Date = Date()
        var programName: String = ""
        var sessionName: String = ""
        var durationSeconds: Int = 0

        @Relationship(deleteRule: .cascade, inverse: \CompletedSet.session)
        var sets: [CompletedSet] = []

        init(id: UUID = UUID(), date: Date = Date(), programName: String, sessionName: String, durationSeconds: Int = 0) {
            self.id = id
            self.date = date
            self.programName = programName
            self.sessionName = sessionName
            self.durationSeconds = durationSeconds
        }
    }

    @Model
    final class CompletedSet {
        var id: UUID = UUID()
        var exerciseId: String = ""
        var displayName: String = ""
        var orderIndex: Int = 0
        var setIndex: Int = 0
        var weight: Double = 0
        var reps: Int = 0
        var isWarmup: Bool = false

        var session: CompletedSession?
        var activeWorkout: ActiveWorkout?

        init(id: UUID = UUID(), exerciseId: String, displayName: String, orderIndex: Int, setIndex: Int, weight: Double, reps: Int, isWarmup: Bool = false) {
            self.id = id
            self.exerciseId = exerciseId
            self.displayName = displayName
            self.orderIndex = orderIndex
            self.setIndex = setIndex
            self.weight = weight
            self.reps = reps
            self.isWarmup = isWarmup
        }
    }

    @Model
    final class ExerciseRecord {
        var id: UUID = UUID()
        var exerciseId: String = ""
        var displayName: String = ""
        var oneRepMax: Double?
        var maxReps: Int?
        var updatedAt: Date = Date()

        init(id: UUID = UUID(), exerciseId: String, displayName: String) {
            self.id = id
            self.exerciseId = exerciseId
            self.displayName = displayName
        }
    }

    @Model
    final class CustomExercise {
        var id: UUID = UUID()
        var name: String = ""
        var primaryMuscles: [String] = []
        var equipment: String = ""
        var notes: String = ""

        init(id: UUID = UUID(), name: String) {
            self.id = id
            self.name = name
        }
    }

    @Model
    final class ActiveWorkout {
        var id: UUID = UUID()
        var startedAt: Date = Date()
        var programSessionId: UUID = UUID()
        var exerciseIndex: Int = 0
        var setIndex: Int = 0
        var phaseRaw: String = "running"
        var runExercisesData: Data?

        @Relationship(deleteRule: .cascade, inverse: \CompletedSet.activeWorkout)
        var loggedSets: [CompletedSet] = []

        init(id: UUID = UUID(), startedAt: Date = Date(), programSessionId: UUID) {
            self.id = id
            self.startedAt = startedAt
            self.programSessionId = programSessionId
        }
    }
}
