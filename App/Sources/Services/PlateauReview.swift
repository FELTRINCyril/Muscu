import Foundation
import SwiftData
import MuscuEngine

/// Detection de stagnation sur les exercices des programmes, et propositions
/// associees.
///
/// Rien n'est applique automatiquement : la roadmap l'interdit explicitement.
/// Une decharge ou une variante est PROPOSEE, avec ses raisons, et n'est
/// ecrite qu'apres accord — puis reste annulable depuis le journal.
@MainActor
enum PlateauReview {
    /// Baisse appliquee par une decharge de stagnation. Valeur documentee et
    /// unique : deux ecrans ne peuvent pas proposer deux decharges
    /// differentes pour la meme situation.
    static let deloadFraction = 0.10

    /// Nombre de seances relues pour juger. Au-dela, ce sont d'autres blocs
    /// d'entrainement : les comparer n'aurait plus de sens.
    static let historyWindow = 12

    struct Item: Identifiable, Equatable {
        let id: UUID
        let prescription: PrescribedExercise
        let displayName: String
        let finding: PlateauFinding
        /// Charge de decharge proposee, si une charge est connue.
        let proposedLoadKilograms: Double?

        var currentLoadKilograms: Double? { prescription.targetWeight }

        static func == (lhs: Item, rhs: Item) -> Bool { lhs.id == rhs.id }
    }

    /// Exercices en stagnation, tous programmes actifs confondus.
    static func findings(in context: ModelContext, now: Date = .now) -> [Item] {
        let profile = ProfileStore.currentProfile(in: context)
        let bodyweight = ProfileStore.latestBodyweightKilograms(in: context)
        let history = completedSessions(in: context)
        let increment = profile?.nearestAvailableIncrement(to: 2.5) ?? 2.5

        var items: [Item] = []
        var seenExerciseIds: Set<String> = []

        for program in programs(in: context) {
            for session in program.orderedSessions {
                for prescription in session.orderedExercises {
                    // Un exercice present dans plusieurs seances ne doit etre
                    // signale qu'une fois : l'historique est le meme.
                    guard seenExerciseIds.insert(prescription.exerciseId).inserted else { continue }

                    let exposures = ProgressionReview.exposures(
                        exerciseId: prescription.exerciseId,
                        history: history,
                        limit: historyWindow
                    )
                    let finding = PlateauDetector.detect(
                        exposures: exposures,
                        bodyweightKilograms: bodyweight
                    )
                    guard finding.isPlateau else { continue }

                    items.append(Item(
                        id: prescription.id,
                        prescription: prescription,
                        displayName: prescription.displayName,
                        finding: finding,
                        proposedLoadKilograms: deloadTarget(
                            from: prescription.targetWeight,
                            increment: increment
                        )
                    ))
                }
            }
        }
        return items
    }

    /// Charge apres decharge, alignee sur le palier reellement disponible.
    /// `nil` quand aucune charge n'est prescrite : on ne decharge pas une
    /// valeur qu'on ne connait pas.
    static func deloadTarget(from current: Double?, increment: Double) -> Double? {
        guard let current, current > 0 else { return nil }
        let target = current * (1 - deloadFraction)
        let rounded = Units.roundedToIncrement(target, increment: increment)
        // Une décharge doit réellement décharger : si l'arrondi ramène à la
        // charge de départ, on descend d'un palier.
        guard rounded < current else { return max(0, current - increment) }
        return rounded
    }

    // MARK: - Décisions

