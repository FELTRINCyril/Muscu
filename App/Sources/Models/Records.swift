import Foundation
import SwiftData

@Model
final class ExerciseRecord {
    var id: UUID = UUID()
    var exerciseId: String = ""
    var displayName: String = ""
    var oneRepMax: Double?
    var maxReps: Int?
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        exerciseId: String,
        displayName: String,
        oneRepMax: Double? = nil,
        maxReps: Int? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.displayName = displayName
        self.oneRepMax = oneRepMax
        self.maxReps = maxReps
        self.updatedAt = updatedAt
    }
}
