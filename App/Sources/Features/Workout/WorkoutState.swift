import Foundation
import SwiftData
import MuscuEngine

// Copie en memoire d'une PrescribedExercise pour la duree de la seance :
// remplacer/ajuster le nombre de series pendant la seance ne doit jamais
// muter le programme source (cf. replaceExercise/addSet/removeSet).
struct RunExercise: Identifiable, Codable {
    var id: UUID
    var exerciseId: String
    var displayName: String
    var format: SetFormat
    var sets: Int
    var repsLower: Int
    var repsUpper: Int
    var restSeconds: Int
    var percentOneRepMax: Double?
    var notes: String
    var orderIndex: Int
    var pyramidReps: [Int]
    var pyramidMinRest: Int
    var pyramidMaxRest: Int
    var intervalWork: Int
    var intervalRest: Int
    var intervalRounds: Int
    var amrapSeconds: Int

    init(from prescribed: PrescribedExercise) {
        self.id = prescribed.id
        self.exerciseId = prescribed.exerciseId
        self.displayName = prescribed.displayName
        self.format = prescribed.format
        self.sets = prescribed.sets
        self.repsLower = prescribed.repsLower
        self.repsUpper = prescribed.repsUpper
        self.restSeconds = prescribed.restSeconds
        self.percentOneRepMax = prescribed.percentOneRepMax
        self.notes = prescribed.notes
        self.orderIndex = prescribed.orderIndex
        self.pyramidReps = prescribed.pyramidReps
        self.pyramidMinRest = prescribed.pyramidMinRest
        self.pyramidMaxRest = prescribed.pyramidMaxRest
        self.intervalWork = prescribed.intervalWork
        self.intervalRest = prescribed.intervalRest
        self.intervalRounds = prescribed.intervalRounds
        self.amrapSeconds = prescribed.amrapSeconds
    }

    // Codable manuel (pas la synthese memberwise) : les champs de formats
    // speciaux ont ete ajoutes apres coup, et des snapshots JSON deja
    // persistes sur une ActiveWorkout (cf. runExercisesData) ne les
    // contiennent pas. decodeIfPresent + valeur par defaut garde ces
    // anciens snapshots decodables au lieu de faire echouer toute la
    // reprise de seance.
    private enum CodingKeys: String, CodingKey {
        case id, exerciseId, displayName, format, sets, repsLower, repsUpper
        case restSeconds, percentOneRepMax, notes, orderIndex
        case pyramidReps, pyramidMinRest, pyramidMaxRest
        case intervalWork, intervalRest, intervalRounds, amrapSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        exerciseId = try container.decode(String.self, forKey: .exerciseId)
        displayName = try container.decode(String.self, forKey: .displayName)
        format = try container.decode(SetFormat.self, forKey: .format)
        sets = try container.decode(Int.self, forKey: .sets)
        repsLower = try container.decode(Int.self, forKey: .repsLower)
        repsUpper = try container.decode(Int.self, forKey: .repsUpper)
        restSeconds = try container.decode(Int.self, forKey: .restSeconds)
        percentOneRepMax = try container.decodeIfPresent(Double.self, forKey: .percentOneRepMax)
        notes = try container.decode(String.self, forKey: .notes)
        orderIndex = try container.decode(Int.self, forKey: .orderIndex)
        pyramidReps = try container.decodeIfPresent([Int].self, forKey: .pyramidReps) ?? []
        pyramidMinRest = try container.decodeIfPresent(Int.self, forKey: .pyramidMinRest) ?? 0
        pyramidMaxRest = try container.decodeIfPresent(Int.self, forKey: .pyramidMaxRest) ?? 0
        intervalWork = try container.decodeIfPresent(Int.self, forKey: .intervalWork) ?? 0
        intervalRest = try container.decodeIfPresent(Int.self, forKey: .intervalRest) ?? 0
        intervalRounds = try container.decodeIfPresent(Int.self, forKey: .intervalRounds) ?? 0
        amrapSeconds = try container.decodeIfPresent(Int.self, forKey: .amrapSeconds) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(exerciseId, forKey: .exerciseId)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(format, forKey: .format)
        try container.encode(sets, forKey: .sets)
        try container.encode(repsLower, forKey: .repsLower)
        try container.encode(repsUpper, forKey: .repsUpper)
        try container.encode(restSeconds, forKey: .restSeconds)
        try container.encodeIfPresent(percentOneRepMax, forKey: .percentOneRepMax)
        try container.encode(notes, forKey: .notes)
        try container.encode(orderIndex, forKey: .orderIndex)
        try container.encode(pyramidReps, forKey: .pyramidReps)
        try container.encode(pyramidMinRest, forKey: .pyramidMinRest)
        try container.encode(pyramidMaxRest, forKey: .pyramidMaxRest)
        try container.encode(intervalWork, forKey: .intervalWork)
        try container.encode(intervalRest, forKey: .intervalRest)
        try container.encode(intervalRounds, forKey: .intervalRounds)
        try container.encode(amrapSeconds, forKey: .amrapSeconds)
    }
}

