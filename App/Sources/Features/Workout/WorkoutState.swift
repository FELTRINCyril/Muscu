import Foundation
import SwiftData
import MuscuEngine

// Copie en memoire d'une PrescribedExercise pour la duree de la seance :
// remplacer/ajuster le nombre de series pendant la seance ne doit jamais
// muter le programme source (cf. replaceExercise/addSet/removeSet).
struct RunExercise: Identifiable {
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
    }
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
    }

    private init(
        programSession: ProgramSession,
        modelContext: ModelContext,
        catalogStore: CatalogStore,
        restTimer: RestTimer,
        restoring activeWorkout: ActiveWorkout
    ) {
        self.programSession = programSession
        self.modelContext = modelContext
        self.catalogStore = catalogStore
        self.restTimer = restTimer
        self.exercises = programSession.exercises
            .sorted { $0.orderIndex < $1.orderIndex }
            .map(RunExercise.init)
        self.startedAt = activeWorkout.startedAt
        self.currentExerciseIndex = activeWorkout.exerciseIndex
        self.currentSetIndex = activeWorkout.setIndex
        self.activeWorkout = activeWorkout
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
            guard let oneRepMax = fetchRecord(exerciseId: exercise.exerciseId)?.oneRepMax else {
                return nil
            }
            return OneRepMax.workingLoad(oneRepMax: oneRepMax, percent: percent)
        }
        return lastLoggedWeight(for: exercise.exerciseId)
    }

    func needsOneRepMax(for exercise: RunExercise) -> Bool {
        guard let percent = exercise.percentOneRepMax, percent > 0 else { return false }
        return fetchRecord(exerciseId: exercise.exerciseId)?.oneRepMax == nil
    }

    func estimateOneRepMax(weight: Double, reps: Int) -> Double {
        OneRepMax.epley(weight: weight, reps: reps)
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

        let newSet = CompletedSet(
            exerciseId: exercise.exerciseId,
            displayName: exercise.displayName,
            orderIndex: currentExerciseIndex,
            setIndex: currentSetIndex,
            weight: weight,
            reps: reps
        )
        modelContext.insert(newSet)

        let workout = activeWorkout ?? createActiveWorkout()
        newSet.activeWorkout = workout
        workout.loggedSets.append(newSet)

        if currentSetIndex + 1 < exercise.sets {
            currentSetIndex += 1
        } else {
            currentExerciseIndex += 1
            currentSetIndex = 0
        }
        workout.exerciseIndex = currentExerciseIndex
        workout.setIndex = currentSetIndex

        try? modelContext.save()

        if !isSessionComplete {
            restTimer.start(seconds: exercise.restSeconds)
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
    }

    func addSet() {
        guard currentExerciseIndex < exercises.count else { return }
        exercises[currentExerciseIndex].sets += 1
    }

    func removeSet() {
        guard currentExerciseIndex < exercises.count else { return }
        exercises[currentExerciseIndex].sets = max(1, exercises[currentExerciseIndex].sets - 1)
        if currentSetIndex >= exercises[currentExerciseIndex].sets {
            currentSetIndex = exercises[currentExerciseIndex].sets - 1
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

    private func createActiveWorkout() -> ActiveWorkout {
        let workout = ActiveWorkout(
            startedAt: startedAt,
            programSessionId: programSession.id,
            exerciseIndex: currentExerciseIndex,
            setIndex: currentSetIndex
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
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: weight)) ?? String(format: "%.1f", weight)
    }
}
