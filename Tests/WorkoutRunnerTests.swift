import XCTest
import SwiftData
import MuscuEngine
@testable import Muscu

/// Tests d'integration du deroule de seance : construction du plan depuis
/// SwiftData, avancement reel, persistance et reprise.
@MainActor
final class WorkoutRunnerTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private var catalogStore: CatalogStore!
    private var restTimer: RestTimer!

    override func setUpWithError() throws {
        container = try TestStore.makeContainer()
        catalogStore = CatalogStore()
        restTimer = RestTimer()
    }

    override func tearDownWithError() throws {
        restTimer = nil
        catalogStore = nil
        container = nil
    }

    // MARK: - Fabriques

    @discardableResult
    private func makeSession(_ build: (ProgramSession) -> Void) throws -> ProgramSession {
        let session = ProgramSession(name: "Séance test", orderIndex: 0)
        let program = Program(name: "Programme test", isActive: true, sessions: [session])
        session.program = program
        context.insert(program)
        build(session)
        try context.save()
        return session
    }

    private func addExercise(
        to session: ProgramSession,
        id: String,
        name: String,
        format: SetFormat = .classic,
        sets: Int = 3,
        rest: Int = 90
    ) -> PrescribedExercise {
        let exercise = PrescribedExercise(
            exerciseId: id,
            displayName: name,
            orderIndex: session.exercises.count,
            formatRaw: format.rawValue,
            sets: sets,
            repsLower: 8,
            repsUpper: 10,
            restSeconds: rest,
            loadKindRaw: LoadKind.external.rawValue
        )
        exercise.session = session
        session.exercises.append(exercise)
        context.insert(exercise)
        return exercise
    }

    private func makeState(_ session: ProgramSession) -> WorkoutState {
        let state = WorkoutState(
            programSession: session,
            modelContext: context,
            catalogStore: catalogStore,
            restTimer: restTimer
        )
        state.finishWarmup()
        return state
    }

    // MARK: - Superset

    func testSupersetAlternatesAndPersistsRoundsInHistory() throws {
        let session = try makeSession { session in
            let first = addExercise(to: session, id: "a", name: "Développé")
            let second = addExercise(to: session, id: "b", name: "Rowing")
            let group = ExerciseGroup(
                kindRaw: ExerciseGroupKind.superset.rawValue,
                orderIndex: 0,
                rounds: 2,
                restBetweenExercisesSeconds: 0,
                restBetweenRoundsSeconds: 60
            )
            group.session = session
            session.groups.append(group)
            context.insert(group)
            first.group = group
            second.group = group
            second.groupOrderIndex = 1
        }

        let state = makeState(session)
        var visited: [String] = []
        for _ in 0..<4 {
            guard let target = state.currentTarget else { break }
            visited.append("\(target.exercise.displayName)-T\(target.round)")
            state.logSet(weight: 50, reps: 8)
        }

        XCTAssertEqual(visited, ["Développé-T1", "Rowing-T1", "Développé-T2", "Rowing-T2"])
        XCTAssertTrue(state.isSessionComplete)

        let logged = state.loggedSets
        XCTAssertEqual(logged.count, 4)
        XCTAssertTrue(logged.allSatisfy { $0.groupId != nil }, "Une série de superset garde son groupe")
        XCTAssertEqual(Set(logged.map(\.roundIndex)), [0, 1])
    }

    /// Le repos de fin de tour se declenche apres le dernier exercice du
    /// tour, jamais entre A1 et A2 quand il est configure a zero.
    func testSupersetRestOnlyBetweenRounds() throws {
        let session = try makeSession { session in
            let first = addExercise(to: session, id: "a", name: "Développé")
            let second = addExercise(to: session, id: "b", name: "Rowing")
            let group = ExerciseGroup(
                kindRaw: ExerciseGroupKind.superset.rawValue,
                orderIndex: 0,
                rounds: 2,
                restBetweenExercisesSeconds: 0,
                restBetweenRoundsSeconds: 60
            )
            group.session = session
            session.groups.append(group)
            context.insert(group)
            first.group = group
            second.group = group
            second.groupOrderIndex = 1
        }

        let state = makeState(session)
        state.logSet(weight: 50, reps: 8)
        XCTAssertFalse(restTimer.isRunning, "Aucun repos entre A1 et A2")
        state.logSet(weight: 50, reps: 8)
        XCTAssertTrue(restTimer.isRunning, "Repos attendu en fin de tour")
        restTimer.skip()
    }

    // MARK: - Reprise

    func testResumeInTheMiddleOfASupersetKeepsExactPosition() throws {
        let session = try makeSession { session in
            let first = addExercise(to: session, id: "a", name: "Développé")
            let second = addExercise(to: session, id: "b", name: "Rowing")
            let group = ExerciseGroup(
                kindRaw: ExerciseGroupKind.superset.rawValue,
                orderIndex: 0,
                rounds: 3,
                restBetweenExercisesSeconds: 0,
                restBetweenRoundsSeconds: 60
            )
            group.session = session
            session.groups.append(group)
            context.insert(group)
            first.group = group
            second.group = group
            second.groupOrderIndex = 1
        }

        let state = makeState(session)
        state.logSet(weight: 50, reps: 8)
        state.logSet(weight: 40, reps: 8)
        restTimer.skip()
        state.logSet(weight: 50, reps: 8)
        let expected = state.currentTarget

        // Simule un kill+resume : on repart de l'ActiveWorkout persistee.
        let stored = try XCTUnwrap(WorkoutState.pendingActiveWorkout(modelContext: context))
        let resumed = try XCTUnwrap(
            WorkoutState.resume(
                from: stored,
                modelContext: context,
                catalogStore: catalogStore,
                restTimer: RestTimer()
            )
        )

        XCTAssertEqual(resumed.currentTarget?.exercise.displayName, expected?.exercise.displayName)
        XCTAssertEqual(resumed.currentTarget?.round, expected?.round)
        XCTAssertEqual(resumed.currentTarget?.memberPosition, expected?.memberPosition)
        XCTAssertEqual(resumed.loggedSets.count, 3)
    }

    /// Une seance commencee avant le deroule unifie n'a ni plan ni position
    /// persistes : elle doit rester reprenable.
    func testResumeFromLegacySnapshotStillWorks() throws {
        let session = try makeSession { session in
            _ = addExercise(to: session, id: "a", name: "Développé", sets: 3)
        }

        let legacy = ActiveWorkout(
            startedAt: .now,
            programSessionId: session.id,
            exerciseIndex: 0,
            setIndex: 1,
            phaseRaw: RunnerPhase.running.rawValue
        )
        context.insert(legacy)
        try context.save()

        let resumed = try XCTUnwrap(
            WorkoutState.resume(
                from: legacy,
                modelContext: context,
                catalogStore: catalogStore,
                restTimer: restTimer
            )
        )
        XCTAssertEqual(resumed.currentTarget?.setNumber, 2, "La série en cours doit être conservée")
        XCTAssertEqual(resumed.currentTarget?.exercise.displayName, "Développé")
    }

    // MARK: - Dropset

    func testDropsetLogsEveryDropWithDecreasingLoads() throws {
        let session = try makeSession { session in
            let exercise = addExercise(to: session, id: "curl", name: "Curl", format: .dropset, sets: 1)
            exercise.dropsetDrops = [20, 20]
            exercise.dropsetUsesPercent = true
            exercise.dropsetRestSeconds = 0
        }

        let state = makeState(session)
        var loads: [Double] = []
        var subSets: [Int] = []
        for _ in 0..<3 {
            guard let target = state.currentTarget else { break }
            subSets.append(target.subSetIndex)
            let weight = target.subSetIndex == 0 ? 40 : state.prefillWeight(for: target)
            loads.append(weight)
            state.logSet(weight: weight, reps: 8)
        }

        XCTAssertEqual(subSets, [0, 1, 2])
        // Chaque palier part de la charge du palier precedent et est arrondi
        // VERS LE BAS au palier de chargement disponible : 40 -> 32 -> 30,
        // puis 30 -> 24 -> 22,5. Jamais une charge impossible a charger.
        XCTAssertEqual(loads, [40, 30, 22.5])
        XCTAssertTrue(state.isSessionComplete)

        let logged = state.loggedSets
        XCTAssertEqual(logged.map(\.subSetIndex), [0, 1, 2])
        XCTAssertTrue(logged.allSatisfy { $0.setIndex == 0 }, "Les paliers appartiennent à la même série")
    }

    // MARK: - Correction

    func testStepBackRemovesTheLastSetAndReturnsToIt() throws {
        let session = try makeSession { session in
            _ = addExercise(to: session, id: "a", name: "Développé", sets: 3, rest: 0)
        }

        let state = makeState(session)
        state.logSet(weight: 60, reps: 8)
        state.logSet(weight: 60, reps: 7)
        XCTAssertEqual(state.loggedSets.count, 2)
        XCTAssertEqual(state.currentTarget?.setNumber, 3)

        XCTAssertTrue(state.canStepBack)
        state.stepBack()

        XCTAssertEqual(state.currentTarget?.setNumber, 2, "On revient sur la série à corriger")
        XCTAssertEqual(state.loggedSets.count, 1, "La série corrigée est retirée, jamais dupliquée")

        state.logSet(weight: 62.5, reps: 8)
        XCTAssertEqual(state.loggedSets.count, 2)
        XCTAssertEqual(state.loggedSets.last?.weight, 62.5)
    }

    func testStepBackIsUnavailableBeforeAnySet() throws {
        let session = try makeSession { session in
            _ = addExercise(to: session, id: "a", name: "Développé", sets: 3)
        }
        let state = makeState(session)
        XCTAssertFalse(state.canStepBack)
    }

    // MARK: - Modification en séance

    func testAddingARoundDoesNotTouchTheSourceProgram() throws {
        let session = try makeSession { session in
            let first = addExercise(to: session, id: "a", name: "Développé")
            let second = addExercise(to: session, id: "b", name: "Rowing")
            let group = ExerciseGroup(
                kindRaw: ExerciseGroupKind.superset.rawValue,
                orderIndex: 0,
                rounds: 2,
                restBetweenRoundsSeconds: 60
            )
            group.session = session
            session.groups.append(group)
            context.insert(group)
            first.group = group
            second.group = group
            second.groupOrderIndex = 1
        }

        let state = makeState(session)
        state.addSet()

        XCTAssertEqual(state.currentTarget?.totalRounds, 3)
        let storedGroup = try XCTUnwrap(session.orderedGroups.first)
        XCTAssertEqual(storedGroup.rounds, 2, "Le programme source ne doit pas être modifié")
    }

    func testReplacingAnExerciseKeepsPlannedExerciseInHistory() throws {
        let session = try makeSession { session in
            _ = addExercise(to: session, id: "a", name: "Développé", sets: 1)
        }

        let state = makeState(session)
        state.replaceExercise(exerciseId: "b", displayName: "Développé incliné")
        state.logSet(weight: 50, reps: 8)

        let logged = try XCTUnwrap(state.loggedSets.first)
        XCTAssertEqual(logged.exerciseId, "b")
        XCTAssertEqual(logged.plannedExerciseId, "a", "L'historique garde prévu ET réalisé")

        let prescription = try XCTUnwrap(session.orderedExercises.first)
        XCTAssertEqual(prescription.exerciseId, "a", "Le programme source ne doit pas être modifié")
    }

    // MARK: - Rôles de série

    /// Une série d'approche s'AJOUTE : elle est enregistrée, mais la série
    /// prescrite reste à faire.
    func testApproachSetDoesNotConsumeAPrescribedSet() throws {
        let session = try makeSession { session in
            _ = addExercise(to: session, id: "a", name: "Développé", sets: 3)
        }
        let state = makeState(session)
        let setNumberBefore = state.currentTarget?.setNumber

        state.logSet(weight: 40, reps: 5, role: .approach)

        XCTAssertEqual(state.currentTarget?.setNumber, setNumberBefore, "La série prévue reste à faire")
        XCTAssertEqual(state.loggedSets.count, 1)
        XCTAssertEqual(state.loggedSets.first?.role, .approach)
        XCTAssertFalse(state.loggedSets.first?.isWarmup ?? true, "Une approche n'est pas un échauffement")
    }

    /// Un back-off compte dans le volume, mais ne consomme pas de série non
    /// plus : ce sont deux questions distinctes.
    func testBackoffSetCountsAsVolumeWithoutAdvancing() throws {
        let session = try makeSession { session in
            _ = addExercise(to: session, id: "a", name: "Développé", sets: 2)
        }
        let state = makeState(session)
        state.logSet(weight: 80, reps: 5)
        let setNumberAfterWorking = state.currentTarget?.setNumber

        state.logSet(weight: 60, reps: 10, role: .backoff)

        XCTAssertEqual(state.currentTarget?.setNumber, setNumberAfterWorking)
        XCTAssertEqual(state.loggedSets.count, 2)
        XCTAssertTrue(SetRole.backoff.countsAsWorkingSet)
        XCTAssertFalse(SetRole.approach.countsAsWorkingSet)
    }

    func testWorkingSetStillAdvances() throws {
        let session = try makeSession { session in
            _ = addExercise(to: session, id: "a", name: "Développé", sets: 3)
        }
        let state = makeState(session)
        let before = try XCTUnwrap(state.currentTarget?.setNumber)

        state.logSet(weight: 80, reps: 8)

        XCTAssertEqual(state.currentTarget?.setNumber, before + 1)
    }

    // MARK: - Estimation partagée

    func testSessionDurationUsesTheSharedEngineCalculation() throws {
        let session = try makeSession { session in
            _ = addExercise(to: session, id: "a", name: "Développé", sets: 4, rest: 120)
        }
        let plan = WorkoutPlanBuilder.plan(for: session)
        XCTAssertEqual(
            SessionDuration.estimatedSeconds(for: plan, includingWarmup: false),
            4 * SessionDuration.workSecondsPerSet + 3 * 120
        )
    }
}

