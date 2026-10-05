import Foundation
import SwiftData
import MuscuEngine

/// Correction d'une seance passee depuis l'historique.
///
/// Une seance terminee reste immuable au quotidien ; la corriger est un acte
/// explicite (mode edition, puis confirmation). Ses consequences sont toutes
/// traitees ici, en une seule sauvegarde :
/// - `editedAt` et `revision` sont renseignes : la synchronisation fait
///   partir la seance (file d'attente alimentee par la sauvegarde) et la
///   correction la plus recente gagne entre appareils (decision 0014) ;
/// - les records sont recalcules sans regression (`RecordRevision`) : un
///   record ne redescend que s'il venait de cette seance ;
/// - l'entrainement Sante deja ecrit est remplace a la synchronisation Sante
///   suivante, declenchee par l'appelant.
@MainActor
enum PastSessionEditor {
    // MARK: - Brouillon

    struct SetDraft: Identifiable, Equatable {
        let id: UUID
        /// Serie existante corrigee ; `nil` pour une serie ajoutee.
        var existingSetId: UUID?
        var role: SetRole
        var weight: Double
        var reps: Int
        var durationSeconds: Int?
        var distanceMeters: Double?
        /// Repere d'affichage, conserve de la serie d'origine.
        var roundIndex: Int
        var setIndex: Int
        var subSetIndex: Int
    }

    struct ExerciseDraft: Identifiable, Equatable {
        let id: UUID
        /// Index d'ordre d'origine ; `nil` pour un exercice ajoute.
        var orderIndex: Int?
        var exerciseId: String
        var displayName: String
        var loadTypeRaw: String
        var sideConventionRaw: String
        var formatRaw: String
        var groupId: UUID?
        var measure: SetMeasure
        var sets: [SetDraft]

        var isGrouped: Bool { groupId != nil }
    }

    struct Draft: Equatable {
        var start: Date
        var end: Date
        var effortRating: Int?
        var exercises: [ExerciseDraft]
    }

    /// Debut et fin d'une seance. Une seance terminee dans Muscu porte sa
    /// date de FIN (posee a « Terminer ») ; une seance importee ou venue de
    /// la montre porte sa date de DEBUT.
    static func interval(of session: CompletedSession) -> (start: Date, end: Date) {
        let duration = TimeInterval(max(0, session.durationSeconds))
        return session.importSource.isEmpty
            ? (session.date.addingTimeInterval(-duration), session.date)
            : (session.date, session.date.addingTimeInterval(duration))
    }

    static func draft(for session: CompletedSession) -> Draft {
        let (start, end) = interval(of: session)
        let byOrder = Dictionary(grouping: session.sets, by: \.orderIndex)
        let exercises = byOrder.keys.sorted().compactMap { orderIndex -> ExerciseDraft? in
            guard let sets = byOrder[orderIndex], let first = sets.first else { return nil }
            let ordered = sets.sorted {
                ($0.roundIndex, $0.setIndex, $0.subSetIndex, $0.sequenceIndex)
                    < ($1.roundIndex, $1.setIndex, $1.subSetIndex, $1.sequenceIndex)
            }
            return ExerciseDraft(
                id: UUID(),
                orderIndex: orderIndex,
                exerciseId: first.exerciseId,
                displayName: first.displayName,
                loadTypeRaw: first.loadTypeRaw,
                sideConventionRaw: first.sideConventionRaw,
                formatRaw: first.formatRaw,
                groupId: first.groupId,
                measure: measure(of: ordered),
                sets: ordered.map { set in
                    SetDraft(
                        id: set.id,
                        existingSetId: set.id,
                        role: set.role,
                        weight: set.weight,
                        reps: set.reps,
                        durationSeconds: set.durationSeconds,
                        distanceMeters: set.distanceMeters,
                        roundIndex: set.roundIndex,
                        setIndex: set.setIndex,
                        subSetIndex: set.subSetIndex
                    )
                }
            )
        }
        return Draft(start: start, end: end, effortRating: session.effortRating, exercises: exercises)
    }