    /// Accepte une decharge : la prescription baisse, et l'ancienne valeur
    /// est conservee pour pouvoir annuler exactement.
    @discardableResult
    static func acceptDeload(_ item: Item, in context: ModelContext, now: Date = .now) -> AdaptationEntry? {
        guard let target = item.proposedLoadKilograms, let current = item.currentLoadKilograms else { return nil }

        let entry = AdaptationEntry(
            createdAt: now,
            sourceRaw: AdaptationSource.plateau.rawValue,
            decisionRaw: AdaptationDecision.accepted.rawValue,
            decidedAt: now,
            prescribedExerciseId: item.prescription.id,
            exerciseId: item.prescription.exerciseId,
            displayName: item.displayName,
            summary: "Décharge : \(WeightFormatter.number(current)) → \(WeightFormatter.number(target)) kg",
            factors: item.finding.factors + ["Décharge de \(Int(deloadFraction * 100)) % proposée après stagnation."],
            previousWeightKilograms: current,
            newWeightKilograms: target
        )
        context.insert(entry)
        item.prescription.targetWeight = target
        item.prescription.touch(now: now)
        _ = PersistenceSupport.save(context, action: "Décharge après stagnation")
        return entry
    }

    /// Accepte une variante : l'exercice du programme change, et la decision
    /// est tracee. L'historique deja enregistre n'est jamais touche.
    @discardableResult
    static func acceptVariant(
        _ item: Item,
        replacement: CatalogExercise,
        in context: ModelContext,
        now: Date = .now
    ) -> AdaptationEntry? {
        let previousName = item.displayName
        guard ProgramEditing.applySubstitution(
            prescriptionId: item.prescription.id,
            exerciseId: replacement.id,
            displayName: replacement.nameFr,
            in: context,
            now: now
        ) else { return nil }

        let entry = AdaptationEntry(
            createdAt: now,
            sourceRaw: AdaptationSource.plateau.rawValue,
            decisionRaw: AdaptationDecision.accepted.rawValue,
            decidedAt: now,
            prescribedExerciseId: item.prescription.id,
            exerciseId: replacement.id,
            displayName: replacement.nameFr,
            summary: "Variante : \(previousName) → \(replacement.nameFr)",
            factors: item.finding.factors
        )
        context.insert(entry)
        _ = PersistenceSupport.save(context, action: "Variante après stagnation")
        return entry
    }

    /// Refus trace : on ne repropose pas la meme chose a l'aveugle.
    @discardableResult
    static func decline(_ item: Item, in context: ModelContext, now: Date = .now) -> AdaptationEntry {
        let entry = AdaptationEntry(
            createdAt: now,
            sourceRaw: AdaptationSource.plateau.rawValue,
            decisionRaw: AdaptationDecision.declined.rawValue,
            decidedAt: now,
            prescribedExerciseId: item.prescription.id,
            exerciseId: item.prescription.exerciseId,
            displayName: item.displayName,
            summary: "Stagnation signalée, aucune adaptation retenue",
            factors: item.finding.factors
        )
        context.insert(entry)
        _ = PersistenceSupport.save(context, action: "Refus d’adaptation")
        return entry
    }

    /// Decisions deja prises recemment pour cet exercice : sert a ne pas
    /// harceler l'utilisateur avec une proposition qu'il vient d'ecarter.
    static func hasRecentDecision(
        exerciseId: String,
        in context: ModelContext,
        within days: Int = 14,
        now: Date = .now
    ) -> Bool {
        let since = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        let entries = (try? context.fetch(FetchDescriptor<AdaptationEntry>())) ?? []
        return entries.contains {
            $0.deletedAt == nil
                && $0.source == .plateau
                && $0.exerciseId == exerciseId
                && $0.decision != .proposed
                && ($0.decidedAt ?? $0.createdAt) >= since
        }
    }

    // MARK: - Lecture

    private static func programs(in context: ModelContext) -> [Program] {
        let descriptor = FetchDescriptor<Program>(sortBy: [SortDescriptor(\.name)])
        return ((try? context.fetch(descriptor)) ?? []).filter { $0.deletedAt == nil }
    }

    private static func completedSessions(in context: ModelContext) -> [CompletedSession] {
        var descriptor = FetchDescriptor<CompletedSession>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 200
        return ((try? context.fetch(descriptor)) ?? []).filter { $0.deletedAt == nil }
    }
}
