import Foundation
import SwiftData
import MuscuEngine

@Model
final class CustomExercise {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = ""
    var primaryMuscles: [String] = []
    var equipment: String = ""
    var notes: String = ""

    // MARK: - Champs v3 (facultatifs)

    var secondaryMuscles: [String] = []
    /// Mouvement principal (push, pull, squat, hinge, carry, core...).
    var movementPattern: String = ""
    /// Type de charge par defaut de cet exercice personnalise.
    var defaultLoadKindRaw: String = LoadKind.external.rawValue
    var isUnilateral: Bool = false
    var tags: [String] = []
    var isFavorite: Bool = false

    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        primaryMuscles: [String] = [],
        equipment: String = "",
        notes: String = "",
        secondaryMuscles: [String] = [],
        movementPattern: String = "",
        defaultLoadKindRaw: String = LoadKind.external.rawValue,
        isUnilateral: Bool = false,
        tags: [String] = [],
        isFavorite: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.primaryMuscles = primaryMuscles
        self.equipment = equipment
        self.notes = notes
        self.secondaryMuscles = secondaryMuscles
        self.movementPattern = movementPattern
        self.defaultLoadKindRaw = defaultLoadKindRaw
        self.isUnilateral = isUnilateral
        self.tags = tags
        self.isFavorite = isFavorite
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

extension CustomExercise {
    var defaultLoadKind: LoadKind {
        get { LoadKind(rawValue: defaultLoadKindRaw) ?? .external }
        set { defaultLoadKindRaw = newValue.rawValue }
    }

    var syncMetadata: SyncMetadata {
        SyncMetadata(identifier: id, createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt)
    }
}