// Phase de la seance : echauffement (avant le premier exercice, si
// warmupEnabled) puis deroule normal. Persistee sur ActiveWorkout pour
// survivre a un kill+resume pendant l'echauffement lui-meme.
enum RunnerPhase: String, Codable {
    case warmup
    case running
}

// Machine a etats de la seance en cours. Ne gere completement dans cette
// tache que les exercices au format classique ; les autres formats sont
// affiches par un ecran relais (cf. WorkoutRunnerView) que la Task 19
// remplacera format par format, sans toucher a cet etat.
@Observable
@MainActor
final class WorkoutState {
    let programSession: ProgramSession
    let modelContext: ModelContext
    let catalogStore: CatalogStore
    let restTimer: RestTimer

    private(set) var exercises: [RunExercise]
    var currentExerciseIndex: Int
    var currentSetIndex: Int
    let startedAt: Date
    private(set) var phase: RunnerPhase

    private(set) var activeWorkout: ActiveWorkout?

    init(
        programSession: ProgramSession,
        modelContext: ModelContext,
        catalogStore: CatalogStore,
        restTimer: RestTimer
    ) {
        self.programSession = programSession
        self.modelContext = modelContext
        self.catalogStore = catalogStore
        self.restTimer = restTimer
        self.exercises = programSession.exercises
            .sorted { $0.orderIndex < $1.orderIndex }
            .map(RunExercise.init)
        self.startedAt = .now
        self.currentExerciseIndex = 0
        self.currentSetIndex = 0
        self.activeWorkout = nil
        self.phase = programSession.warmupEnabled ? .warmup : .running
    }

    private init(
        programSession: ProgramSession,
        modelContext: ModelContext,
        catalogStore: CatalogStore,
        restTimer: RestTimer,
        restoring activeWorkout: ActiveWorkout
    ) {
        // Priorite au snapshot des mutations en memoire (addSet/removeSet/
        // replaceExercise) persiste sur l'ActiveWorkout : sans lui, un
        // kill+resume reconstruirait les exercices depuis la ProgramSession
        // source et perdrait ces mutations, desynchronisant les indices deja
        // persistes du contenu reel de la seance. A defaut (ancienne
        // ActiveWorkout sans snapshot, ou decodage impossible), on retombe
        // sur la reconstruction depuis le programme.
        let restoredExercises: [RunExercise]
        if let data = activeWorkout.runExercisesData,
           let decoded = try? JSONDecoder().decode([RunExercise].self, from: data),
           !decoded.isEmpty {
            restoredExercises = decoded
        } else {
            restoredExercises = programSession.exercises
                .sorted { $0.orderIndex < $1.orderIndex }
                .map(RunExercise.init)
        }

        // Reclampage defensif : les indices persistes doivent rester valides
        // meme si l'ActiveWorkout est desynchronisee (snapshot absent + le
        // programme source a change depuis, corruption, etc.).
        let clampedExerciseIndex = min(max(activeWorkout.exerciseIndex, 0), restoredExercises.count)
        let clampedSetIndex: Int
        if clampedExerciseIndex < restoredExercises.count {
            // Le nombre de "slots" par format differe de `sets` (qui ne
            // vaut jamais pour la pyramide/les intervalles/l'AMRAP, cf.
            // PrescriptionEditorView) : sans passer par WorkoutState.slots,
            // le clampage retomberait a tort sur 0 a chaque reprise en plein
            // milieu d'une pyramide.
            let slotsCount = WorkoutState.totalSlots(for: restoredExercises[clampedExerciseIndex])
            clampedSetIndex = min(max(activeWorkout.setIndex, 0), max(slotsCount - 1, 0))
        } else {
            clampedSetIndex = 0
        }

        self.programSession = programSession
        self.modelContext = modelContext
        self.catalogStore = catalogStore
        self.restTimer = restTimer
        self.startedAt = activeWorkout.startedAt
        self.activeWorkout = activeWorkout
        self.exercises = restoredExercises
        self.currentExerciseIndex = clampedExerciseIndex
        self.currentSetIndex = clampedSetIndex
        self.phase = RunnerPhase(rawValue: activeWorkout.phaseRaw) ?? .running
    }

