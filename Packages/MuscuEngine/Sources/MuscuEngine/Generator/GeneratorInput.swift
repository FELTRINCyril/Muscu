import Foundation

public enum Goal: String, Codable, CaseIterable, Sendable {
    case hypertrophy, strength, fatLoss, endurance, pullUpProgress, calisthenics
}

public enum Experience: String, Codable, CaseIterable, Sendable {
    case beginner, intermediate, advanced
}

public enum TrainingEquipment: String, Codable, CaseIterable, Sendable {
    case fullGym, homeGym, bodyweight
}

public enum SplitPreference: String, Codable, CaseIterable, Sendable {
    case auto, fullBody, upperLower, ppl, pplul, ulppl, arnold, pushPullUpperLower
}

public struct GeneratorInput: Codable, Equatable, Sendable {
    public var goal: Goal
    public var experience: Experience
    public var daysPerWeek: Int          // 2...6
    public var sessionMinutes: Int       // 45, 60, 90
    public var equipment: TrainingEquipment
    public var splitPreference: SplitPreference
    public var priorityMuscles: [String] // cles EN du catalogue
    public var avoidAreas: [String]      // ex: ["lower back", "knees"]
    /// Exercices explicitement refuses par l'athlete. Le generateur ne les
    /// propose jamais, et le validateur refuse tout programme qui en contient.
    public var excludedExerciseIds: [String]
    /// Inventaire du lieu ou la seance aura lieu. `nil` ou inventaire vide =
    /// aucune contrainte supplementaire : on ne masque jamais d'exercice tant
    /// que rien n'a ete declare.
    public var inventory: EquipmentInventory?

    public init(
        goal: Goal,
        experience: Experience,
        daysPerWeek: Int,
        sessionMinutes: Int,
        equipment: TrainingEquipment,
        splitPreference: SplitPreference,
        priorityMuscles: [String],
        avoidAreas: [String],
        excludedExerciseIds: [String] = [],
        inventory: EquipmentInventory? = nil
    ) {
        self.goal = goal
        self.experience = experience
        self.daysPerWeek = daysPerWeek
        self.sessionMinutes = sessionMinutes
        self.equipment = equipment
        self.splitPreference = splitPreference
        self.priorityMuscles = priorityMuscles
        self.avoidAreas = avoidAreas
        self.excludedExerciseIds = excludedExerciseIds
        self.inventory = inventory
    }
}
