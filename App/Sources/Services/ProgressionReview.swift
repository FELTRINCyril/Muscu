import Foundation
import SwiftData
import MuscuEngine

/// Fait le pont entre le moteur de progression (pur) et le store.
///
/// Trois garanties, qui viennent directement de la roadmap :
/// 1. rien n'est applique sans decision explicite de l'utilisateur ;
/// 2. chaque proposition porte ses facteurs, issus de performances reelles ;
/// 3. toute adaptation acceptee reste annulable, via le journal.
@MainActor
enum ProgressionReview {
    /// Une proposition prete a etre presentee.
    struct Item: Identifiable {
        let id: UUID
        let prescription: PrescribedExercise
        let proposal: ProgressionProposal

        var displayName: String { prescription.displayName }
        var factors: [String] { proposal.factors.map(\.text) }
    }

    /// Nombre d'expositions passees examinees. Au-dela, l'historique ancien
    /// ne dit plus rien d'utile sur la progression en cours.
    static let historyWindow = 6

    // MARK: - Lecture

    /// Propositions pour tous les exercices d'une seance de programme.
    /// Seules celles qui changent reellement quelque chose sont retournees.
    static func proposals(
        for session: ProgramSession,
        context: ModelContext,
        now: Date = .now
    ) -> [Item] {
        let profile = ProfileStore.currentProfile(in: context)
        let bodyweight = ProfileStore.latestBodyweightKilograms(in: context)
        let history = completedSessions(context: context)

        return session.orderedExercises.compactMap { prescription in
            let proposal = propose(
                for: prescription,
                history: history,
                profile: profile,
                bodyweightKilograms: bodyweight
            )
            guard proposal.changesAnything else { return nil }
            return Item(id: prescription.id, prescription: prescription, proposal: proposal)
        }
    }

    /// Proposition pour une prescription donnee.
    static func propose(
        for prescription: PrescribedExercise,
        history: [CompletedSession],
        profile: AthleteProfile?,
        bodyweightKilograms: Double?
    ) -> ProgressionProposal {
        let rule = prescription.progressionRule ?? profile?.defaultProgressionRule ?? .default
        let exposures = Self.exposures(
            exerciseId: prescription.exerciseId,
            history: history,
            limit: historyWindow
        )
        let context = ProgressionContext(
            rule: rule,
            prescribedSets: prescription.sets,
            repsLower: prescription.repsLower,
            repsUpper: prescription.repsUpper,
            currentWeightKilograms: prescription.targetWeight,
            availableIncrementKilograms: profile?.nearestAvailableIncrement(to: 2.5) ?? 2.5,
            loadKind: prescription.prescribedLoadKind ?? .unknown,
            exposures: exposures,
            targetEffort: prescription.targetEffort
        )
        return ProgressionEngine.propose(context)
    }

    /// Historique converti vers le type pur du moteur, du plus recent au plus
    /// ancien. Les series d'echauffement sont exclues par `SetRole`.
    static func exposures(
        exerciseId: String,
        history: [CompletedSession],
        limit: Int
    ) -> [ExerciseExposure] {
        var result: [ExerciseExposure] = []
        for session in history {
            let sets = session.sets.filter { $0.exerciseId == exerciseId }
            guard !sets.isEmpty else { continue }
            result.append(
                ExerciseExposure(
                    date: session.date,
                    sets: sets
                        .sorted { ($0.roundIndex, $0.setIndex, $0.subSetIndex) < ($1.roundIndex, $1.setIndex, $1.subSetIndex) }
                        .map { set in
                            ExposureSet(
                                weightKilograms: set.weight,
                                reps: set.reps,
                                effort: set.effort,
                                loadKind: set.loadType.loadKind,
                                isWorkingSet: set.role.countsAsWorkingSet,
                                durationSeconds: set.durationSeconds
                            )
                        }
                )
            )
            if result.count >= limit { break }
        }
        return result
    }

    // MARK: - Écriture

    /// Enregistre la proposition au journal, sans rien appliquer.
    @discardableResult
    static func record(_ item: Item, context: ModelContext, now: Date = .now) -> AdaptationEntry {
        let entry = AdaptationEntry(
            createdAt: now,
            sourceRaw: AdaptationSource.progression.rawValue,
            decisionRaw: AdaptationDecision.proposed.rawValue,
            prescribedExerciseId: item.prescription.id,
            exerciseId: item.prescription.exerciseId,
            displayName: item.displayName,
            summary: summary(for: item.proposal.outcome),
            factors: item.factors
        )
        context.insert(entry)
        return entry
    }

