import Foundation
import SwiftData

@Model
final class Program {
    var id: UUID = UUID()
    var name: String = ""
    var notes: String = ""
    var isActive: Bool = false
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \ProgramSession.program)
    var sessions: [ProgramSession] = []

    init(
        id: UUID = UUID(),
        name: String,
        notes: String = "",
        isActive: Bool = false,
        createdAt: Date = Date(),
        sessions: [ProgramSession] = []
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.isActive = isActive
        self.createdAt = createdAt
        self.sessions = sessions
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

    init(
        id: UUID = UUID(),
        name: String,
        orderIndex: Int,
        warmupEnabled: Bool = false,
        exercises: [PrescribedExercise] = []
    ) {
        self.id = id
        self.name = name
        self.orderIndex = orderIndex
        self.warmupEnabled = warmupEnabled
        self.exercises = exercises
    }
}

@Model
final class PrescribedExercise {
    var id: UUID = UUID()
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

    var session: ProgramSession?

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
        notes: String = ""
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
    }
}