// MARK: - Aperçu et navigation

extension WorkoutRunnerTests {
    func testMovingToAnotherExerciseKeepsLoggedSets() throws {
        let session = try makeSession { session in
            _ = addExercise(to: session, id: "a", name: "Développé", sets: 2, rest: 0)
            _ = addExercise(to: session, id: "b", name: "Squat", sets: 2, rest: 0)
        }

        let state = makeState(session)
        state.logSet(weight: 60, reps: 8)
        XCTAssertEqual(state.loggedSets.count, 1)

        // Saut vers le second exercice, puis retour au premier.
        state.moveTo(position: WorkoutPosition(nodeIndex: 1))
        XCTAssertEqual(state.currentTarget?.exercise.displayName, "Squat")
        XCTAssertEqual(state.loggedSets.count, 1, "Se déplacer n'efface aucune série")

        state.moveTo(position: WorkoutPosition(nodeIndex: 0, setIndex: 1))
        XCTAssertEqual(state.currentTarget?.exercise.displayName, "Développé")
        XCTAssertEqual(state.currentTarget?.setNumber, 2)
    }

    func testMovingToAnImpossiblePositionIsClamped() throws {
        let session = try makeSession { session in
            _ = addExercise(to: session, id: "a", name: "Développé", sets: 2)
        }
        let state = makeState(session)
        state.moveTo(position: WorkoutPosition(nodeIndex: 42, setIndex: 99))
        XCTAssertTrue(state.isSessionComplete)
    }