    /// Applique la proposition a la prescription, en conservant les valeurs
    /// precedentes pour pouvoir annuler exactement.
    @discardableResult
    static func accept(_ item: Item, context: ModelContext, now: Date = .now) -> AdaptationEntry {
        let prescription = item.prescription
        let entry = record(item, context: context, now: now)
        entry.decision = .accepted
        entry.decidedAt = now

        switch item.proposal.outcome {
        case .increaseLoad(let from, let to), .reduceLoad(let from, let to):
            entry.previousWeightKilograms = prescription.targetWeight ?? from
            entry.newWeightKilograms = to
            prescription.targetWeight = to

        case .increaseReps(let from, let to):
            entry.previousRepsUpper = from
            entry.newRepsUpper = to
            prescription.repsUpper = to

        case .increaseSets(let from, let to):
            entry.previousSets = from
            entry.newSets = to
            prescription.sets = to

        case .increasePercent(let from, let to):
            entry.previousPercentOneRepMax = prescription.percentOneRepMax ?? from
            entry.newPercentOneRepMax = to
            prescription.percentOneRepMax = to

        case .adjustTime(let workDelta, let restDelta):
            // Les bornes sont celles de l'editeur : une adaptation ne doit
            // jamais produire une prescription non editable.
            prescription.intervalWork = max(5, min(600, prescription.intervalWork + workDelta))
            prescription.intervalRest = max(0, min(600, prescription.intervalRest + restDelta))

        case .hold, .notEnoughData:
            entry.decision = .declined
        }

        prescription.touch(now: now)
        return entry
    }

    /// Enregistre un refus : la prescription n'est pas touchee, mais la
    /// decision est tracee pour ne pas reproposer la meme chose a l'aveugle.
    @discardableResult
    static func decline(_ item: Item, context: ModelContext, now: Date = .now) -> AdaptationEntry {
        let entry = record(item, context: context, now: now)
        entry.decision = .declined
        entry.decidedAt = now
        return entry
    }

    /// Annule une adaptation acceptee en restaurant exactement les valeurs
    /// d'origine.
    @discardableResult
    static func revert(_ entry: AdaptationEntry, context: ModelContext, now: Date = .now) -> Bool {
        guard entry.canRevert, let prescriptionId = entry.prescribedExerciseId else { return false }
        let descriptor = FetchDescriptor<PrescribedExercise>(
            predicate: #Predicate { $0.id == prescriptionId }
        )
        guard let prescription = try? context.fetch(descriptor).first else { return false }

        if let previous = entry.previousWeightKilograms { prescription.targetWeight = previous }
        if let previous = entry.previousRepsUpper { prescription.repsUpper = previous }
        if let previous = entry.previousSets { prescription.sets = previous }
        if let previous = entry.previousPercentOneRepMax { prescription.percentOneRepMax = previous }

        entry.decision = .reverted
        entry.decidedAt = now
        entry.updatedAt = now
        prescription.touch(now: now)
        return true
    }

    // MARK: - Présentation

    /// Resume court d'une proposition, affichable tel quel.
    static func summary(for outcome: ProgressionOutcome) -> String {
        switch outcome {
        case .increaseLoad(let from, let to):
            return "Charge \(WeightFormatter.string(kilograms: from)) → \(WeightFormatter.string(kilograms: to))"
        case .reduceLoad(let from, let to):
            return "Charge \(WeightFormatter.string(kilograms: from)) → \(WeightFormatter.string(kilograms: to))"
        case .increaseReps(let from, let to):
            return "Répétitions \(from) → \(to)"
        case .increaseSets(let from, let to):
            return "Séries \(from) → \(to)"
        case .increasePercent(let from, let to):
            return "Intensité \(Int(from)) % → \(Int(to)) % du 1RM"
        case .adjustTime(let work, let rest):
            var parts: [String] = []
            if work != 0 { parts.append("effort \(work > 0 ? "+" : "")\(work) s") }
            if rest != 0 { parts.append("repos \(rest > 0 ? "+" : "")\(rest) s") }
            return parts.isEmpty ? "Aucun ajustement" : parts.joined(separator: ", ")
        case .hold:
            return "Prescription inchangée"
        case .notEnoughData:
            return "Pas assez de données"
        }
    }

    private static func completedSessions(context: ModelContext) -> [CompletedSession] {
        var descriptor = FetchDescriptor<CompletedSession>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        // On borne la lecture : un historique de plusieurs annees n'a pas a
        // etre charge pour decider de la prochaine seance.
        descriptor.fetchLimit = 200
        return (try? context.fetch(descriptor)) ?? []
    }
}