    /// Mesure d'un exercice deduite de ses series : sans repetitions mais
    /// avec une duree ou une distance, il etait mesure.
    static func measure(of sets: [CompletedSet]) -> SetMeasure {
        let working = sets.filter { $0.role.countsAsWorkingSet }
        guard !working.isEmpty, working.allSatisfy({ $0.reps == 0 }) else { return .weightReps }
        let hasDuration = working.contains { ($0.durationSeconds ?? 0) > 0 }
        let hasDistance = working.contains { ($0.distanceMeters ?? 0) > 0 }
        return SetMeasure(
            targetDurationSeconds: hasDuration ? 1 : 0,
            targetDistanceMeters: hasDistance ? 1 : 0
        )
    }

    /// Nouvelle serie pour un exercice du brouillon : reprend les valeurs de
    /// sa derniere serie, a corriger ensuite.
    static func newSet(for exercise: ExerciseDraft) -> SetDraft {
        let last = exercise.sets.last { $0.role.countsAsWorkingSet } ?? exercise.sets.last
        let nextIndex = (exercise.sets.filter { $0.subSetIndex == 0 }.map(\.setIndex).max() ?? -1) + 1
        let nextRound = (exercise.sets.map(\.roundIndex).max() ?? -1) + 1
        return SetDraft(
            id: UUID(),
            existingSetId: nil,
            role: .working,
            weight: last?.weight ?? 0,
            reps: exercise.measure.measuresReps ? max(1, last?.reps ?? 8) : 0,
            durationSeconds: exercise.measure.measuresDuration ? (last?.durationSeconds ?? SetMeasure.defaultTargetDurationSeconds) : nil,
            distanceMeters: exercise.measure.measuresDistance ? (last?.distanceMeters ?? SetMeasure.defaultTargetDistanceMeters) : nil,
            roundIndex: exercise.isGrouped ? nextRound : 0,
            setIndex: exercise.isGrouped ? 0 : nextIndex,
            subSetIndex: 0
        )
    }

    /// Exercice ajoute a une seance passee : une serie a remplir.
    static func newExercise(exerciseId: String, displayName: String, loadKind: LoadKind) -> ExerciseDraft {
        var exercise = ExerciseDraft(
            id: UUID(),
            orderIndex: nil,
            exerciseId: exerciseId,
            displayName: displayName,
            loadTypeRaw: ExerciseLoadType(loadKind: loadKind).rawValue,
            sideConventionRaw: SideConvention.bilateral.rawValue,
            formatRaw: SetFormat.classic.rawValue,
            groupId: nil,
            measure: .weightReps,
            sets: []
        )
        exercise.sets = [newSet(for: exercise)]
        return exercise
    }

    // MARK: - Validation

    enum Issue: Equatable {
        case timing(PastSessionEdit.TimingIssue)
        case invalidSet(exerciseName: String)
        case empty

        var message: String {
            switch self {
            case .timing(.endBeforeStart): return String(localized: "La fin doit suivre le début.")
            case .timing(.tooLong): return String(localized: "Une séance ne peut pas dépasser 24 heures.")
            case .timing(.inFuture): return String(localized: "La fin ne peut pas être dans le futur.")
            case .invalidSet(let name): return String(localized: "Une série de « \(name) » n’a pas de valeur valide.")
            case .empty: return String(localized: "Une séance doit garder au moins une série.")
            }
        }
    }

    static func issue(in draft: Draft, now: Date = .now) -> Issue? {
        if let timing = PastSessionEdit.timingIssue(start: draft.start, end: draft.end, now: now) {
            return .timing(timing)
        }
        guard draft.exercises.contains(where: { !$0.sets.isEmpty }) else { return .empty }
        for exercise in draft.exercises {
            for set in exercise.sets where !PastSessionEdit.isValidSet(
                weightKilograms: set.weight,
                reps: set.reps,
                durationSeconds: set.durationSeconds,
                distanceMeters: set.distanceMeters
            ) {
                return .invalidSet(exerciseName: exercise.displayName)
            }
        }
        return nil
    }