    // MARK: - Reprise

    // A appeler au lancement de l'app : au plus une ActiveWorkout doit exister.
    static func pendingActiveWorkout(modelContext: ModelContext) -> ActiveWorkout? {
        (try? modelContext.fetch(FetchDescriptor<ActiveWorkout>()))?.first
    }

    // Reconstruit l'etat depuis une ActiveWorkout persistee. Si la ProgramSession
    // source n'existe plus (programme supprime entre-temps), l'ActiveWorkout est
    // abandonnee proprement et la fonction retourne nil.
    static func resume(
        from activeWorkout: ActiveWorkout,
        modelContext: ModelContext,
        catalogStore: CatalogStore,
        restTimer: RestTimer
    ) -> WorkoutState? {
        let programs = (try? modelContext.fetch(FetchDescriptor<Program>())) ?? []
        guard let session = programs.flatMap(\.sessions).first(where: { $0.id == activeWorkout.programSessionId }) else {
            modelContext.delete(activeWorkout)
            try? modelContext.save()
            return nil
        }
        return WorkoutState(
            programSession: session,
            modelContext: modelContext,
            catalogStore: catalogStore,
            restTimer: restTimer,
            restoring: activeWorkout
        )
    }

    // MARK: - Etat courant

    var currentExercise: RunExercise? {
        guard currentExerciseIndex < exercises.count else { return nil }
        return exercises[currentExerciseIndex]
    }

    var isSessionComplete: Bool {
        currentExerciseIndex >= exercises.count
    }

    // Series deja loggees pour cette seance, triees exercice puis serie.
    var loggedSets: [CompletedSet] {
        (activeWorkout?.loggedSets ?? []).sorted {
            ($0.orderIndex, $0.setIndex) < ($1.orderIndex, $1.setIndex)
        }
    }

    // MARK: - Suggestions

    // %1RM + record connu -> charge de travail calculee ; %1RM sans record ->
    // nil (la vue doit demander le 1RM, cf. needsOneRepMax) ; sinon dernier
    // poids logge pour cet exercice.
    func suggestedWeight(for exercise: RunExercise) -> Double? {
        if let percent = exercise.percentOneRepMax {
            // oneRepMax <= 0 (jamais renseigne, valeur par defaut) compte
            // comme "pas de record" : pas de charge calculable.
            guard let oneRepMax = fetchRecord(exerciseId: exercise.exerciseId)?.oneRepMax, oneRepMax > 0 else {
                return nil
            }
            return OneRepMax.workingLoad(oneRepMax: oneRepMax, percent: percent)
        }
        return lastLoggedWeight(for: exercise.exerciseId)
    }