    /// L'effort, l'echec et le commentaire saisis sur une serie sont
    /// reellement persistes avec elle.
    func testEffortFailureAndNotesArePersistedWithTheSet() throws {
        let session = try makeSession { session in
            _ = addExercise(to: session, id: "a", name: "Développé", sets: 1)
        }
        let state = makeState(session)
        state.logSet(weight: 80, reps: 5, effort: .rir(1), reachedFailure: true, notes: "Barre lourde")

        let logged = try XCTUnwrap(state.loggedSets.first)
        XCTAssertEqual(logged.effort, .rir(1))
        XCTAssertTrue(logged.reachedFailure)
        XCTAssertEqual(logged.notes, "Barre lourde")
    }
}

// MARK: - Correction dans les blocs à sous-séries

extension WorkoutRunnerTests {
    /// Corriger la dernière saisie d'un rest-pause doit revenir sur la
    /// mini-série réellement enregistrée, pas sur une position devinée en
    /// rejouant la machine à états (dont la sortie dépend des résultats).
    func testStepBackInsideARestPauseReturnsToTheLoggedMiniSet() throws {
        let session = try makeSession { session in
            let exercise = addExercise(to: session, id: "curl", name: "Curl", format: .restPause, sets: 1, rest: 0)
            exercise.restPauseMaxMiniSets = 3
            exercise.restPauseMicroRestSeconds = 0
            exercise.restPauseMinimumReps = 3
        }

        let state = makeState(session)
        state.logSet(weight: 20, reps: 12)
        state.logSet(weight: 20, reps: 6)
        XCTAssertEqual(state.currentTarget?.subSetIndex, 2)

        state.stepBack()
        XCTAssertEqual(state.currentTarget?.subSetIndex, 1, "On revient sur la mini-série à corriger")
        XCTAssertEqual(state.loggedSets.count, 1)

        state.logSet(weight: 20, reps: 8)
        XCTAssertEqual(state.loggedSets.map(\.subSetIndex), [0, 1])
    }

