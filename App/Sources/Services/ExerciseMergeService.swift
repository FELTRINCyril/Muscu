import Foundation
import SwiftData
import MuscuEngine

/// Fusion d'exercices en double.
///
/// Un meme mouvement enregistre sous deux noms coupe son historique en deux.
/// La detection (`MuscuEngine.DuplicateExercises`) propose des paires ; rien
/// n'est fusionne sans confirmation, paire par paire. La fusion reaffecte
/// TOUT ce qui designe le doublon vers l'exercice conserve, en une seule
/// sauvegarde : series, records, prescriptions, modeles, annotations de
/// bibliotheque, collections, objectifs, exclusions, journal d'adaptation.
///
/// Le doublon n'est pas supprime : il est REDIRIGE
/// (`CustomExercise.mergedIntoExerciseId`). Une reference ancienne — archive
/// importee, appareil pas encore synchronise — se resout ainsi vers
/// l'exercice retenu (`applyPendingRedirects`).
@MainActor
enum ExerciseMergeService {
    /// Paires ecartees par l'utilisateur (« Ce ne sont pas des doublons »).
    /// Preference locale : elle n'a de sens que pour la liste de cet appareil.
    static let dismissedKey = "exerciseMerge.dismissedPairs"

    static var dismissedPairs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: dismissedKey) ?? []) }
        set { UserDefaults.standard.set(newValue.sorted(), forKey: dismissedKey) }
    }

    enum MergeError: LocalizedError, Equatable {
        case workoutInProgress
        case duplicateNotFound
        case sameExercise
        case wouldCreateCycle
        case saveFailed

        var errorDescription: String? {
            switch self {
            case .workoutInProgress:
                return String(localized: "Une séance est en cours : terminez-la ou abandonnez-la avant de fusionner des exercices.")
            case .duplicateNotFound:
                return String(localized: "L’exercice à fusionner n’existe plus ou a déjà été fusionné.")
            case .sameExercise:
                return String(localized: "Un exercice ne peut pas être fusionné avec lui-même.")
            case .wouldCreateCycle:
                return String(localized: "Cette fusion créerait une boucle : l’exercice conservé est lui-même redirigé vers le doublon.")
            case .saveFailed:
                return String(localized: "La fusion n’a pas pu être enregistrée. Rien n’a été modifié.")
            }
        }
    }

    /// Ce que la fusion a deplace, pour le compte rendu affiche apres coup.
    struct Report: Equatable {
        var sets = 0
        var sessions = 0
        var prescriptions = 0
        var templates = 0
        var goals = 0
        /// Records repris du doublon parce qu'ils etaient meilleurs.
        var recordsGained = 0
        var otherReferences = 0

        var isEmpty: Bool {
            sets == 0 && prescriptions == 0 && templates == 0 && goals == 0 && recordsGained == 0 && otherReferences == 0
        }
    }

    // MARK: - Détection

    /// Paires candidates, des plus sures aux plus incertaines.
    static func pairs(in context: ModelContext, catalog: [CatalogExercise]) -> [DuplicatePair] {
        let customs = activeCustomExercises(in: context)
        guard !customs.isEmpty else { return [] }

        let usage = usageIndex(in: context)
        let customCandidates = customs.map { exercise in
            let id = exercise.id.uuidString
            return DuplicateCandidate(
                id: id,
                name: exercise.name,
                equipment: exercise.equipment,
                primaryMuscles: exercise.primaryMuscles,
                isCatalog: false,
                sessionCount: usage[id]?.sessions.count ?? 0,
                setCount: usage[id]?.sets ?? 0,
                firstUsedAt: usage[id]?.firstUsedAt
            )
        }
        let catalogCandidates = catalog.map { exercise in
            DuplicateCandidate(
                id: exercise.id,
                name: exercise.nameFr,
                alternateName: exercise.name,
                equipment: exercise.equipment ?? "",
                primaryMuscles: exercise.primaryMuscles,
                isCatalog: true,
                sessionCount: usage[exercise.id]?.sessions.count ?? 0,
                setCount: usage[exercise.id]?.sets ?? 0,
                firstUsedAt: usage[exercise.id]?.firstUsedAt
            )
        }
        return DuplicateExercises.pairs(custom: customCandidates, catalog: catalogCandidates, dismissed: dismissedPairs)
    }

    static func dismiss(_ pair: DuplicatePair) {
        var dismissed = dismissedPairs
        dismissed.insert(pair.id)
        dismissedPairs = dismissed
    }

    /// Exercices personnalises actifs : ni supprimes, ni deja fusionnes.
    static func activeCustomExercises(in context: ModelContext) -> [CustomExercise] {
        ((try? context.fetch(FetchDescriptor<CustomExercise>(sortBy: [SortDescriptor(\.name)]))) ?? [])
            .filter { $0.deletedAt == nil && $0.mergedIntoExerciseId == nil }
    }

    // MARK: - Fusion

    /// Fusionne `duplicateId` (exercice personnalise) dans `survivorId`.
    ///
    /// Tout est fait dans le contexte puis enregistre en UNE sauvegarde : un
    /// echec annule l'ensemble (`PersistenceSupport` fait le rollback).
    @discardableResult
    static func merge(
        duplicateId: String,
        into survivorId: String,
        survivorName: String,
        in context: ModelContext,
        now: Date = .now
    ) throws -> Report {
        guard duplicateId != survivorId else { throw MergeError.sameExercise }
        guard !hasWorkoutInProgress(in: context) else { throw MergeError.workoutInProgress }
        guard let duplicate = activeCustomExercises(in: context).first(where: { $0.id.uuidString == duplicateId }) else {
            throw MergeError.duplicateNotFound
        }
        guard !ExerciseMerge.wouldCreateCycle(duplicate: duplicateId, survivor: survivorId, redirects: redirects(in: context)) else {
            throw MergeError.wouldCreateCycle
        }

        let report = reassign(from: duplicateId, to: survivorId, survivorName: survivorName, in: context, now: now)
        duplicate.mergedIntoExerciseId = survivorId
        duplicate.isFavorite = false
        duplicate.updatedAt = now

        guard PersistenceSupport.save(context, action: "Fusion d’exercices") else {
            throw MergeError.saveFailed
        }
        DiagnosticsCenter.record(.store, .info, code: "exercise.merged", detail: "\(report.sets) série(s), \(report.prescriptions) prescription(s)")
        return report
    }

    /// Applique les redirections dont les references n'ont pas encore ete
    /// reecrites sur cet appareil : fusion recue par la synchronisation ou
    /// par une archive. Idempotent ; ne fait rien pendant une seance en
    /// cours (elle sera traitee au lancement suivant).
    @discardableResult
    static func applyPendingRedirects(in context: ModelContext, now: Date = .now) -> Bool {
        guard !hasWorkoutInProgress(in: context) else { return false }
        let map = redirects(in: context)
        guard !map.isEmpty else { return false }

        let customs = (try? context.fetch(FetchDescriptor<CustomExercise>())) ?? []
        let names = Dictionary(customs.map { ($0.id.uuidString, $0.name) }, uniquingKeysWith: { first, _ in first })
        var changed = false
        for duplicateId in map.keys.sorted() {
            let target = ExerciseMerge.resolve(duplicateId, redirects: map)
            guard target != duplicateId else { continue }
            let name = names[target] ?? catalogName(for: target) ?? target
            let report = reassign(from: duplicateId, to: target, survivorName: name, in: context, now: now)
            if !report.isEmpty { changed = true }
        }
        guard changed else { return false }
        return PersistenceSupport.save(context, action: "Application des fusions d’exercices")
    }

    // MARK: - Réaffectation

    /// Reecrit, dans le contexte, toutes les references a `duplicateId`.
    /// N'enregistre rien : l'appelant sauvegarde une seule fois.
    static func reassign(
        from duplicateId: String,
        to survivorId: String,
        survivorName: String,
        in context: ModelContext,
        now: Date
    ) -> Report {
        var report = Report()

        // Series de l'historique. Le nom affiche reste celui de la seance :
        // c'est un instantane de ce qui a ete fait.
        let sets = (try? context.fetch(FetchDescriptor<CompletedSet>(
            predicate: #Predicate { $0.exerciseId == duplicateId || $0.plannedExerciseId == duplicateId }
        ))) ?? []
        var sessionIds: Set<UUID> = []
        for set in sets {
            if set.exerciseId == duplicateId {
                set.exerciseId = survivorId
                report.sets += 1
            }
            if set.plannedExerciseId == duplicateId { set.plannedExerciseId = survivorId }
            set.updatedAt = now
            if let session = set.session, sessionIds.insert(session.id).inserted {
                session.updatedAt = now
            }
        }
        report.sessions = sessionIds.count

        // Prescriptions des programmes.
        let prescriptions = (try? context.fetch(FetchDescriptor<PrescribedExercise>(
            predicate: #Predicate { $0.exerciseId == duplicateId }
        ))) ?? []
        for prescription in prescriptions {
            prescription.exerciseId = survivorId
            prescription.displayName = survivorName
            prescription.touch(now: now)
        }
        report.prescriptions = prescriptions.count

        report.templates = reassignTemplates(from: duplicateId, to: survivorId, survivorName: survivorName, in: context, now: now)
        report.goals = reassignGoals(from: duplicateId, to: survivorId, in: context, now: now)
        report.recordsGained = reassignPersonalBests(from: duplicateId, to: survivorId, survivorName: survivorName, in: context, now: now)
            + reassignExerciseRecords(from: duplicateId, to: survivorId, survivorName: survivorName, in: context, now: now)
        report.otherReferences = reassignLibrary(from: duplicateId, to: survivorId, in: context, now: now)
            + reassignLists(from: duplicateId, to: survivorId, in: context, now: now)
        return report
    }

    private static func reassignTemplates(from duplicateId: String, to survivorId: String, survivorName: String, in context: ModelContext, now: Date) -> Int {
        var count = 0
        for template in (try? context.fetch(FetchDescriptor<SessionTemplate>())) ?? [] {
            guard var payload = TemplateService.payload(of: template) else { continue }
            var touched = false
            for sessionIndex in payload.sessions.indices {
                for exerciseIndex in payload.sessions[sessionIndex].exercises.indices
                where payload.sessions[sessionIndex].exercises[exerciseIndex].exerciseId == duplicateId {
                    payload.sessions[sessionIndex].exercises[exerciseIndex].exerciseId = survivorId
                    payload.sessions[sessionIndex].exercises[exerciseIndex].displayName = survivorName
                    touched = true
                }
            }
            // Un modele qu'on ne sait pas reencoder garde son contenu
            // d'origine plutot que d'etre vide.
            guard touched, let data = try? JSONEncoder().encode(payload) else { continue }
            template.payloadData = data
            template.updatedAt = now
            count += 1
        }
        return count
    }

    private static func reassignGoals(from duplicateId: String, to survivorId: String, in context: ModelContext, now: Date) -> Int {
        var count = 0
        for goal in (try? context.fetch(FetchDescriptor<TrainingGoal>())) ?? [] {
            guard let target = goal.target else { continue }
            let replaced = target.replacingExercise(duplicateId, with: survivorId)
            guard replaced != target else { continue }
            goal.target = replaced
            goal.updatedAt = now
            count += 1
        }
        return count
    }

    /// Records types : pour chaque nature et configuration, le meilleur des
    /// deux exercices est conserve (`ExerciseMerge.reconcile`) — jamais de
    /// regression. Renvoie le nombre de records repris du doublon.
    private static func reassignPersonalBests(from duplicateId: String, to survivorId: String, survivorName: String, in context: ModelContext, now: Date) -> Int {
        let all = (try? context.fetch(FetchDescriptor<PersonalBest>())) ?? []
        let duplicates = all.filter { $0.exerciseId == duplicateId && $0.deletedAt == nil }
        var gained = 0

        for moved in duplicates {
            let key = PersonalBest.identityKey(exerciseId: survivorId, kind: moved.kind, configurationKey: moved.configurationKey)
            let sameKey = all.filter { $0.identityKey == key }
            let live = sameKey.first { $0.deletedAt == nil }

            guard let kept = live ?? sameKey.first else {
                // Aucun record equivalent : le record du doublon change
                // simplement d'exercice, avec son origine.
                moved.exerciseId = survivorId
                moved.displayName = survivorName
                moved.updatedAt = now
                gained += 1
                continue
            }

            let decision = ExerciseMerge.reconcile(
                survivor: live.map { RecordValue(value: $0.value, sessionId: $0.sourceSessionId, achievedAt: $0.achievedAt) },
                duplicate: RecordValue(value: moved.value, sessionId: moved.sourceSessionId, achievedAt: moved.achievedAt),
                lowerIsBetter: moved.kind.lowerIsBetter
            )
            if decision?.fromDuplicate == true {
                kept.value = moved.value
                kept.reps = moved.reps
                kept.achievedAt = moved.achievedAt
                kept.sourceSessionId = moved.sourceSessionId
                kept.deletedAt = nil
                kept.updatedAt = now
                gained += 1
            }
            // Suppression LOGIQUE : la synchronisation propage le retrait.
            moved.deletedAt = now
            moved.updatedAt = now
        }
        return gained
    }

    /// Records saisis ou valides (1RM, repetitions max) : maximum des deux.
    private static func reassignExerciseRecords(from duplicateId: String, to survivorId: String, survivorName: String, in context: ModelContext, now: Date) -> Int {
        let all = (try? context.fetch(FetchDescriptor<ExerciseRecord>())) ?? []
        guard let moved = all.first(where: { $0.exerciseId == duplicateId && $0.deletedAt == nil }) else { return 0 }
        guard let kept = all.first(where: { $0.exerciseId == survivorId && $0.deletedAt == nil }) else {
            moved.exerciseId = survivorId
            moved.displayName = survivorName
            moved.updatedAt = now
            return 1
        }

        var gained = 0
        if let value = moved.oneRepMax, value > (kept.oneRepMax ?? 0) {
            kept.oneRepMax = value
            gained += 1
        }
        if let reps = moved.maxReps, reps > (kept.maxReps ?? 0) {
            kept.maxReps = reps
            gained += 1
        }
        kept.updatedAt = now
        // Meme traitement que la suppression d'un record depuis l'ecran
        // Records : ce type de record n'a pas de suppression logique.
        for duplicate in all where duplicate.exerciseId == duplicateId {
            context.delete(duplicate)
        }
        return gained
    }

    /// Favori, tags, derniere utilisation et lien de demonstration.
    private static func reassignLibrary(from duplicateId: String, to survivorId: String, in context: ModelContext, now: Date) -> Int {
        let entries = (try? context.fetch(FetchDescriptor<ExerciseLibraryEntry>())) ?? []
        guard let moved = entries.first(where: { $0.exerciseId == duplicateId }) else { return 0 }
        guard let kept = entries.first(where: { $0.exerciseId == survivorId }) else {
            moved.exerciseId = survivorId
            moved.updatedAt = now
            return 1
        }
        kept.isFavorite = kept.isFavorite || moved.isFavorite
        kept.tags = kept.tags.union(moved.tags)
        kept.lastUsedAt = [kept.lastUsedAt, moved.lastUsedAt].compactMap { $0 }.max()
        if (kept.demoURL ?? "").isEmpty { kept.demoURL = moved.demoURL }
        kept.deletedAt = nil
        kept.updatedAt = now
        context.delete(moved)
        return 1
    }

    /// Collections, exercices exclus du profil, journal d'adaptation.
    private static func reassignLists(from duplicateId: String, to survivorId: String, in context: ModelContext, now: Date) -> Int {
        var count = 0
        for collection in (try? context.fetch(FetchDescriptor<ExerciseCollection>())) ?? []
        where collection.exerciseIds.contains(duplicateId) {
            collection.exerciseIds = ExerciseMerge.replacing(duplicateId, with: survivorId, in: collection.exerciseIds)
            collection.updatedAt = now
            count += 1
        }
        for profile in (try? context.fetch(FetchDescriptor<AthleteProfile>())) ?? []
        where profile.excludedExerciseIds.contains(duplicateId) {
            profile.excludedExerciseIds = ExerciseMerge.replacing(duplicateId, with: survivorId, in: profile.excludedExerciseIds)
            profile.touch(now: now)
            count += 1
        }
        for entry in (try? context.fetch(FetchDescriptor<AdaptationEntry>())) ?? []
        where entry.exerciseId == duplicateId || entry.previousExerciseId == duplicateId {
            if entry.exerciseId == duplicateId { entry.exerciseId = survivorId }
            if entry.previousExerciseId == duplicateId { entry.previousExerciseId = survivorId }
            entry.updatedAt = now
            count += 1
        }
        return count
    }

    // MARK: - Lecture

    private struct Usage {
        var sessions: Set<UUID> = []
        var sets = 0
        var firstUsedAt: Date?
    }

    /// Historique par exercice : seances, series de travail, premiere date.
    private static func usageIndex(in context: ModelContext) -> [String: Usage] {
        var result: [String: Usage] = [:]
        for session in (try? context.fetch(FetchDescriptor<CompletedSession>())) ?? [] {
            for set in session.sets where set.role.countsAsWorkingSet && !set.exerciseId.isEmpty {
                var usage = result[set.exerciseId] ?? Usage()
                usage.sessions.insert(session.id)
                usage.sets += 1
                usage.firstUsedAt = min(usage.firstUsedAt ?? session.date, session.date)
                result[set.exerciseId] = usage
            }
        }
        return result
    }

    /// Redirections connues : doublon -> exercice cible.
    static func redirects(in context: ModelContext) -> [String: String] {
        var result: [String: String] = [:]
        for custom in (try? context.fetch(FetchDescriptor<CustomExercise>())) ?? [] {
            guard custom.deletedAt == nil, let target = custom.mergedIntoExerciseId, !target.isEmpty else { continue }
            result[custom.id.uuidString] = target
        }
        return result
    }

    private static func hasWorkoutInProgress(in context: ModelContext) -> Bool {
        ((try? context.fetchCount(FetchDescriptor<ActiveWorkout>())) ?? 0) > 0
    }

    /// Nom francais d'un exercice du catalogue, lu une seule fois.
    private static func catalogName(for exerciseId: String) -> String? {
        catalogNames[exerciseId]
    }

    private static let catalogNames: [String: String] = {
        guard let catalog = try? ExerciseCatalog.load() else { return [:] }
        return Dictionary(catalog.all.map { ($0.id, $0.nameFr) }, uniquingKeysWith: { first, _ in first })
    }()
}
