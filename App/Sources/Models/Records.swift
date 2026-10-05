import Foundation
import SwiftData
import MuscuEngine

@Model
final class ExerciseRecord {
    @Attribute(.unique) var id: UUID = UUID()
    var exerciseId: String = ""
    var displayName: String = ""
    var oneRepMax: Double?
    var maxReps: Int?
    var updatedAt: Date = Date()
    var createdAt: Date = Date()
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        exerciseId: String,
        displayName: String,
        oneRepMax: Double? = nil,
        maxReps: Int? = nil,
        updatedAt: Date = Date(),
        createdAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.displayName = displayName
        self.oneRepMax = oneRepMax
        self.maxReps = maxReps
        self.updatedAt = updatedAt
        self.createdAt = createdAt
        self.deletedAt = deletedAt
    }
}

extension ExerciseRecord {
    var syncMetadata: SyncMetadata {
        SyncMetadata(identifier: id, createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt)
    }
}
