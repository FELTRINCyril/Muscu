import XCTest
import SwiftData
import MuscuEngine
@testable import Muscu

/// Lot 3 : seance libre, ajout et ordre des exercices en seance, series au
/// temps et a la distance, repos reel, note d'effort.
@MainActor
final class FreeSessionTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private var restTimer: RestTimer!

    override func setUp() async throws {
        container = try TestStore.makeContainer()
        restTimer = RestTimer()
    }

    override func tearDown() async throws {
        restTimer.skip()
        restTimer = nil
        container = nil
    }

    private func makeFreeState() -> WorkoutState {
        WorkoutState(freeSessionWith: context, catalogStore: CatalogStore(), restTimer: restTimer)
    }

    private func resume() throws -> WorkoutState {
        let active = try XCTUnwrap(context.fetch(FetchDescriptor<ActiveWorkout>()).first)
        return try XCTUnwrap(WorkoutState.resume(
            from: active,
            modelContext: context,
            catalogStore: CatalogStore(),
            restTimer: RestTimer()
        ))
    }

    private func makeProgramSession(_ names: [String]) throws -> ProgramSession {
        let exercises = names.enumerated().map { index, name in
            PrescribedExercise(
                exerciseId: name,
                displayName: name,
                orderIndex: index,
                sets: 2,
                repsLower: 8,
                repsUpper: 8,
                restSeconds: 60,
                loadKindRaw: LoadKind.external.rawValue
            )
        }
        let session = ProgramSession(name: "Push", orderIndex: 0, exercises: exercises)
        context.insert(Program(name: "PPL", sessions: [session]))
        try context.save()
        return session
    }

    // MARK: - Seance libre

    func testFreeSessionStartsEmptyAndWaitsForAnExercise() throws {
        let state = makeFreeState()

        XCTAssertTrue(state.isFreeSession)
        XCTAssertEqual(state.phase, .running, "Pas d'échauffement guidé sans exercice")
        XCTAssertEqual(state.currentStep, .finished)
        XCTAssertFalse(state.isSessionComplete, "Un déroulé vide n'est pas une séance terminée")
        let active = try XCTUnwrap(context.fetch(FetchDescriptor<ActiveWorkout>()).first)
        XCTAssertTrue(active.isFreeSession)

        state.addExercise(exerciseId: "squat", displayName: "Squat")
        XCTAssertEqual(state.currentTarget?.exercise.exerciseId, "squat")
        XCTAssertEqual(state.currentTarget?.totalSets, 3)
    }

    func testFreeSessionSurvivesKillAndJoinsHistoryWithoutProgram() throws {
        let state = makeFreeState()
        state.addExercise(exerciseId: "squat", displayName: "Squat")
        state.logSet(weight: 100, reps: 5)

        // Kill de l'application : reprise depuis la seule ActiveWorkout.
        let resumed = try resume()
        XCTAssertTrue(resumed.isFreeSession)
        XCTAssertEqual(resumed.exercises.map(\.exerciseId), ["squat"])
        XCTAssertEqual(resumed.currentTarget?.setNumber, 2)
        XCTAssertEqual(resumed.loggedSets.count, 1)

        resumed.logSet(weight: 100, reps: 5)
        resumed.logSet(weight: 100, reps: 4)
        XCTAssertTrue(resumed.isPlanExhausted)
        XCTAssertFalse(resumed.isSessionComplete, "La séance libre attend l'exercice suivant")

        resumed.addExercise(exerciseId: "row", displayName: "Rowing")
        XCTAssertEqual(resumed.currentTarget?.exercise.exerciseId, "row")
        resumed.logSet(weight: 60, reps: 10)

        resumed.requestEnd()
        XCTAssertTrue(resumed.isSessionComplete)
        let completed = try XCTUnwrap(resumed.finish(effortRating: 7))

        XCTAssertNil(completed.programId)
        XCTAssertNil(completed.programSessionId)
        XCTAssertEqual(completed.programName, "")
        XCTAssertEqual(completed.sessionName, WorkoutState.freeSessionTitle)
        XCTAssertEqual(completed.effortRating, 7)
        XCTAssertEqual(completed.sets.count, 4)
        XCTAssertEqual(Set(completed.sets.filter { $0.exerciseId == "row" }.map(\.orderIndex)), [1])
        XCTAssertTrue(try context.fetch(FetchDescriptor<ActiveWorkout>()).isEmpty)
    }

    func testFreeSessionWithoutSnapshotRebuildsItsPlanFromLoggedSets() throws {
        let state = makeFreeState()
        state.addExercise(exerciseId: "squat", displayName: "Squat")
        state.logSet(weight: 100, reps: 5)
        let active = try XCTUnwrap(context.fetch(FetchDescriptor<ActiveWorkout>()).first)
        // Archive ou synchronisation : l'instantane du deroule est absent.
        active.planData = nil
        try context.save()

        let resumed = try resume()
        XCTAssertEqual(resumed.exercises.map(\.exerciseId), ["squat"])
        resumed.addExercise(exerciseId: "row", displayName: "Rowing")
        XCTAssertEqual(resumed.exercises.map(\.exerciseId), ["squat", "row"])
    }

    func testInvalidEffortIsNotStored() throws {
        let state = makeFreeState()
        state.addExercise(exerciseId: "squat", displayName: "Squat")
        state.logSet(weight: 100, reps: 5)
        state.requestEnd()
        let completed = try XCTUnwrap(state.finish(effortRating: 0))
        XCTAssertNil(completed.effortRating, "Zéro n'est pas une note : la séance reste non notée")
    }

    func testActiveFreeSessionFlagSurvivesExport() {
        let workout = ActiveWorkout(programSessionId: UUID(), isFreeSession: true)
        let dto = ExportImport.dto(from: workout)
        XCTAssertEqual(dto.isFreeSession, true)
        XCTAssertTrue(ExportImport.model(from: dto).isFreeSession)

        let legacy = ExportImport.dto(from: ActiveWorkout(programSessionId: UUID()))
        XCTAssertNil(legacy.isFreeSession, "Clé absente pour une séance de programme")
    }

    // MARK: - Ajout et ordre en seance de programme

    func testAddedExerciseDoesNotTouchTheProgram() throws {
        let session = try makeProgramSession(["bench", "fly"])
        let state = WorkoutState(programSession: session, modelContext: context, catalogStore: CatalogStore(), restTimer: restTimer)
        state.finishWarmup()

        state.addExercise(exerciseId: "dips", displayName: "Dips")

        XCTAssertEqual(state.exercises.map(\.exerciseId), ["bench", "fly", "dips"])
        XCTAssertEqual(session.exercises.count, 2, "Le programme n'est jamais modifié")
        XCTAssertEqual(try resume().exercises.map(\.exerciseId), ["bench", "fly", "dips"])
    }

    func testReorderKeepsStartedExercisesAndPersists() throws {
        let session = try makeProgramSession(["bench", "fly", "dips"])
        let state = WorkoutState(programSession: session, modelContext: context, catalogStore: CatalogStore(), restTimer: restTimer)
        state.finishWarmup()
        state.logSet(weight: 80, reps: 8)

        // « bench » est commencé : seuls fly et dips sont proposés.
        let movable = state.reorderableNodes
        XCTAssertEqual(movable.flatMap(\.exercises).map(\.exerciseId), ["fly", "dips"])

        XCTAssertTrue(state.reorderRemaining(movable.reversed().map(\.id)))
        XCTAssertEqual(state.exercises.map(\.exerciseId), ["bench", "dips", "fly"])
        XCTAssertEqual(state.currentTarget?.exercise.exerciseId, "bench", "L'exercice en cours ne bouge pas")
        XCTAssertEqual(state.loggedSets.first?.orderIndex, 0)

        XCTAssertFalse(state.reorderRemaining([movable[0].id]), "Un ordre incomplet est refusé")

        let resumed = try resume()
        XCTAssertEqual(resumed.exercises.map(\.exerciseId), ["bench", "dips", "fly"])
    }

    // MARK: - Repos reel

    func testActualRestIsMeasuredFromThePreviousSet() throws {
        let session = try makeProgramSession(["bench"])
        let state = WorkoutState(programSession: session, modelContext: context, catalogStore: CatalogStore(), restTimer: restTimer)
        state.finishWarmup()

        state.logSet(weight: 80, reps: 8)
        let first = try XCTUnwrap(state.loggedSets.first)
        XCTAssertNil(first.actualRestSeconds, "Première série : rien avant")

        // La série précédente a été validée il y a 95 s.
        first.createdAt = Date.now.addingTimeInterval(-95)
        state.logSet(weight: 80, reps: 8)
        let second = try XCTUnwrap(state.loggedSets.last)
        let rest = try XCTUnwrap(second.actualRestSeconds)
        XCTAssertEqual(Double(rest), 95, accuracy: 2)
    }

    func testLongInterruptionIsNotARest() throws {
        let session = try makeProgramSession(["bench"])
        let state = WorkoutState(programSession: session, modelContext: context, catalogStore: CatalogStore(), restTimer: restTimer)
        state.finishWarmup()
        state.logSet(weight: 80, reps: 8)
        try XCTUnwrap(state.loggedSets.first).createdAt = Date.now.addingTimeInterval(-2 * 3_600)

        state.logSet(weight: 80, reps: 8)
        XCTAssertNil(state.loggedSets.last?.actualRestSeconds)
    }

    // MARK: - Series au temps et a la distance

    func testPrescriptionMeasureReachesThePlan() throws {
        let plank = PrescribedExercise(exerciseId: "plank", displayName: "Gainage", orderIndex: 0, sets: 3, repsLower: 1, repsUpper: 1, restSeconds: 60)
        plank.measure = .duration
        XCTAssertEqual(plank.targetDurationSeconds, SetMeasure.defaultTargetDurationSeconds)
        XCTAssertEqual(plank.targetDistanceMeters, 0)

        let plan = WorkoutPlanBuilder.plan(for: plank)
        XCTAssertEqual(plan.effectiveMeasure, .duration)
        XCTAssertEqual(plan.targetDurationSeconds, SetMeasure.defaultTargetDurationSeconds)
        XCTAssertNil(plan.targetDistanceMeters)

        plank.measure = .weightReps
        XCTAssertEqual(plank.targetDurationSeconds, 0)

        plank.measure = .distance
        plank.formatRaw = SetFormat.dropset.rawValue
        XCTAssertEqual(WorkoutPlanBuilder.plan(for: plank).effectiveMeasure, .weightReps, "Mesure réservée au format classique")
    }

    func testTimedSetIsLoggedWithoutTonnageAndMakesADurationRecord() throws {
        let state = makeFreeState()
        state.addExercise(exerciseId: "plank", displayName: "Gainage")
        state.setMeasure(.duration)
        XCTAssertEqual(state.currentTarget?.exercise.effectiveMeasure, .duration)

        // Une durée nulle n'est pas une série.
        state.logMeasuredSet(MeasuredSetResult(durationSeconds: 0, distanceMeters: nil))
        XCTAssertTrue(state.loggedSets.isEmpty)

        state.logMeasuredSet(MeasuredSetResult(durationSeconds: 45, distanceMeters: nil))
        state.logMeasuredSet(MeasuredSetResult(durationSeconds: 70, distanceMeters: nil), weight: 10)
        XCTAssertEqual(state.loggedSets.map(\.reps), [0, 0])
        XCTAssertEqual(state.loggedSets.map(\.durationSeconds), [45, 70])
        XCTAssertEqual(state.currentTarget?.setNumber, 3, "La série au temps fait avancer la séance")

        state.requestEnd()
        let completed = try XCTUnwrap(state.finish())
        let tonnage = CompletedSetPresentation.tonnage(for: completed, fallbackBodyweight: 80)
        XCTAssertEqual(tonnage.total, 0)
        XCTAssertEqual(tonnage.unknownSets, 0, "Pas de répétitions : ni tonnage, ni donnée manquante")

        let candidates = PersonalBestUpdater.candidates(for: completed, bodyweightKilograms: 80)
        XCTAssertEqual(candidates.map(\.kind), [.maxDuration])
        XCTAssertEqual(candidates.first?.value, 70)

        let set = try XCTUnwrap(completed.orderedSets.last)
        XCTAssertTrue(CompletedSetPresentation.performance(for: set).contains("1 min 10 s"))
    }

    func testRunWithTimeAndDistanceComparesTimesAtEqualDistance() throws {
        let state = makeFreeState()
        state.addExercise(exerciseId: "run", displayName: "Course")
        state.setMeasure(.durationAndDistance)
        state.logMeasuredSet(MeasuredSetResult(durationSeconds: 600, distanceMeters: 2_000))
        state.logMeasuredSet(MeasuredSetResult(durationSeconds: 560, distanceMeters: 2_000))
        state.logMeasuredSet(MeasuredSetResult(durationSeconds: 400, distanceMeters: nil))
        XCTAssertEqual(state.loggedSets.count, 2, "Distance manquante : série refusée")

        state.requestEnd()
        let completed = try XCTUnwrap(state.finish())
        let candidates = PersonalBestUpdater.candidates(for: completed)
        let bestTime = try XCTUnwrap(candidates.first { $0.kind == .bestTime })
        XCTAssertEqual(bestTime.value, 560, "Plus bas est meilleur")
        XCTAssertEqual(bestTime.configurationKey, "distance:2000")
        XCTAssertEqual(candidates.first { $0.kind == .maxDistance }?.value, 2_000)
        XCTAssertFalse(candidates.contains { $0.kind == .maxWeight || $0.kind == .maxReps })
    }

    // MARK: - Export CSV

    func testCSVExportAppendsEffortDistanceAndRestColumns() throws {
        let session = CompletedSession(programName: "", sessionName: "Séance libre", effortRating: 8)
        context.insert(session)
        let set = CompletedSet(
            exerciseId: "run", displayName: "Course", orderIndex: 0, setIndex: 0,
            weight: 0, reps: 0, durationSeconds: 600, distanceMeters: 2_000, actualRestSeconds: 90
        )
        set.session = session
        session.sets.append(set)
        try context.save()

        let sessions = try CSVExport.csv(for: .sessions, context: context)
        let sessionLines = sessions.split(whereSeparator: \.isNewline)
        XCTAssertTrue(sessionLines[0].hasSuffix(",notes,effort_seance"))
        XCTAssertTrue(sessionLines[1].hasSuffix(",8"))

        let sets = try CSVExport.csv(for: .sets, context: context)
        let setLines = sets.split(whereSeparator: \.isNewline)
        XCTAssertTrue(setLines[0].hasSuffix(",notes,distance_m,repos_reel_secondes"))
        XCTAssertTrue(setLines[1].hasSuffix(",2000,90"))
    }
}
