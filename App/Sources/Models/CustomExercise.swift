import Foundation
import SwiftData

@Model
final class CustomExercise {
    var id: UUID = UUID()
    var name: String = ""
    var primaryMuscles: [String] = []
    var equipment: String = ""
    var notes: String = ""

    init(
        id: UUID = UUID(),
        name: String,
        primaryMuscles: [String] = [],
        equipment: String = "",
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.primaryMuscles = primaryMuscles
        self.equipment = equipment
        self.notes = notes
    }
}
