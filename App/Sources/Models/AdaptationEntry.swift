import Foundation
import SwiftData
import MuscuEngine

/// Origine d'une adaptation proposee.
enum AdaptationSource: String, Codable, CaseIterable, Sendable {
    case progression
    case readiness
    case plateau
    case deload
    case manual
}

/// Suite donnee a une proposition par l'utilisateur.
enum AdaptationDecision: String, Codable, CaseIterable, Sendable {
    case proposed
    case accepted
    case declined
    case reverted
}

/// Journal des adaptations : ce qui a ete propose, pourquoi, et ce que
/// l'utilisateur a decide.
///
/// Une proposition n'est jamais appliquee sans trace : ce journal est ce qui
/// rend une progression explicable et annulable.
@Model
final class AdaptationEntry {
    @Attribute(.unique) var id: UUID = UUID()
    var createdAt: Date = Date()
    var sourceRaw: String = AdaptationSource.progression.rawValue
    var decisionRaw: String = AdaptationDecision.proposed.rawValue
    var decidedAt: Date?

    /// Prescription concernee, quand l'adaptation porte sur un exercice.
    var prescribedExerciseId: UUID?
    var exerciseId: String = ""
    var displayName: String = ""

    /// Resume lisible de la proposition, par exemple « 60 kg → 62,5 kg ».
    var summary: String = ""
    /// Facteurs ayant conduit a la proposition, un par ligne.
    var factors: [String] = []

    /// Valeurs avant/apres, pour pouvoir annuler exactement.
    var previousWeightKilograms: Double?
    var newWeightKilograms: Double?
    var previousRepsUpper: Int?
    var newRepsUpper: Int?
    var previousSets: Int?
    var newSets: Int?
    var previousPercentOneRepMax: Double?
    var newPercentOneRepMax: Double?

    var updatedAt: Date = Date()
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        sourceRaw: String = AdaptationSource.progression.rawValue,
        decisionRaw: String = AdaptationDecision.proposed.rawValue,
        decidedAt: Date? = nil,
        prescribedExerciseId: UUID? = nil,
        exerciseId: String = "",
        displayName: String = "",
        summary: String = "",
        factors: [String] = [],
        previousWeightKilograms: Double? = nil,
        newWeightKilograms: Double? = nil,
        previousRepsUpper: Int? = nil,
        newRepsUpper: Int? = nil,
        previousSets: Int? = nil,
        newSets: Int? = nil,
        previousPercentOneRepMax: Double? = nil,
        newPercentOneRepMax: Double? = nil,
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.sourceRaw = sourceRaw
        self.decisionRaw = decisionRaw
        self.decidedAt = decidedAt
        self.prescribedExerciseId = prescribedExerciseId
        self.exerciseId = exerciseId
        self.displayName = displayName
        self.summary = summary
        self.factors = factors
        self.previousWeightKilograms = previousWeightKilograms
        self.newWeightKilograms = newWeightKilograms
        self.previousRepsUpper = previousRepsUpper
        self.newRepsUpper = newRepsUpper
        self.previousSets = previousSets
        self.newSets = newSets
        self.previousPercentOneRepMax = previousPercentOneRepMax
        self.newPercentOneRepMax = newPercentOneRepMax
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

extension AdaptationEntry {
    var source: AdaptationSource {
        get { AdaptationSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    var decision: AdaptationDecision {
        get { AdaptationDecision(rawValue: decisionRaw) ?? .proposed }
        set { decisionRaw = newValue.rawValue }
    }

    /// Une adaptation acceptee peut etre annulee tant qu'elle porte des
    /// valeurs precedentes exploitables.
    var canRevert: Bool {
        decision == .accepted
            && (previousWeightKilograms != nil
                || previousRepsUpper != nil
                || previousSets != nil
                || previousPercentOneRepMax != nil)
    }

    var syncMetadata: SyncMetadata {
        SyncMetadata(identifier: id, createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt)
    }
}