    func needsOneRepMax(for exercise: RunExercise) -> Bool {
        guard let percent = exercise.percentOneRepMax, percent > 0 else { return false }
        let oneRepMax = fetchRecord(exerciseId: exercise.exerciseId)?.oneRepMax
        return oneRepMax == nil || oneRepMax! <= 0
    }

    // Enregistre (ou met a jour) le 1RM connu pour cet exercice, saisi
    // directement ou estime depuis une performance recente.
    func saveOneRepMax(_ value: Double, for exercise: RunExercise) {
        if let record = fetchRecord(exerciseId: exercise.exerciseId) {
            record.oneRepMax = value
            record.updatedAt = .now
        } else {
            let record = ExerciseRecord(exerciseId: exercise.exerciseId, displayName: exercise.displayName, oneRepMax: value)
            modelContext.insert(record)
        }
        try? modelContext.save()
    }

    // "La dernière fois : 4x8 @ 72,5 kg" depuis la CompletedSession la plus
    // recente contenant cet exercice.
    func lastPerformance(for exercise: RunExercise) -> String? {
        guard let session = lastCompletedSession(containing: exercise.exerciseId) else { return nil }
        let matching = session.sets
            .filter { $0.exerciseId == exercise.exerciseId }
            .sorted { $0.setIndex < $1.setIndex }
        guard !matching.isEmpty, let lastSet = matching.last else { return nil }

        let repsCounts = Dictionary(grouping: matching, by: \.reps).mapValues(\.count)
        let modeReps = repsCounts.max { $0.value < $1.value }?.key ?? lastSet.reps

        return "La dernière fois : \(matching.count)x\(modeReps) @ \(Self.formatWeight(lastSet.weight)) kg"
    }

    // MARK: - Actions

    func logSet(weight: Double, reps: Int) {
        guard let exercise = currentExercise else { return }
        insertCompletedSet(
            exerciseId: exercise.exerciseId,
            displayName: exercise.displayName,
            orderIndex: currentExerciseIndex,
            setIndex: currentSetIndex,
            weight: weight,
            reps: reps
        )
        advance(totalSlots: Self.totalSlots(for: exercise), startRestSeconds: exercise.restSeconds)
    }

    // Un palier de pyramide = un CompletedSet (poids du corps, weight 0) ;
    // le repos qui suit depend de l'intensite relative du palier qui vient
    // d'etre fait (cf. Pyramid.adaptiveRest), pas d'un restSeconds fixe.
    // Aucun repos apres le dernier palier (l'exercice est termine).
    func logPyramidStep(reps: Int) {
        guard let exercise = currentExercise, exercise.format == .pyramid else { return }
        let steps = exercise.pyramidReps
        guard !steps.isEmpty else { return }
        let stepIndex = currentSetIndex

        insertCompletedSet(
            exerciseId: exercise.exerciseId,
            displayName: exercise.displayName,
            orderIndex: currentExerciseIndex,
            setIndex: stepIndex,
            weight: 0,
            reps: reps
        )

        let isLastStep = stepIndex + 1 >= steps.count
        let rest = Pyramid.adaptiveRest(
            repsDone: reps,
            maxReps: pyramidMaxReps(for: exercise),
            minRest: exercise.pyramidMinRest,
            maxRest: exercise.pyramidMaxRest
        )
        advance(totalSlots: steps.count, startRestSeconds: isLastStep ? nil : rest)
    }

    // Un bloc d'intervalles = une seule serie loggee (les reps totales sont
    // optionnelles) ; pas de chrono de repos supplementaire, la vue gere
    // elle-meme le decompte travail/repos segment par segment.
    func logIntervalBlock(totalReps: Int) {
        guard let exercise = currentExercise, exercise.format == .intervals else { return }
        insertCompletedSet(
            exerciseId: exercise.exerciseId,
            displayName: exercise.displayName,
            orderIndex: currentExerciseIndex,
            setIndex: 0,
            weight: 0,
            reps: totalReps
        )
        advance(totalSlots: 1, startRestSeconds: nil)
    }