    /// Corriger dans un superset doit revenir sur le bon exercice ET le bon
    /// tour.
    func testStepBackInsideASupersetReturnsToTheRightRound() throws {
        let session = try makeSession { session in
            let first = addExercise(to: session, id: "a", name: "Développé", rest: 0)
            let second = addExercise(to: session, id: "b", name: "Rowing", rest: 0)
            let group = ExerciseGroup(
                kindRaw: ExerciseGroupKind.superset.rawValue,
                orderIndex: 0,
                rounds: 3,
                restBetweenExercisesSeconds: 0,
                restBetweenRoundsSeconds: 0
            )
            group.session = session
            session.groups.append(group)
            context.insert(group)
            first.group = group
            second.group = group
            second.groupOrderIndex = 1
        }

        let state = makeState(session)
        state.logSet(weight: 50, reps: 8)
        state.logSet(weight: 40, reps: 8)
        state.logSet(weight: 50, reps: 8)
        XCTAssertEqual(state.currentTarget?.exercise.displayName, "Rowing")
        XCTAssertEqual(state.currentTarget?.round, 2)

        state.stepBack()
        XCTAssertEqual(state.currentTarget?.exercise.displayName, "Développé")
        XCTAssertEqual(state.currentTarget?.round, 2)
        XCTAssertEqual(state.loggedSets.count, 2)
    }
}
