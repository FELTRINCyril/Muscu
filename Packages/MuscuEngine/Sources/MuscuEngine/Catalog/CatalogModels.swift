import Foundation

/// Un exercice du catalogue, tel que decode depuis exercises_fr.json.
public struct CatalogExercise: Codable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let nameFr: String
    public let force: String?
    public let level: String
    public let mechanic: String?
    public let equipment: String?
    public let primaryMuscles: [String]
    public let secondaryMuscles: [String]
    public let category: String
    public let images: [String]
    public let instructionsFr: [String]

    public init(
        id: String,
        name: String,
        nameFr: String,
        force: String? = nil,
        level: String = "intermediate",
        mechanic: String? = nil,
        equipment: String? = nil,
        primaryMuscles: [String] = [],
        secondaryMuscles: [String] = [],
        category: String = "strength",
        images: [String] = [],
        instructionsFr: [String] = []
    ) {
        self.id = id
        self.name = name
        self.nameFr = nameFr
        self.force = force
        self.level = level
        self.mechanic = mechanic
        self.equipment = equipment
        self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
        self.category = category
        self.images = images
        self.instructionsFr = instructionsFr
    }
}
