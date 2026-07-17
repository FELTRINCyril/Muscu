import Foundation
import MuscuEngine

// Detection de records battus a la fin d'une seance, comparee aux
// ExerciseRecord existants. Logique pure (pas de SwiftData ici) : le
// contexte SwiftData reste la responsabilite de l'appelant (WorkoutSummaryView).
enum RecordDetection {
    struct RecordSuggestion: Identifiable {
        enum Kind {
            case oneRepMax(new: Double, old: Double?)
            case maxReps(new: Int, old: Int?)
        }

        var id: String {
            switch kind {
            case .oneRepMax: "\(exerciseId)-1rm"
            case .maxReps: "\(exerciseId)-reps"
            }
        }

        let exerciseId: String
        let displayName: String
        let kind: Kind
    }

    // Une suggestion au plus par exercice et par nature (1RM estime / max
    // reps), en ne considerant que les series de travail (isWarmup exclu).
    // Series chargees (weight > 0) -> 1RM estime via Epley, on prend le
    // meilleur de la seance ; series au poids du corps (weight == 0) -> max
    // reps de la seance.
    static func check(session: CompletedSession, records: [ExerciseRecord]) -> [RecordSuggestion] {
        let workingSets = session.sets.filter { !$0.isWarmup }
        guard !workingSets.isEmpty else { return [] }

        // uniquingKeysWith plutot que uniqueKeysWithValues : des doublons
        // d'exerciseId sont creables via import (fusion additive), ne pas
        // trapper dessus - on garde arbitrairement le premier.
        let recordsByExerciseId = Dictionary(records.map { ($0.exerciseId, $0) }, uniquingKeysWith: { first, _ in first })
        let grouped = Dictionary(grouping: workingSets, by: \.exerciseId)

        var suggestions: [RecordSuggestion] = []

        for (exerciseId, sets) in grouped {
            guard let displayName = sets.first?.displayName else { continue }
            let existingRecord = recordsByExerciseId[exerciseId]

            let weightedSets = sets.filter { $0.weight > 0 }
            if let bestOneRepMax = weightedSets.map({ OneRepMax.epley(weight: $0.weight, reps: $0.reps) }).max() {
                let oldOneRepMax = existingRecord?.oneRepMax
                if oldOneRepMax == nil || bestOneRepMax > oldOneRepMax! {
                    suggestions.append(
                        RecordSuggestion(
                            exerciseId: exerciseId,
                            displayName: displayName,
                            kind: .oneRepMax(new: bestOneRepMax, old: oldOneRepMax)
                        )
                    )
                }
            }

            let bodyweightSets = sets.filter { $0.weight == 0 }
            if let bestReps = bodyweightSets.map(\.reps).max() {
                let oldMaxReps = existingRecord?.maxReps
                if oldMaxReps == nil || bestReps > oldMaxReps! {
                    suggestions.append(
                        RecordSuggestion(
                            exerciseId: exerciseId,
                            displayName: displayName,
                            kind: .maxReps(new: bestReps, old: oldMaxReps)
                        )
                    )
                }
            }
        }

        return suggestions.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }
}