    // Un bloc AMRAP = une seule serie loggee (nb de repetitions totales).
    func logAmrapBlock(reps: Int) {
        guard let exercise = currentExercise, exercise.format == .amrap else { return }
        insertCompletedSet(
            exerciseId: exercise.exerciseId,
            displayName: exercise.displayName,
            orderIndex: currentExerciseIndex,
            setIndex: 0,
            weight: 0,
            reps: reps
        )
        advance(totalSlots: 1, startRestSeconds: nil)
    }

    // MARK: - Echauffement

    // Premier exercice classique de la seance pour lequel une charge de
    // travail est calculable ET suffisante pour justifier une montee en
    // charge (cf. Warmup.rampSets, qui retourne [] sous 30 kg).
    func warmupTargetExercise() -> RunExercise? {
        exercises.first { exercise in
            guard exercise.format == .classic, let weight = suggestedWeight(for: exercise) else { return false }
            return !Warmup.rampSets(workingWeight: weight).isEmpty
        }
    }

    func warmupRampSets() -> [WarmupSet] {
        guard let target = warmupTargetExercise(), let weight = suggestedWeight(for: target) else { return [] }
        return Warmup.rampSets(workingWeight: weight)
    }

    // Loggee avec isWarmup = true, sur l'index reel du futur exercice cible
    // dans `exercises` (currentExerciseIndex vaut encore 0 pendant
    // l'echauffement, qui precede le deroule normal).
    func logWarmupSet(_ warmupSet: WarmupSet, rampIndex: Int) {
        guard let target = warmupTargetExercise(),
              let targetIndex = exercises.firstIndex(where: { $0.id == target.id }) else { return }
        insertCompletedSet(
            exerciseId: target.exerciseId,
            displayName: target.displayName,
            orderIndex: targetIndex,
            setIndex: rampIndex,
            weight: warmupSet.weight,
            reps: warmupSet.reps,
            isWarmup: true
        )
        try? modelContext.save()
    }

    // Passe en phase normale, que l'echauffement ait ete fait entierement,
    // partiellement ou pas du tout ("Passer l'échauffement" a tout moment).
    func finishWarmup() {
        phase = .running
        guard let workout = activeWorkout else { return }
        workout.phaseRaw = RunnerPhase.running.rawValue
        try? modelContext.save()
    }

    // 1RM maxReps connu pour cet exercice ; a defaut, une valeur plausible
    // deduite de la pyramide elle-meme (jamais 0, sinon adaptiveRest
    // retomberait a tort sur minRest a chaque palier).
    func pyramidMaxReps(for exercise: RunExercise) -> Int {
        if let maxReps = fetchRecord(exerciseId: exercise.exerciseId)?.maxReps, maxReps > 0 {
            return maxReps
        }
        let fallback = (exercise.pyramidReps.max() ?? 1) * 2
        return max(1, fallback)
    }

    // Nombre de "slots" (series/paliers/blocs) que compte cet exercice pour
    // l'avancement de la seance, quel que soit son format : `sets` pour le
    // classique, le nombre de paliers pour la pyramide, 1 seul bloc pour
    // les intervalles/l'AMRAP (cf. PrescribedExercise ou `sets` ne vaut
    // jamais pour ces trois derniers formats).
    static func totalSlots(for exercise: RunExercise) -> Int {
        switch exercise.format {
        case .classic:
            return max(1, exercise.sets)
        case .pyramid:
            return max(1, exercise.pyramidReps.count)
        case .intervals, .amrap:
            return 1
        }
    }

    // "Pyramide 2-4-6-4-2" / "8 x 30 s / 30 s" / "AMRAP 60 s" - ligne
    // d'objectif par format, affichee dans le runner (le format classique
    // a deja sa propre ligne dans ClassicExerciseCard).
    static func objectiveLabel(for exercise: RunExercise) -> String {
        switch exercise.format {
        case .classic:
            return ""
        case .pyramid:
            return "Pyramide " + exercise.pyramidReps.map(String.init).joined(separator: "-")
        case .intervals:
            return "\(exercise.intervalRounds) x \(exercise.intervalWork) s / \(exercise.intervalRest) s"
        case .amrap:
            return "AMRAP \(exercise.amrapSeconds) s"
        }
    }