    // MARK: - Consequences sur les records

    /// Un changement de record annonce dans la confirmation, puis applique.
    struct RecordChange: Identifiable {
        enum Target {
            case personalBest(existing: PersonalBest?, candidate: PersonalBestUpdater.Candidate)
            case oneRepMax(existing: ExerciseRecord?, exerciseId: String, displayName: String)
            case maxReps(existing: ExerciseRecord?, exerciseId: String, displayName: String)
        }

        let id = UUID()
        let target: Target
        let decision: RecordRevisionDecision
        /// Repetitions de la valeur retenue (records types).
        let reps: Int?
        let exerciseName: String
        let kindLabel: String
        let oldValue: String?
        let newValue: String?
    }

    /// Records touches par la correction (ou la suppression, `draft == nil`)
    /// de la seance. Rien n'est ecrit ici.
    static func recordChanges(
        for session: CompletedSession,
        draft: Draft?,
        in context: ModelContext
    ) -> [RecordChange] {
        let fallbackBodyweight = ProfileStore.latestBodyweightKilograms(in: context)
        let bodyweight = session.bodyweightKilograms ?? fallbackBodyweight
        let before = session.sets.map { PersonalBestUpdater.SetSnapshot($0, bodyweightKilograms: bodyweight) }
        let after = draft.map { snapshots(of: $0, session: session, bodyweight: bodyweight) } ?? []
        let sessionDate = draft.map { session.importSource.isEmpty ? $0.end : $0.start } ?? session.date

        let others = ((try? context.fetch(FetchDescriptor<CompletedSession>())) ?? [])
            .filter { $0.id != session.id && $0.deletedAt == nil }
        // L'historique n'est relu que si un record doit redescendre.
        var otherHistory: OtherHistory?
        func history() -> OtherHistory {
            if let otherHistory { return otherHistory }
            let built = OtherHistory(sessions: others, fallbackBodyweight: fallbackBodyweight)
            otherHistory = built
            return built
        }

        var changes: [RecordChange] = []
        changes += personalBestChanges(
            session: session,
            sessionDate: sessionDate,
            before: before,
            after: after,
            context: context,
            history: history
        )
        changes += exerciseRecordChanges(
            sessionId: session.id,
            before: before,
            after: after,
            context: context,
            history: history
        )
        return changes
    }

    private static func snapshots(
        of draft: Draft,
        session: CompletedSession,
        bodyweight: Double?
    ) -> [PersonalBestUpdater.SetSnapshot] {
        draft.exercises.flatMap { exercise in
            exercise.sets.map { set in
                let loadType = ExerciseLoadType(rawValue: exercise.loadTypeRaw) ?? .unknown
                return PersonalBestUpdater.SetSnapshot(
                    exerciseId: exercise.exerciseId,
                    displayName: exercise.displayName,
                    format: SetFormat(rawValue: exercise.formatRaw) ?? .classic,
                    reps: set.reps,
                    durationSeconds: set.durationSeconds,
                    distanceMeters: set.distanceMeters,
                    countsAsWorkingSet: set.role.countsAsWorkingSet,
                    input: SetMetricsInput(
                        weightKilograms: set.weight,
                        reps: set.reps,
                        loadKind: loadType.loadKind,
                        side: SideConvention(rawValue: exercise.sideConventionRaw) ?? .bilateral,
                        isWarmup: !set.role.countsAsWorkingSet,
                        bodyweightKilograms: bodyweight,
                        durationSeconds: set.durationSeconds,
                        distanceMeters: set.distanceMeters,
                        maximumRepsForOneRepMax: WorkoutSettings.maximumRepsForOneRepMax
                    )
                )
            }
        }
    }

    /// Meilleures valeurs des AUTRES seances, par cle de record.
    @MainActor
    private final class OtherHistory {
        var bests: [String: (candidate: PersonalBestUpdater.Candidate, value: RecordValue)] = [:]
        var oneRepMax: [String: Double] = [:]
        var maxReps: [String: Int] = [:]

