import Foundation
import SwiftData
import MuscuEngine

/// Met a jour les records TYPES (`PersonalBest`) a partir d'une seance
/// terminee. L'historique reste la source de verite : ces records sont
/// recalculables, jamais la seule trace d'une performance.
///
/// Les regles d'eligibilite (charge portee, plage de repetitions, cle de
/// configuration) viennent de `MuscuEngine.SetMetrics` : rien n'est
/// redefini ici.
@MainActor
enum PersonalBestUpdater {
    struct Candidate: Equatable {
        var exerciseId: String
        var displayName: String
        var kind: PersonalBestKind
        var configurationKey: String
        var value: Double
        var reps: Int?

        var identityKey: String {
            PersonalBest.identityKey(exerciseId: exerciseId, kind: kind, configurationKey: configurationKey)
        }
    }

    /// Candidats issus d'une seance, un par (exercice, nature, configuration).
    static func candidates(for session: CompletedSession, bodyweightKilograms: Double? = nil) -> [Candidate] {
        let knownBodyweight = session.bodyweightKilograms ?? bodyweightKilograms
        var best: [String: Candidate] = [:]

        func offer(_ candidate: Candidate) {
            let existing = best[candidate.identityKey]
            let improves = existing.map { current in
                candidate.kind.lowerIsBetter ? candidate.value < current.value : candidate.value > current.value
            } ?? true
            if improves { best[candidate.identityKey] = candidate }
        }

        for set in session.workingSets {
            let input = set.metricsInput(bodyweightKilograms: knownBodyweight)
            let configurationKey = SetMetrics.recordConfigurationKey(input)

            if set.format.isTimed {
                offerTimedCandidates(for: set, offer: offer)
                continue
            }

            if let oneRepMax = SetMetrics.estimatedOneRepMax(input) {
                offer(Candidate(
                    exerciseId: set.exerciseId,
                    displayName: set.displayName,
                    kind: .estimatedOneRepMax,
                    configurationKey: "",
                    value: oneRepMax,
                    reps: set.reps
                ))
            }
            if SetMetrics.allowsLoadRecord(input), let load = SetMetrics.effectiveLoad(input), load > 0 {
                offer(Candidate(
                    exerciseId: set.exerciseId,
                    displayName: set.displayName,
                    kind: .maxWeight,
                    configurationKey: "",
                    value: load,
                    reps: set.reps
                ))
            }
            if SetMetrics.allowsRepetitionRecord(input) {
                offer(Candidate(
                    exerciseId: set.exerciseId,
                    displayName: set.displayName,
                    kind: .maxReps,
                    configurationKey: "",
                    value: Double(set.reps),
                    reps: set.reps
                ))
            }
            // Un lest ou une assistance ne se compare qu'a configuration
            // egale : le record porte alors sa cle.
            if !configurationKey.isEmpty, set.reps > 0 {
                offer(Candidate(
                    exerciseId: set.exerciseId,
                    displayName: set.displayName,
                    kind: .maxReps,
                    configurationKey: configurationKey,
                    value: Double(set.reps),
                    reps: set.reps
                ))
            }
        }

        // Tonnage de seance par exercice : une seule valeur par exercice.
        for (exerciseId, sets) in Dictionary(grouping: session.workingSets, by: \.exerciseId) {
            let inputs = sets.map { $0.metricsInput(bodyweightKilograms: knownBodyweight) }
            let tonnage = SetMetrics.totalTonnage(inputs)
            guard tonnage.total > 0, tonnage.unknownSets == 0, let displayName = sets.first?.displayName else { continue }
            offer(Candidate(
                exerciseId: exerciseId,
                displayName: displayName,
                kind: .maxSessionVolume,
                configurationKey: "",
                value: tonnage.total,
                reps: nil
            ))
        }

        return best.values.sorted {
            ($0.displayName, $0.kind.rawValue) < ($1.displayName, $1.kind.rawValue)
        }
    }

    /// Les formats chronometres produisent un record propre a leur
    /// configuration : un AMRAP de 8 minutes n'est pas comparable a un
    /// AMRAP de 12 minutes.
    private static func offerTimedCandidates(for set: CompletedSet, offer: (Candidate) -> Void) {
        let duration = set.durationSeconds ?? 0
        let configurationKey = "\(set.formatRaw):\(duration)"

        switch set.format {
        case .amrap, .intervals, .emom:
            guard set.reps > 0 else { return }
            offer(Candidate(
                exerciseId: set.exerciseId,
                displayName: set.displayName,
                kind: .maxRounds,
                configurationKey: configurationKey,
                value: Double(set.reps),
                reps: set.reps
            ))
        case .forTime:
            // For Time se mesure en TEMPS : plus bas est meilleur. La cle
            // inclut le travail annonce, sinon deux volumes differents
            // seraient compares.
            guard duration > 0 else { return }
            offer(Candidate(
                exerciseId: set.exerciseId,
                displayName: set.displayName,
                kind: .bestTime,
                configurationKey: "forTime:\(set.reps)",
                value: Double(duration),
                reps: set.reps
            ))
        case .classic, .pyramid, .dropset, .restPause, .myoReps:
            return
        }
    }

    /// Applique les candidats qui ameliorent reellement un record. Renvoie
    /// les records crees ou mis a jour. Idempotent : rejouer la meme seance
    /// ne cree aucun doublon.
    @discardableResult
    static func apply(
        candidates: [Candidate],
        context: ModelContext,
        sourceSessionId: UUID?,
        achievedAt: Date
    ) -> [PersonalBest] {
        let existing = (try? context.fetch(FetchDescriptor<PersonalBest>())) ?? []
        var byKey = Dictionary(existing.map { ($0.identityKey, $0) }, uniquingKeysWith: { first, _ in first })
        var updated: [PersonalBest] = []

        for candidate in candidates {
            if let current = byKey[candidate.identityKey] {
                guard current.isImprovement(by: candidate.value) else { continue }
                current.value = candidate.value
                current.reps = candidate.reps
                current.achievedAt = achievedAt
                current.sourceSessionId = sourceSessionId
                current.updatedAt = .now
                updated.append(current)
            } else {
                let best = PersonalBest(
                    exerciseId: candidate.exerciseId,
                    displayName: candidate.displayName,
                    kindRaw: candidate.kind.rawValue,
                    configurationKey: candidate.configurationKey,
                    value: candidate.value,
                    reps: candidate.reps,
                    achievedAt: achievedAt,
                    sourceSessionId: sourceSessionId
                )
                context.insert(best)
                byKey[candidate.identityKey] = best
                updated.append(best)
            }
        }
        return updated
    }
}
