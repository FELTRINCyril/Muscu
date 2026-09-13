import Foundation
import SwiftData
import MuscuEngine

/// Type de regroupement d'exercices dans une seance.
enum ExerciseGroupKind: String, Codable, CaseIterable, Sendable {
    /// Exercice seul : le cas par defaut, conserve pour que toute
    /// prescription puisse etre decrite uniformement.
    case single
    case superset
    case triset
    case giantSet
    case circuit

    var displayName: String {
        switch self {
        case .single: return String(localized: "Exercice seul")
        case .superset: return String(localized: "Superset")
        case .triset: return String(localized: "Triset")
        case .giantSet: return String(localized: "Giant set")
        case .circuit: return String(localized: "Circuit")
        }
    }

    /// Nombre d'exercices attendu. `nil` = pas de contrainte haute.
    var expectedExerciseCount: ClosedRange<Int>? {
        switch self {
        case .single: return 1...1
        case .superset: return 2...2
        case .triset: return 3...3
        case .giantSet: return 4...12
        case .circuit: return 2...20
        }
    }

    /// Un repos de zero seconde n'est semantiquement valide qu'entre les
    /// exercices d'un groupe enchaine, jamais entre deux tours de circuit
    /// ni apres un exercice seul.
    var allowsZeroRestBetweenExercises: Bool {
        switch self {
        case .single: return false
        case .superset, .triset, .giantSet, .circuit: return true
        }
    }

    func accepts(exerciseCount: Int) -> Bool {
        guard let range = expectedExerciseCount else { return exerciseCount >= 1 }
        return range.contains(exerciseCount)
    }

    /// Conversion autorisee vers un autre type, selon le nombre d'exercices.
    func canConvert(to other: ExerciseGroupKind, exerciseCount: Int) -> Bool {
        other.accepts(exerciseCount: exerciseCount)
    }
}

/// Groupe ordonne d'exercices dans une seance de programme : superset,
/// triset, giant set ou circuit. Les exercices restent des
/// `PrescribedExercise` : un groupe ne duplique aucune prescription.
@Model
final class ExerciseGroup {
    @Attribute(.unique) var id: UUID = UUID()
    var kindRaw: String = ExerciseGroupKind.superset.rawValue
    var orderIndex: Int = 0
    var rounds: Int = 3
    /// Repos entre deux exercices du groupe, en secondes. Zero autorise.
    var restBetweenExercisesSeconds: Int = 0
    /// Repos apres un tour complet, en secondes.
    var restBetweenRoundsSeconds: Int = 90
    /// Transition facultative entre stations d'un circuit, en secondes.
    var transitionSeconds: Int = 0
    /// Circuit : validation manuelle de chaque station plutot qu'automatique.
    var requiresManualStationValidation: Bool = true
    var notes: String = ""

    var session: ProgramSession?

    @Relationship(deleteRule: .nullify, inverse: \PrescribedExercise.group)
    var exercises: [PrescribedExercise] = []

    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        kindRaw: String = ExerciseGroupKind.superset.rawValue,
        orderIndex: Int,
        rounds: Int = 3,
        restBetweenExercisesSeconds: Int = 0,
        restBetweenRoundsSeconds: Int = 90,
        transitionSeconds: Int = 0,
        requiresManualStationValidation: Bool = true,
        notes: String = "",
        exercises: [PrescribedExercise] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.kindRaw = kindRaw
        self.orderIndex = orderIndex
        self.rounds = rounds
        self.restBetweenExercisesSeconds = restBetweenExercisesSeconds
        self.restBetweenRoundsSeconds = restBetweenRoundsSeconds
        self.transitionSeconds = transitionSeconds
        self.requiresManualStationValidation = requiresManualStationValidation
        self.notes = notes
        self.exercises = exercises
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

extension ExerciseGroup {
    var kind: ExerciseGroupKind {
        get { ExerciseGroupKind(rawValue: kindRaw) ?? .superset }
        set { kindRaw = newValue.rawValue }
    }

    var orderedExercises: [PrescribedExercise] {
        exercises.sorted { $0.groupOrderIndex < $1.groupOrderIndex }
    }

    var syncMetadata: SyncMetadata {
        SyncMetadata(identifier: id, createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt)
    }

    /// Resume lisible affiche avant enregistrement, par exemple
    /// « Superset · 3 tours · 2 exercices · repos 90 s ».
    var summaryText: String {
        let parts = [
            kind.displayName,
            String(localized: "\(rounds) tours"),
            String(localized: "\(orderedExercises.count) exercices"),
        ]
        return parts.joined(separator: " · ")
    }
}