    func skipExercise() {
        guard currentExerciseIndex < exercises.count else { return }
        currentExerciseIndex += 1
        currentSetIndex = 0
        persistProgressIfStarted()
    }

    // Remplace l'exercice courant pour cette seance uniquement : ne touche
    // jamais a la PrescribedExercise du programme.
    func replaceExercise(with catalogExercise: CatalogExercise) {
        guard currentExerciseIndex < exercises.count else { return }
        exercises[currentExerciseIndex].exerciseId = catalogExercise.id
        exercises[currentExerciseIndex].displayName = catalogExercise.nameFr
        persistExercisesSnapshot()
    }

    func addSet() {
        guard currentExerciseIndex < exercises.count else { return }
        exercises[currentExerciseIndex].sets += 1
        persistExercisesSnapshot()
    }

    // "Retirer une série" ne doit jamais faire descendre le nombre de series
    // en dessous du nombre de series deja loggees pour l'exercice courant
    // (currentSetIndex, qui avance sequentiellement depuis 0 via logSet),
    // ni en dessous de 1 : sinon currentSetIndex se retrouverait clampe sur
    // une serie deja loggee, et le prochain logSet persisterait un setIndex
    // DUPLIQUE pour cet exercice. Si la serie retiree etait justement celle
    // en attente de saisie (sets devient == nombre de series loggees), on
    // avance vers l'exercice suivant - meme cheminement que si sa derniere
    // serie venait d'etre loggee (pas de timer de repos si ca termine la
    // seance).
    func removeSet() {
        guard currentExerciseIndex < exercises.count else { return }
        let exercise = exercises[currentExerciseIndex]
        let loggedCount = currentSetIndex
        let minSets = max(1, loggedCount)
        exercises[currentExerciseIndex].sets = max(minSets, exercise.sets - 1)
        persistExercisesSnapshot()

        if currentSetIndex >= exercises[currentExerciseIndex].sets {
            currentExerciseIndex += 1
            currentSetIndex = 0
            persistProgressIfStarted()
            if !isSessionComplete {
                restTimer.start(seconds: exercise.restSeconds)
            }
        }
    }

    // "Abandonner" : supprime la seance en cours et les series deja loggees
    // (cascade sur ActiveWorkout.loggedSets). Rien n'est ecrit a l'historique.
    func discard() {
        guard let workout = activeWorkout else { return }
        modelContext.delete(workout)
        try? modelContext.save()
        activeWorkout = nil
    }

    // Fin de seance : bascule les series loggees vers une CompletedSession
    // (historique), supprime l'ActiveWorkout, sauvegarde.
    func finish() -> CompletedSession {
        let duration = Int(Date.now.timeIntervalSince(startedAt))
        let completedSession = CompletedSession(
            date: .now,
            programName: programSession.program?.name ?? "",
            sessionName: programSession.name,
            durationSeconds: duration
        )
        modelContext.insert(completedSession)

        if let workout = activeWorkout {
            for set in workout.loggedSets {
                set.activeWorkout = nil
                set.session = completedSession
                completedSession.sets.append(set)
            }
            workout.loggedSets.removeAll()
            modelContext.delete(workout)
            activeWorkout = nil
        }

        try? modelContext.save()
        return completedSession
    }

    // MARK: - Prive

    private func persistProgressIfStarted() {
        guard let workout = activeWorkout else { return }
        workout.exerciseIndex = currentExerciseIndex
        workout.setIndex = currentSetIndex
        try? modelContext.save()
    }

    // Persiste un snapshot JSON de `exercises` sur l'ActiveWorkout courante,
    // pour survivre a un kill+resume (cf. commentaire sur
    // ActiveWorkout.runExercisesData). No-op tant que l'ActiveWorkout n'a pas
    // encore ete creee (rien n'est de toute facon persiste avant le premier
    // logSet).
    private func persistExercisesSnapshot() {
        guard let workout = activeWorkout else { return }
        workout.runExercisesData = try? JSONEncoder().encode(exercises)
        try? modelContext.save()
    }

