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
    public var variation: Int            // increment a chaque "Regenerer" pour faire tourner les choix

    public init(
        goal: Goal,
        experience: Experience,
        daysPerWeek: Int,
        sessionMinutes: Int,
        equipment: TrainingEquipment,
        splitPreference: SplitPreference,
        priorityMuscles: [String],
        avoidAreas: [String],
        variation: Int = 0
    ) {
        self.goal = goal
        self.experience = experience
        self.daysPerWeek = daysPerWeek
        self.sessionMinutes = sessionMinutes
        self.equipment = equipment
        self.splitPreference = splitPreference
        self.priorityMuscles = priorityMuscles
        self.avoidAreas = avoidAreas
        self.variation = variation
    }

    // Decodage retro-compatible (les autres champs restent synthetises)
    private enum CodingKeys: String, CodingKey {
        case goal
        case experience
        case daysPerWeek
        case sessionMinutes
        case equipment
        case splitPreference
        case priorityMuscles
        case avoidAreas
        case variation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        goal = try container.decode(Goal.self, forKey: .goal)
        experience = try container.decode(Experience.self, forKey: .experience)
        daysPerWeek = try container.decode(Int.self, forKey: .daysPerWeek)
        sessionMinutes = try container.decode(Int.self, forKey: .sessionMinutes)
        equipment = try container.decode(TrainingEquipment.self, forKey: .equipment)
        splitPreference = try container.decode(SplitPreference.self, forKey: .splitPreference)
        priorityMuscles = try container.decode([String].self, forKey: .priorityMuscles)
        avoidAreas = try container.decode([String].self, forKey: .avoidAreas)
        variation = try container.decodeIfPresent(Int.self, forKey: .variation) ?? 0
    }
}
