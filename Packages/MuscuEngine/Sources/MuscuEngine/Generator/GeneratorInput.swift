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

public struct GeneratorInput: Codable, Sendable {
    public var goal: Goal
    public var experience: Experience
    public var daysPerWeek: Int          // 2...6
    public var sessionMinutes: Int       // 45, 60, 90
    public var equipment: TrainingEquipment
    public var splitPreference: SplitPreference
    public var priorityMuscles: [String] // cles EN du catalogue
    public var avoidAreas: [String]      // ex: ["lower back", "knees"]

    public init(
        goal: Goal,
        experience: Experience,
        daysPerWeek: Int,
        sessionMinutes: Int,
        equipment: TrainingEquipment,
        splitPreference: SplitPreference,
        priorityMuscles: [String],
        avoidAreas: [String]
    ) {
        self.goal = goal
        self.experience = experience
        self.daysPerWeek = daysPerWeek
        self.sessionMinutes = sessionMinutes
        self.equipment = equipment
        self.splitPreference = splitPreference
        self.priorityMuscles = priorityMuscles
        self.avoidAreas = avoidAreas
    }
}