    // Insere un CompletedSet et le rattache a l'ActiveWorkout courante
    // (creee au besoin, paresseusement). Ne fait ni avancer les indices ni
    // sauvegarder : cf. `advance(totalSlots:startRestSeconds:)` pour la
    // suite du log d'une serie classique/pyramide/intervalle/AMRAP, et
    // `logWarmupSet` pour l'echauffement (qui sauvegarde lui-meme).
    private func insertCompletedSet(
        exerciseId: String,
        displayName: String,
        orderIndex: Int,
        setIndex: Int,
        weight: Double,
        reps: Int,
        isWarmup: Bool = false
    ) {
        let newSet = CompletedSet(
            exerciseId: exerciseId,
            displayName: displayName,
            orderIndex: orderIndex,
            setIndex: setIndex,
            weight: weight,
            reps: reps,
            isWarmup: isWarmup
        )
        modelContext.insert(newSet)
        let workout = activeWorkout ?? createActiveWorkout()
        newSet.activeWorkout = workout
        workout.loggedSets.append(newSet)
    }

    // Avance currentSetIndex/currentExerciseIndex apres le log d'une serie
    // ou d'un bloc, quel que soit le format (totalSlots = nb de series pour
    // le classique, nb de paliers pour la pyramide, 1 pour un bloc
    // intervalles/AMRAP) ; persiste la progression, demarre le chrono de
    // repos fourni sauf si la seance est terminee.
    private func advance(totalSlots: Int, startRestSeconds: Int?) {
        if currentSetIndex + 1 < totalSlots {
            currentSetIndex += 1
        } else {
            currentExerciseIndex += 1
            currentSetIndex = 0
        }

        if let workout = activeWorkout {
            workout.exerciseIndex = currentExerciseIndex
            workout.setIndex = currentSetIndex
        }
        try? modelContext.save()

        if !isSessionComplete, let seconds = startRestSeconds {
            restTimer.start(seconds: seconds)
        }
    }

    private func createActiveWorkout() -> ActiveWorkout {
        let workout = ActiveWorkout(
            startedAt: startedAt,
            programSessionId: programSession.id,
            exerciseIndex: currentExerciseIndex,
            setIndex: currentSetIndex,
            phaseRaw: phase.rawValue,
            runExercisesData: try? JSONEncoder().encode(exercises)
        )
        modelContext.insert(workout)
        activeWorkout = workout
        return workout
    }

    private func fetchRecord(exerciseId: String) -> ExerciseRecord? {
        let descriptor = FetchDescriptor<ExerciseRecord>(predicate: #Predicate { $0.exerciseId == exerciseId })
        return try? modelContext.fetch(descriptor).first
    }

    private func lastLoggedWeight(for exerciseId: String) -> Double? {
        let descriptor = FetchDescriptor<CompletedSet>(
            predicate: #Predicate { $0.exerciseId == exerciseId && $0.session != nil }
        )
        guard let sets = try? modelContext.fetch(descriptor), !sets.isEmpty else { return nil }
        let sorted = sets.sorted { lhs, rhs in
            let lhsDate = lhs.session?.date ?? .distantPast
            let rhsDate = rhs.session?.date ?? .distantPast
            if lhsDate != rhsDate { return lhsDate > rhsDate }
            return lhs.setIndex > rhs.setIndex
        }
        return sorted.first?.weight
    }

    private func lastCompletedSession(containing exerciseId: String) -> CompletedSession? {
        let descriptor = FetchDescriptor<CompletedSession>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        guard let sessions = try? modelContext.fetch(descriptor) else { return nil }
        return sessions.first { session in session.sets.contains { $0.exerciseId == exerciseId } }
    }

    static func formatWeight(_ weight: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: weight)) ?? String(format: "%.1f", weight)
    }
}
