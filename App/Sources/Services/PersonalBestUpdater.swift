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

    /// Serie vue par le calcul des records. Type valeur : la correction
    /// d'une seance passee calcule les records de la version CORRIGEE avant
    /// de l'enregistrer, pour les montrer dans la confirmation.
    struct SetSnapshot {
        var exerciseId: String
        var displayName: String
        var format: SetFormat
        var formatRaw: String
        var reps: Int
        var durationSeconds: Int?
        var distanceMeters: Double?
        var countsAsWorkingSet: Bool
        var input: SetMetricsInput

        init(
            exerciseId: String,
            displayName: String,
            format: SetFormat,
            reps: Int,
            durationSeconds: Int?,
            distanceMeters: Double?,
            countsAsWorkingSet: Bool,
            input: SetMetricsInput
        ) {
            self.exerciseId = exerciseId
            self.displayName = displayName
            self.format = format
            self.formatRaw = format.rawValue
            self.reps = reps
            self.durationSeconds = durationSeconds
            self.distanceMeters = distanceMeters
            self.countsAsWorkingSet = countsAsWorkingSet
            self.input = input
        }

        init(_ set: CompletedSet, bodyweightKilograms: Double?) {
            self.init(
                exerciseId: set.exerciseId,
                displayName: set.displayName,
                format: set.format,
                reps: set.reps,
                durationSeconds: set.durationSeconds,
                distanceMeters: set.distanceMeters,
                countsAsWorkingSet: set.role.countsAsWorkingSet,
                input: set.metricsInput(bodyweightKilograms: bodyweightKilograms)
            )
            // Valeur brute conservee : une valeur inconnue garde sa cle.
            self.formatRaw = set.formatRaw
        }
    }

    /// Candidats issus d'une seance, un par (exercice, nature, configuration).
    static func candidates(for session: CompletedSession, bodyweightKilograms: Double? = nil) -> [Candidate] {
        let knownBodyweight = session.bodyweightKilograms ?? bodyweightKilograms
        return candidates(for: session.sets.map { SetSnapshot($0, bodyweightKilograms: knownBodyweight) })
    }

    /// Candidats issus de series, un par (exercice, nature, configuration).
    static func candidates(for sets: [SetSnapshot]) -> [Candidate] {
        var best: [String: Candidate] = [:]
        let workingSets = sets.filter(\.countsAsWorkingSet)

        func offer(_ candidate: Candidate) {
            let existing = best[candidate.identityKey]
            let improves = existing.map { current in
                candidate.kind.lowerIsBetter ? candidate.value < current.value : candidate.value > current.value
            } ?? true
            if improves { best[candidate.identityKey] = candidate }
        }

        for set in workingSets {
            let input = set.input
            let configurationKey = SetMetrics.recordConfigurationKey(input)

            if set.format.isTimed {
                offerTimedCandidates(for: set, offer: offer)
                continue
            }
            // Serie classique mesuree en temps ou en distance, sans
            // repetitions : ni charge, ni 1RM, ni repetitions n'ont de sens.
            if isMeasured(set) {
                offerMeasuredCandidates(for: set, offer: offer)
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
        for (exerciseId, sets) in Dictionary(grouping: workingSets, by: \.exerciseId) {
            let inputs = sets.map(\.input)
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
    private static func offerTimedCandidates(for set: SetSnapshot, offer: (Candidate) -> Void) {
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

    /// Serie au temps ou a la distance : aucune repetition, mais une duree
    /// ou une distance mesuree.
    private static func isMeasured(_ set: SetSnapshot) -> Bool {
        set.reps == 0 && ((set.durationSeconds ?? 0) > 0 || (set.distanceMeters ?? 0) > 0)
    }

    /// Records d'une serie mesuree :
    /// - temps seul (gainage) : duree maximale, plus haut = mieux ;
    /// - distance : distance maximale ;
    /// - temps ET distance (course) : distance maximale, et meilleur temps
    ///   A DISTANCE EGALE — plus bas = mieux, comme le For Time. Deux
    ///   distances differentes ne sont jamais comparees.
    private static func offerMeasuredCandidates(for set: SetSnapshot, offer: (Candidate) -> Void) {
        let duration = set.durationSeconds ?? 0
        let distance = set.distanceMeters ?? 0
        if distance > 0, distance.isFinite {
            offer(Candidate(
                exerciseId: set.exerciseId,
                displayName: set.displayName,
                kind: .maxDistance,
                configurationKey: "",
                value: distance,
                reps: nil
            ))
            if duration > 0 {
                offer(Candidate(
                    exerciseId: set.exerciseId,
                    displayName: set.displayName,
                    kind: .bestTime,
                    configurationKey: "distance:" + String(Int(distance.rounded())),
                    value: Double(duration),
                    reps: nil
                ))
            }
        } else if duration > 0 {
            offer(Candidate(
                exerciseId: set.exerciseId,
                displayName: set.displayName,
                kind: .maxDuration,
                configurationKey: "",
                value: Double(duration),
                reps: nil
            ))
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
                // Un record supprime logiquement n'est plus une reference :
                // il renait avec la nouvelle valeur plutot que de rester
                // masque avec une valeur a jour.
                guard current.deletedAt != nil || current.isImprovement(by: candidate.value) else { continue }
                current.deletedAt = nil
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
