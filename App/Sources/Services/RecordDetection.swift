import Foundation
import MuscuEngine

// Detection de records battus a la fin d'une seance, comparee aux
// ExerciseRecord existants. Logique pure (pas de SwiftData ici) : le
// contexte SwiftData reste la responsabilite de l'appelant (WorkoutSummaryView).
//
// Toutes les regles de calcul (charge effective, eligibilite au 1RM, records
// de repetitions) viennent de `MuscuEngine.SetMetrics` : aucune formule n'est
// redefinie ici.
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
    // reps), en ne considerant que les series de travail.
    //
    // 1RM estime : uniquement sur les series dont la charge est reellement
    // portee (externe ou lestee) et comprises entre 1 et 12 repetitions, cf.
    // SetMetrics.isEligibleForOneRepMax. Une serie ASSISTEE ne peut donc
    // jamais produire de record de charge.
    //
    // Max de repetitions : uniquement sur les series ou la charge n'est pas
    // le facteur mesure (poids du corps, assistance).
    static func check(
        session: CompletedSession,
        records: [ExerciseRecord],
        bodyweightKilograms: Double? = nil
    ) -> [RecordSuggestion] {
        let workingSets = session.sets.filter { $0.role.countsAsWorkingSet }
        guard !workingSets.isEmpty else { return [] }

        // uniquingKeysWith plutot que uniqueKeysWithValues : des doublons
        // d'exerciseId sont creables via import (fusion additive), ne pas
        // trapper dessus - on garde arbitrairement le premier.
        let recordsByExerciseId = Dictionary(records.map { ($0.exerciseId, $0) }, uniquingKeysWith: { first, _ in first })
        let grouped = Dictionary(grouping: workingSets, by: \.exerciseId)
        let knownBodyweight = session.bodyweightKilograms ?? bodyweightKilograms

        var suggestions: [RecordSuggestion] = []

        for (exerciseId, sets) in grouped {
            guard let displayName = sets.first?.displayName else { continue }
            let existingRecord = recordsByExerciseId[exerciseId]
            let inputs = sets.map { $0.metricsInput(bodyweightKilograms: knownBodyweight) }

            if let bestOneRepMax = inputs.compactMap(SetMetrics.estimatedOneRepMax).max() {
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

            let repsCandidates = inputs.filter(SetMetrics.allowsRepetitionRecord).map(\.reps)
            if let bestReps = repsCandidates.max(), bestReps > 0 {
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