        init(sessions: [CompletedSession], fallbackBodyweight: Double?) {
            for session in sessions {
                for candidate in PersonalBestUpdater.candidates(for: session, bodyweightKilograms: fallbackBodyweight) {
                    let value = RecordValue(value: candidate.value, sessionId: session.id, achievedAt: session.date)
                    if let current = bests[candidate.identityKey],
                       RecordRevision.best([current.value, value], lowerIsBetter: candidate.kind.lowerIsBetter) == current.value {
                        continue
                    }
                    bests[candidate.identityKey] = (candidate, value)
                }
                let bodyweight = session.bodyweightKilograms ?? fallbackBodyweight
                let snapshots = session.sets.map { PersonalBestUpdater.SetSnapshot($0, bodyweightKilograms: bodyweight) }
                for (exerciseId, values) in PastSessionEditor.exerciseRecordValues(snapshots) {
                    if let value = values.oneRepMax { oneRepMax[exerciseId] = max(oneRepMax[exerciseId] ?? 0, value) }
                    if let value = values.maxReps { maxReps[exerciseId] = max(maxReps[exerciseId] ?? 0, value) }
                }
            }
        }
    }

    private static func personalBestChanges(
        session: CompletedSession,
        sessionDate: Date,
        before: [PersonalBestUpdater.SetSnapshot],
        after: [PersonalBestUpdater.SetSnapshot],
        context: ModelContext,
        history: () -> OtherHistory
    ) -> [RecordChange] {
        let existing = ((try? context.fetch(FetchDescriptor<PersonalBest>())) ?? [])
        let liveByKey = Dictionary(
            existing.filter { $0.deletedAt == nil }.map { ($0.identityKey, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let anyByKey = Dictionary(existing.map { ($0.identityKey, $0) }, uniquingKeysWith: { first, _ in first })
        let newByKey = Dictionary(
            PersonalBestUpdater.candidates(for: after).map { ($0.identityKey, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let oldByKey = Dictionary(
            PersonalBestUpdater.candidates(for: before).map { ($0.identityKey, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let attributedKeys = Set(existing.filter { $0.deletedAt == nil && $0.sourceSessionId == session.id }.map(\.identityKey))
        let keys = Set(newByKey.keys).union(oldByKey.keys).union(attributedKeys)

        var changes: [RecordChange] = []
        for key in keys.sorted() {
            let current = liveByKey[key]
            let attributed = attributedKeys.contains(key)
            let edited = newByKey[key]
            guard let template = edited ?? oldByKey[key] ?? current.map(candidate(from:)) else { continue }
            // Sans record attribue a cette seance ni nouvelle valeur, rien a
            // revoir : une serie supprimee qui ne portait aucun record.
            guard attributed || edited != nil else { continue }

            let lowerIsBetter = template.kind.lowerIsBetter
            let editedValue = edited.map { RecordValue(value: $0.value, sessionId: session.id, achievedAt: sessionDate) }
            let needsHistory = attributed
            let other = needsHistory ? history().bests[key] : nil
            let decision = RecordRevision.revise(
                current: current.map { RecordValue(value: $0.value, sessionId: $0.sourceSessionId, achievedAt: $0.achievedAt) },
                attributedToEditedSession: attributed,
                editedSessionBest: editedValue,
                otherSessionsBest: other?.value,
                lowerIsBetter: lowerIsBetter
            )
            guard decision != .keep else { continue }

            let reps: Int?
            let newText: String?
            switch decision {
            case .set(let value):
                reps = value.sessionId == session.id ? edited?.reps : other?.candidate.reps
                newText = PersonalBest.formatted(value: value.value, kind: template.kind)
            case .remove, .keep:
                reps = nil
                newText = nil
            }
            changes.append(RecordChange(
                target: .personalBest(existing: current ?? anyByKey[key], candidate: template),
                decision: decision,
                reps: reps,
                exerciseName: template.displayName,
                kindLabel: template.kind.displayName,
                oldValue: current.map(\.formattedValue),
                newValue: newText
            ))
        }
        return changes
    }

    private static func candidate(from best: PersonalBest) -> PersonalBestUpdater.Candidate {
        PersonalBestUpdater.Candidate(
            exerciseId: best.exerciseId,
            displayName: best.displayName,
            kind: best.kind,
            configurationKey: best.configurationKey,
            value: best.value,
            reps: best.reps
        )
    }

    /// 1RM estime et maximum de repetitions par exercice, selon les regles
    /// de `RecordDetection`.
    static func exerciseRecordValues(
        _ sets: [PersonalBestUpdater.SetSnapshot]
    ) -> [String: (oneRepMax: Double?, maxReps: Int?)] {
        let working = sets.filter(\.countsAsWorkingSet)
        var result: [String: (oneRepMax: Double?, maxReps: Int?)] = [:]
        for (exerciseId, group) in Dictionary(grouping: working, by: \.exerciseId) {
            let inputs = group.map(\.input)
            let oneRepMax = inputs.compactMap(SetMetrics.estimatedOneRepMax).max()
            let reps = inputs.filter(SetMetrics.allowsRepetitionRecord).map(\.reps).max().flatMap { $0 > 0 ? $0 : nil }
            result[exerciseId] = (oneRepMax, reps)
        }
        return result
    }

    /// Records saisis (`ExerciseRecord`) : ils pilotent les charges en % du
    /// 1RM et ne sont jamais montes sans accord. Sans origine enregistree,
    /// un record est attribue a la seance quand il egale exactement sa
    /// valeur d'avant correction.
    private static func exerciseRecordChanges(
        sessionId: UUID,
        before: [PersonalBestUpdater.SetSnapshot],
        after: [PersonalBestUpdater.SetSnapshot],
        context: ModelContext,
        history: () -> OtherHistory
    ) -> [RecordChange] {
        let records = ((try? context.fetch(FetchDescriptor<ExerciseRecord>())) ?? []).filter { $0.deletedAt == nil }
        let recordByExercise = Dictionary(records.map { ($0.exerciseId, $0) }, uniquingKeysWith: { first, _ in first })
        let old = exerciseRecordValues(before)
        let new = exerciseRecordValues(after)
        let names = Dictionary(
            (before + after).map { ($0.exerciseId, $0.displayName) },
            uniquingKeysWith: { _, last in last }
        )

        var changes: [RecordChange] = []
        for exerciseId in Set(old.keys).union(new.keys).sorted() where !exerciseId.isEmpty {
            let record = recordByExercise[exerciseId]
            let name = record?.displayName ?? names[exerciseId] ?? exerciseId

            let currentOneRepMax = record?.oneRepMax.flatMap { $0 > 0 ? $0 : nil }
            let oldOneRepMax = old[exerciseId]?.oneRepMax
            let attributedOneRepMax: Bool
            if let currentOneRepMax, let oldOneRepMax {
                attributedOneRepMax = abs(oldOneRepMax - currentOneRepMax) < 0.001
            } else {
                attributedOneRepMax = false
            }
            let newOneRepMax = new[exerciseId]?.oneRepMax
            // Un record absent n'est jamais cree en silence par une
            // correction : la fin de seance le propose, ici aussi on ne le
            // cree que s'il existait deja.
            if currentOneRepMax != nil {
                let decision = RecordRevision.revise(
                    current: currentOneRepMax.map { RecordValue(value: $0) },
                    attributedToEditedSession: attributedOneRepMax,
                    editedSessionBest: newOneRepMax.map { RecordValue(value: $0) },
                    otherSessionsBest: attributedOneRepMax ? history().oneRepMax[exerciseId].map { RecordValue(value: $0) } : nil,
                    lowerIsBetter: false,
                    raisesFromOtherSessions: false
                )
                if decision != .keep {
                    changes.append(RecordChange(
                        target: .oneRepMax(existing: record, exerciseId: exerciseId, displayName: name),
                        decision: decision,
                        reps: nil,
                        exerciseName: name,
                        kindLabel: String(localized: "1RM"),
                        oldValue: currentOneRepMax.map { WeightFormatter.string(kilograms: $0) },
                        newValue: decision.value.map { WeightFormatter.string(kilograms: $0) }
                    ))
                }
            }

            let currentReps = record?.maxReps.flatMap { $0 > 0 ? $0 : nil }
            let oldReps = old[exerciseId]?.maxReps
            let attributedReps = currentReps != nil && oldReps == currentReps
            if let currentReps {
                let decision = RecordRevision.revise(
                    current: RecordValue(value: Double(currentReps)),
                    attributedToEditedSession: attributedReps,
                    editedSessionBest: new[exerciseId]?.maxReps.map { RecordValue(value: Double($0)) },
                    otherSessionsBest: attributedReps ? history().maxReps[exerciseId].map { RecordValue(value: Double($0)) } : nil,
                    lowerIsBetter: false,
                    raisesFromOtherSessions: false
                )
                if decision != .keep {
                    changes.append(RecordChange(
                        target: .maxReps(existing: record, exerciseId: exerciseId, displayName: name),
                        decision: decision,
                        reps: nil,
                        exerciseName: name,
                        kindLabel: String(localized: "Répétitions max"),
                        oldValue: String(localized: "\(currentReps) reps"),
                        newValue: decision.value.map { String(localized: "\(Int($0)) reps") }
                    ))
                }
            }
        }
        return changes
    }

    private static func applyRecordChanges(_ changes: [RecordChange], in context: ModelContext, now: Date) {
        for change in changes {
            switch change.target {
            case .personalBest(let existing, let candidate):
                switch change.decision {
                case .keep:
                    continue
                case .remove:
                    existing?.deletedAt = now
                    existing?.updatedAt = now
                case .set(let value):
                    let best = existing ?? {
                        let created = PersonalBest(
                            exerciseId: candidate.exerciseId,
                            displayName: candidate.displayName,
                            kindRaw: candidate.kind.rawValue,
                            configurationKey: candidate.configurationKey,
                            value: value.value
                        )
                        context.insert(created)
                        return created
                    }()
                    best.value = value.value
                    best.reps = change.reps
                    best.sourceSessionId = value.sessionId
                    best.achievedAt = value.achievedAt ?? now
                    best.deletedAt = nil
                    best.updatedAt = now
                }
            case .oneRepMax(let existing, _, _):
                guard let existing else { continue }
                existing.oneRepMax = change.decision.value
                existing.updatedAt = now
            case .maxReps(let existing, _, _):
                guard let existing else { continue }
                existing.maxReps = change.decision.value.map { Int($0) }
                existing.updatedAt = now
            }
        }
    }

    // MARK: - Enregistrement

    /// Applique le brouillon et les consequences sur les records, en UNE
    /// sauvegarde : un echec annule tout (cf. `PersistenceSupport`).
    @discardableResult
    static func apply(
        _ draft: Draft,
        to session: CompletedSession,
        recordChanges: [RecordChange],
        in context: ModelContext,
        now: Date = .now
    ) -> Bool {
        guard issue(in: draft, now: now) == nil else { return false }

        session.date = session.importSource.isEmpty ? draft.end : draft.start
        session.durationSeconds = PastSessionEdit.durationSeconds(start: draft.start, end: draft.end)
        session.effortRating = draft.effortRating.flatMap { SessionEffort.isValid($0) ? $0 : nil }

        let keptIds = Set(draft.exercises.flatMap(\.sets).compactMap(\.existingSetId))
        for set in session.sets where !keptIds.contains(set.id) {
            context.delete(set)
        }
        session.sets.removeAll { !keptIds.contains($0.id) }

        let setsById = Dictionary(session.sets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // Les exercices ajoutes prennent les index d'ordre suivants, dans
        // l'ordre du brouillon ; les series ajoutees, les rangs de saisie
        // suivants.
        var nextOrder = (session.sets.map(\.orderIndex).max() ?? -1) + 1
        var sequence = (session.sets.map(\.sequenceIndex).max() ?? -1) + 1

        for exercise in draft.exercises where !exercise.sets.isEmpty {
            let orderIndex: Int
            if let original = exercise.orderIndex {
                orderIndex = original
            } else {
                orderIndex = nextOrder
                nextOrder += 1
            }
            for draftSet in exercise.sets {
                if let id = draftSet.existingSetId, let set = setsById[id] {
                    let changed = set.weight != draftSet.weight
                        || set.reps != draftSet.reps
                        || set.durationSeconds != draftSet.durationSeconds
                        || set.distanceMeters != draftSet.distanceMeters
                    guard changed else { continue }
                    set.weight = draftSet.weight
                    set.reps = draftSet.reps
                    set.durationSeconds = draftSet.durationSeconds
                    set.distanceMeters = draftSet.distanceMeters
                    set.updatedAt = now
                } else {
                    let set = CompletedSet(
                        exerciseId: exercise.exerciseId,
                        displayName: exercise.displayName,
                        orderIndex: orderIndex,
                        setIndex: draftSet.setIndex,
                        weight: draftSet.weight,
                        reps: draftSet.reps,
                        isWarmup: draftSet.role == .warmup,
                        loadTypeRaw: exercise.loadTypeRaw,
                        roleRaw: draftSet.role.rawValue,
                        sideConventionRaw: exercise.sideConventionRaw,
                        groupId: exercise.groupId,
                        roundIndex: draftSet.roundIndex,
                        subSetIndex: draftSet.subSetIndex,
                        durationSeconds: draftSet.durationSeconds,
                        distanceMeters: draftSet.distanceMeters,
                        formatRaw: exercise.formatRaw,
                        sequenceIndex: sequence,
                        // Ajoutee apres coup : son repos n'a jamais ete
                        // mesure, il reste inconnu.
                        actualRestSeconds: nil,
                        createdAt: now,
                        updatedAt: now
                    )
                    sequence += 1
                    context.insert(set)
                    set.session = session
                    session.sets.append(set)
                }
            }
        }

        applyRecordChanges(recordChanges, in: context, now: now)

        session.editedAt = now
        session.updatedAt = now
        session.revision += 1
        return PersistenceSupport.save(context, action: "Correction de la séance")
    }

    /// Suppression d'une seance de l'historique, records recalcules dans la
    /// meme sauvegarde.
    @discardableResult
    static func delete(
        _ session: CompletedSession,
        in context: ModelContext,
        now: Date = .now
    ) -> Bool {
        let changes = recordChanges(for: session, draft: nil, in: context)
        applyRecordChanges(changes, in: context, now: now)
        context.delete(session)
        return PersistenceSupport.save(context, action: "Suppression de la séance")
    }

    /// Le brouillon differe-t-il de la seance ?
    static func hasChanges(_ draft: Draft, comparedTo session: CompletedSession) -> Bool {
        draft != Self.draft(for: session).withIdentifiers(of: draft)
    }
}

private extension PastSessionEditor.Draft {
    /// Meme brouillon avec les identifiants d'exercice d'un autre : les
    /// identifiants d'exercice sont regeneres a chaque lecture et ne doivent
    /// pas faire croire a une modification.
    func withIdentifiers(of other: PastSessionEditor.Draft) -> PastSessionEditor.Draft {
        var copy = self
        guard copy.exercises.count == other.exercises.count else { return copy }
        copy.exercises = zip(copy.exercises, other.exercises).map { mine, theirs in
            PastSessionEditor.ExerciseDraft(
                id: theirs.id,
                orderIndex: mine.orderIndex,
                exerciseId: mine.exerciseId,
                displayName: mine.displayName,
                loadTypeRaw: mine.loadTypeRaw,
                sideConventionRaw: mine.sideConventionRaw,
                formatRaw: mine.formatRaw,
                groupId: mine.groupId,
                measure: mine.measure,
                sets: mine.sets
            )
        }
        return copy
    }
}

extension RecordRevisionDecision {
    /// Valeur retenue, `nil` pour une suppression ou un statu quo.
    var value: Double? {
        if case .set(let value) = self { return value.value }
        return nil
    }
}
