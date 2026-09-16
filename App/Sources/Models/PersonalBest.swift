import Foundation
import SwiftData
import MuscuEngine

/// Nature d'un record. Chaque nature a sa propre unite et son propre sens
/// de comparaison, afin qu'un record de temps ne soit jamais compare a un
/// record de charge.
enum PersonalBestKind: String, Codable, CaseIterable, Sendable {
    /// Charge maximale reellement portee (kg).
    case maxWeight
    /// 1RM estime (kg) — une estimation, jamais une performance mesuree.
    case estimatedOneRepMax
    /// Repetitions maximales sur une serie.
    case maxReps
    /// Tonnage maximal sur une seance pour cet exercice (kg).
    case maxSessionVolume
    /// Meilleur temps sur un format chronometre (secondes, plus bas = mieux).
    case bestTime
    /// Tours complets maximum (circuit, AMRAP).
    case maxRounds
    /// Distance maximale (metres).
    case maxDistance

    /// Un record de temps s'ameliore en DIMINUANT ; tous les autres en augmentant.
    var lowerIsBetter: Bool { self == .bestTime }

    var displayName: String {
        switch self {
        case .maxWeight: return String(localized: "Charge maximale")
        case .estimatedOneRepMax: return String(localized: "1RM estimé")
        case .maxReps: return String(localized: "Répétitions maximales")
        case .maxSessionVolume: return String(localized: "Tonnage de séance")
        case .bestTime: return String(localized: "Meilleur temps")
        case .maxRounds: return String(localized: "Tours complets")
        case .maxDistance: return String(localized: "Distance")
        }
    }
}

/// Record typé pour un exercice et, pour les formats chronometres, pour une
/// configuration precise (un AMRAP de 8 minutes n'est pas comparable a un
/// AMRAP de 12 minutes).
@Model
final class PersonalBest {
    @Attribute(.unique) var id: UUID = UUID()
    var exerciseId: String = ""
    var displayName: String = ""
    var kindRaw: String = PersonalBestKind.maxWeight.rawValue
    /// Cle de configuration du format, par exemple `amrap:600` ou
    /// `circuit:5x4`. Vide pour les records classiques.
    var configurationKey: String = ""
    var value: Double = 0
    /// Repetitions associees a la performance, quand la nature du record en
    /// depend (charge maximale sur 3 repetitions, par exemple).
    var reps: Int?
    var achievedAt: Date = Date()
    /// `CompletedSession.id` d'origine : un record est toujours recalculable
    /// depuis l'historique, qui reste la source de verite.
    var sourceSessionId: UUID?

    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        exerciseId: String,
        displayName: String,
        kindRaw: String = PersonalBestKind.maxWeight.rawValue,
        configurationKey: String = "",
        value: Double,
        reps: Int? = nil,
        achievedAt: Date = Date(),
        sourceSessionId: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.displayName = displayName
        self.kindRaw = kindRaw
        self.configurationKey = configurationKey
        self.value = value
        self.reps = reps
        self.achievedAt = achievedAt
        self.sourceSessionId = sourceSessionId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

extension PersonalBest {
    /// Valeur mise en forme AVEC son unite. Chaque nature a la sienne :
    /// afficher « 42 » sans dire si ce sont des kilos, des secondes ou des
    /// tours ne veut rien dire.
    var formattedValue: String {
        switch kind {
        case .maxWeight, .estimatedOneRepMax, .maxSessionVolume:
            return WeightFormatter.string(kilograms: value)
        case .maxReps:
            return String(localized: "\(Int(value)) reps")
        case .bestTime:
            return CompletedSetPresentation.formattedDuration(Int(value))
        case .maxRounds:
            return String(localized: "\(Int(value)) tours")
        case .maxDistance:
            return String(localized: "\(Int(value)) m")
        }
    }

    /// Precision lisible de la configuration, quand elle existe : un AMRAP
    /// de 8 minutes n'est pas comparable a un AMRAP de 12.
    var configurationLabel: String? {
        guard !configurationKey.isEmpty else { return nil }
        let parts = configurationKey.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { return configurationKey }
        let format = String(parts[0])
        let detail = String(parts[1])
        switch format {
        case "amrap":
            if let seconds = Int(detail) { return String(localized: "AMRAP \(seconds) s") }
        case "emom":
            if let rounds = Int(detail) { return String(localized: "EMOM \(rounds) min") }
        case "forTime":
            if let seconds = Int(detail) { return String(localized: "For Time (cap \(seconds) s)") }
        default:
            break
        }
        return configurationKey
    }

    var kind: PersonalBestKind {
        get { PersonalBestKind(rawValue: kindRaw) ?? .maxWeight }
        set { kindRaw = newValue.rawValue }
    }

    /// Cle d'unicite : un seul record par exercice, nature et configuration.
    var identityKey: String { "\(exerciseId)|\(kindRaw)|\(configurationKey)" }

    static func identityKey(exerciseId: String, kind: PersonalBestKind, configurationKey: String = "") -> String {
        "\(exerciseId)|\(kind.rawValue)|\(configurationKey)"
    }

    /// Une valeur candidate ameliore-t-elle ce record ?
    func isImprovement(by candidate: Double) -> Bool {
        kind.lowerIsBetter ? candidate < value : candidate > value
    }

    var syncMetadata: SyncMetadata {
        SyncMetadata(identifier: id, createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt)
    }
}
