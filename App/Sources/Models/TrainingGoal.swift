import Foundation
import SwiftData
import MuscuEngine

/// Un objectif suivi par l'utilisateur.
///
/// Mettre en pause, modifier ou archiver un objectif ne reecrit jamais
/// l'historique : seul l'objectif change d'etat.
@Model
final class TrainingGoal {
    @Attribute(.unique) var id: UUID = UUID()
    var title: String = ""
    /// `GoalTarget` encode. Le type porte son unite et son sens.
    var targetData: Data?
    var stateRaw: String = GoalState.active.rawValue
    /// Echeance facultative : un objectif sans date reste valable.
    var dueDate: Date?
    /// Valeur de depart, figee a la creation : indispensable pour exprimer
    /// l'avancement d'un objectif en baisse.
    var startValue: Double?
    var notes: String = ""

    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        targetData: Data? = nil,
        stateRaw: String = GoalState.active.rawValue,
        dueDate: Date? = nil,
        startValue: Double? = nil,
        notes: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.targetData = targetData
        self.stateRaw = stateRaw
        self.dueDate = dueDate
        self.startValue = startValue
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

extension TrainingGoal {
    /// Cible de l'objectif. `nil` quand le blob est illisible (donnee ecrite
    /// par une version plus recente) : l'objectif s'affiche alors comme non
    /// exploitable plutot que d'etre interprete de travers.
    var target: GoalTarget? {
        get {
            guard let targetData else { return nil }
            return try? JSONDecoder().decode(GoalTarget.self, from: targetData)
        }
        set { targetData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    var state: GoalState {
        get { GoalState(rawValue: stateRaw) ?? .active }
        set { stateRaw = newValue.rawValue }
    }

    var isTracked: Bool { state == .active && deletedAt == nil }

    var syncMetadata: SyncMetadata {
        SyncMetadata(identifier: id, createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt)
    }
}
