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
}
