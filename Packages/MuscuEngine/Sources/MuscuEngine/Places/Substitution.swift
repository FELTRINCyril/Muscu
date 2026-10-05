import Foundation

/// Raison d'une substitution proposee. Chaque proposition porte ses raisons :
/// l'utilisateur doit pouvoir juger le remplacement, pas subir un classement
/// opaque.
public enum SubstitutionReason: Hashable, Sendable {
    case sameMovementPattern(String)
    case sharedPrimaryMuscles([String])
    case sameMechanic(String)
    case equipmentAvailable(String)
    case sameLevel(String)
    case easierLevel(String)

    public var explanation: String {
        switch self {
        case .sameMovementPattern(let pattern):
            return "Même type de mouvement (\(pattern))."
        case .sharedPrimaryMuscles(let muscles):
            let names = muscles.map(FrenchLabels.muscle).joined(separator: ", ")
            return "Mêmes muscles principaux : \(names)."
        case .sameMechanic(let mechanic):
            return mechanic == "compound" ? "Mouvement polyarticulaire, comme l’original." : "Mouvement d’isolation, comme l’original."
        case .equipmentAvailable(let equipment):
            return "Matériel disponible sur place : \(FrenchLabels.equipment(equipment))."
        case .sameLevel(let level):
            return "Même niveau (\(FrenchLabels.level(level)))."
        case .easierLevel(let level):
            return "Niveau plus accessible (\(FrenchLabels.level(level)))."
        }
    }
}

public struct SubstitutionCandidate: Hashable, Sendable, Identifiable {
    public let exercise: CatalogExercise
    public let score: Int
    public let reasons: [SubstitutionReason]

    public var id: String { exercise.id }

    public init(exercise: CatalogExercise, score: Int, reasons: [SubstitutionReason]) {
        self.exercise = exercise
        self.score = score
        self.reasons = reasons
    }

    public static func == (lhs: SubstitutionCandidate, rhs: SubstitutionCandidate) -> Bool {
        lhs.exercise.id == rhs.exercise.id && lhs.score == rhs.score && lhs.reasons == rhs.reasons
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(exercise.id)
        hasher.combine(score)
    }
}

/// Classement des remplacements possibles pour un exercice.
///
/// Le classement est DETERMINISTE : a egalite de score, l'ordre suit le nom,
/// pour qu'une meme situation propose toujours la meme liste.
public enum SubstitutionFinder {
    private enum Weight {
        static let sharedPrimaryMuscle = 40
        static let movementPattern = 25
        static let mechanic = 15
        static let equipment = 10
        static let level = 5
    }

    public static func candidates(
        for exercise: CatalogExercise,
        in catalog: [CatalogExercise],
        inventory: EquipmentInventory = EquipmentInventory(),
        level: String? = nil,
        limit: Int = 10
    ) -> [SubstitutionCandidate] {
        let originalMuscles = Set(exercise.primaryMuscles)
        guard !originalMuscles.isEmpty else { return [] }

        var scored: [SubstitutionCandidate] = []

        for candidate in catalog where candidate.id != exercise.id {
            guard inventory.allows(equipment: candidate.equipment) else { continue }

            let shared = originalMuscles.intersection(candidate.primaryMuscles)
            guard !shared.isEmpty else { continue }

            var score = shared.count * Weight.sharedPrimaryMuscle
            var reasons: [SubstitutionReason] = [.sharedPrimaryMuscles(shared.sorted())]

            if let force = exercise.force, candidate.force == force {
                score += Weight.movementPattern
                reasons.append(.sameMovementPattern(FrenchLabels.force(force)))
            }
            if let mechanic = exercise.mechanic, candidate.mechanic == mechanic {
                score += Weight.mechanic
                reasons.append(.sameMechanic(mechanic))
            }
            if let equipment = candidate.equipment, !inventory.isEmpty, inventory.equipmentIds.contains(equipment) {
                score += Weight.equipment
                reasons.append(.equipmentAvailable(equipment))
            }
            if let level {
                if candidate.level == level {
                    score += Weight.level
                    reasons.append(.sameLevel(candidate.level))
                } else if levelRank(candidate.level) < levelRank(level) {
                    reasons.append(.easierLevel(candidate.level))
                }
            }

            scored.append(SubstitutionCandidate(exercise: candidate, score: score, reasons: reasons))
        }

        return scored
            .sorted { left, right in
                if left.score != right.score { return left.score > right.score }
                return left.exercise.nameFr.localizedCaseInsensitiveCompare(right.exercise.nameFr) == .orderedAscending
            }
            .prefix(limit)
            .map { $0 }
    }

    private static func levelRank(_ level: String) -> Int {
        switch level {
        case "beginner": return 0
        case "intermediate": return 1
        case "expert": return 2
        default: return 1
        }
    }
}
