import Foundation
import MuscuEngine

/// Ancien format du snapshot d'exercices persiste sur `ActiveWorkout`
/// (`runExercisesData`), conserve UNIQUEMENT en lecture pour reprendre une
/// séance commencée avant l'arrivée du déroulé unifié (`WorkoutPlan`).
///
/// Rien n'écrit plus ce format : `WorkoutState` persiste désormais un
/// `WorkoutPlan` et une `WorkoutPosition`.
struct LegacyRunExercise: Codable {
    var id: UUID
    var exerciseId: String
    var displayName: String
    var format: String
    var sets: Int
    var repsLower: Int
    var repsUpper: Int
    var restSeconds: Int
    var percentOneRepMax: Double?
    var percentMaxReps: Double?
    var targetWeight: Double?
    var notes: String
    var orderIndex: Int
    var pyramidReps: [Int]
    var pyramidMinRest: Int
    var pyramidMaxRest: Int
    var intervalWork: Int
    var intervalRest: Int
    var intervalRounds: Int
    var amrapSeconds: Int

    private enum CodingKeys: String, CodingKey {
        case id, exerciseId, displayName, format, sets, repsLower, repsUpper
        case restSeconds, percentOneRepMax, percentMaxReps, targetWeight, notes, orderIndex
        case pyramidReps, pyramidMinRest, pyramidMaxRest
        case intervalWork, intervalRest, intervalRounds, amrapSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        exerciseId = try container.decode(String.self, forKey: .exerciseId)
        displayName = try container.decode(String.self, forKey: .displayName)
        format = try container.decode(String.self, forKey: .format)
        sets = try container.decode(Int.self, forKey: .sets)
        repsLower = try container.decode(Int.self, forKey: .repsLower)
        repsUpper = try container.decode(Int.self, forKey: .repsUpper)
        restSeconds = try container.decode(Int.self, forKey: .restSeconds)
        percentOneRepMax = try container.decodeIfPresent(Double.self, forKey: .percentOneRepMax)
        percentMaxReps = try container.decodeIfPresent(Double.self, forKey: .percentMaxReps)
        targetWeight = try container.decodeIfPresent(Double.self, forKey: .targetWeight)
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        orderIndex = try container.decode(Int.self, forKey: .orderIndex)
        pyramidReps = try container.decodeIfPresent([Int].self, forKey: .pyramidReps) ?? []
        pyramidMinRest = try container.decodeIfPresent(Int.self, forKey: .pyramidMinRest) ?? 0
        pyramidMaxRest = try container.decodeIfPresent(Int.self, forKey: .pyramidMaxRest) ?? 0
        intervalWork = try container.decodeIfPresent(Int.self, forKey: .intervalWork) ?? 0
        intervalRest = try container.decodeIfPresent(Int.self, forKey: .intervalRest) ?? 0
        intervalRounds = try container.decodeIfPresent(Int.self, forKey: .intervalRounds) ?? 0
        amrapSeconds = try container.decodeIfPresent(Int.self, forKey: .amrapSeconds) ?? 0
    }

    /// Conversion vers le déroulé unifié. Le type de charge n'était pas
    /// persisté dans l'ancien format : il reste `unknown`, jamais deviné.
    var workoutExercisePlan: WorkoutExercisePlan {
        WorkoutExercisePlan(
            id: id,
            exerciseId: exerciseId,
            displayName: displayName,
            format: WorkoutFormat(rawValue: format) ?? .classic,
            loadKind: .unknown,
            setCount: sets,
            repsLower: repsLower,
            repsUpper: repsUpper,
            restSeconds: restSeconds,
            targetWeight: targetWeight,
            percentOneRepMax: percentOneRepMax,
            percentMaxReps: percentMaxReps,
            notes: notes,
            pyramidReps: pyramidReps,
            pyramidMinRest: pyramidMinRest,
            pyramidMaxRest: pyramidMaxRest,
            intervalWorkSeconds: intervalWork,
            intervalRestSeconds: intervalRest,
            intervalRounds: intervalRounds,
            amrapSeconds: amrapSeconds
        )
    }

    /// Reconstruit un déroulé plat à partir d'un ancien snapshot. Les
    /// séances commencées avant les groupes n'en contenaient aucun.
    static func plan(from data: Data) -> WorkoutPlan? {
        guard let decoded = try? JSONDecoder().decode([LegacyRunExercise].self, from: data), !decoded.isEmpty else {
            return nil
        }
        return WorkoutPlan(nodes: decoded.map { .single($0.workoutExercisePlan) })
    }
}
