import Foundation

// Format de sortie commun au generateur local et a l'IA (Codable pour l'IA).
public struct DraftProgram: Codable, Equatable, Sendable {
    public var name: String
    public var notes: String
    public var sessions: [DraftSession]

    public init(name: String, notes: String, sessions: [DraftSession]) {
        self.name = name
        self.notes = notes
        self.sessions = sessions
    }
}

public struct DraftSession: Codable, Equatable, Sendable {
    public var name: String
    public var warmupEnabled: Bool
    public var exercises: [DraftExercise]

    public init(name: String, warmupEnabled: Bool, exercises: [DraftExercise]) {
        self.name = name
        self.warmupEnabled = warmupEnabled
        self.exercises = exercises
    }
}

public struct DraftExercise: Codable, Equatable, Sendable {
    public var exerciseId: String      // id du catalogue
    public var displayName: String     // nameFr
    public var sets: Int
    public var repsLower: Int
    public var repsUpper: Int          // == repsLower si reps fixes
    public var restSeconds: Int
    public var percentOneRepMax: Double? // nil = charge libre

    public init(
        exerciseId: String,
        displayName: String,
        sets: Int,
        repsLower: Int,
        repsUpper: Int,
        restSeconds: Int,
        percentOneRepMax: Double? = nil
    ) {
        self.exerciseId = exerciseId
        self.displayName = displayName
        self.sets = sets
        self.repsLower = repsLower
        self.repsUpper = repsUpper
        self.restSeconds = restSeconds
        self.percentOneRepMax = percentOneRepMax
    }
}
