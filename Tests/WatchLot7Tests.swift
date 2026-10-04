import XCTest
import SwiftData
import MuscuEngine
@testable import Muscu

/// Lot 7 : séance en miroir sur la montre, commandes, repos au poignet,
/// séance Santé tenue par la montre.
@MainActor
final class WatchLot7Tests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private var restTimer: RestTimer!

    override func setUp() async throws {
        container = try TestStore.makeContainer()
        restTimer = RestTimer()
        HealthSettings.reset()
        LiveWorkoutActions.install(container: container)
    }

    override func tearDown() async throws {
        restTimer.skip()
        restTimer = nil
        HealthSettings.reset()
        container = nil
    }

    // MARK: - Fabriques

    private func makeSession(sets: Int = 3) throws -> ProgramSession {
        let session = ProgramSession(name: "Séance test", orderIndex: 0)
        let program = Program(name: "Programme test", isActive: true, sessions: [session])
        session.program = program
        context.insert(program)
        let exercise = PrescribedExercise(
            exerciseId: "bench",
            displayName: "Développé couché",
            orderIndex: 0,
            formatRaw: SetFormat.classic.rawValue,
            sets: sets,
            repsLower: 8,
            repsUpper: 10,
            restSeconds: 90,
            loadKindRaw: LoadKind.external.rawValue
        )
        exercise.session = session
        session.exercises.append(exercise)
        context.insert(exercise)
        try context.save()
        return session
    }

    private func addPastSession(weight: Double, reps: Int) throws {
        let past = CompletedSession(
            date: Date.now.addingTimeInterval(-3 * 86_400),
            programName: "Programme test",
            sessionName: "Séance passée",
            durationSeconds: 3_120
        )
        context.insert(past)
        for index in 0..<3 {
            let set = CompletedSet(
                exerciseId: "bench",
                displayName: "Développé couché",
                orderIndex: 0,
                setIndex: index,
                weight: weight,
                reps: reps,
                loadTypeRaw: ExerciseLoadType.external.rawValue,
                roleRaw: SetRole.working.rawValue,
                sequenceIndex: index
            )
            set.session = past
            past.sets.append(set)
            context.insert(set)
        }
        try context.save()
    }

    private func makeState(_ session: ProgramSession, skipWarmup: Bool = true) -> WorkoutState {
        let state = WorkoutState(programSession: session, modelContext: context, catalogStore: CatalogStore(), restTimer: restTimer)
        if skipWarmup { state.finishWarmup() }
        return state
    }

    private func envelope(_ command: WatchCommand, workoutId: UUID? = nil) -> WatchCommandEnvelope {
        WatchCommandEnvelope(workoutId: workoutId, command: command)
    }

    // MARK: - État poussé à la montre

    func testTheMirrorDescribesTheSetTheAppProposes() throws {
        let session = try makeSession()
        try addPastSession(weight: 80, reps: 8)
        let state = makeState(session)

        let mirror = WatchMirrorPublisher.state(for: state)
        XCTAssertEqual(mirror.phase, .running)
        XCTAssertEqual(mirror.activeWorkoutId, state.activeWorkout?.id)
        XCTAssertEqual(mirror.sessionName, "Séance test")
        // Exactement la Live Activity : un seul calcul.
        XCTAssertEqual(mirror.activity?.exerciseName, "Développé couché")
        XCTAssertEqual(mirror.activity?.setNumber, 1)
        XCTAssertEqual(mirror.activity?.totalSets, 3)
        XCTAssertEqual(mirror.activity?.nextStepText, "Série 2/3")
        XCTAssertEqual(mirror.activity?.slotKey, state.liveActivitySlotKey)
        XCTAssertEqual(mirror.plannedWeightKilograms, 80)
        XCTAssertEqual(mirror.plannedReps, 10)
        XCTAssertEqual(mirror.massUnitSymbol, "kg")
        XCTAssertTrue(mirror.canLogFromWatch)
        // Santé désactivée : la montre n'enregistre rien.
        XCTAssertFalse(mirror.healthEnabled)
        XCTAssertEqual(mirror.healthHost, .afterTheFact)
    }

    func testAnUnknownLoadIsNeverProposedAtTheWrist() throws {
        let session = try makeSession()
        let state = makeState(session)
        let mirror = WatchMirrorPublisher.state(for: state)
        XCTAssertNil(mirror.plannedWeightKilograms)
        XCTAssertFalse(mirror.canLogFromWatch)
    }

    func testTheWarmupAndTheEndAreSaidAsSuch() throws {
        let session = try makeSession(sets: 1)
        try addPastSession(weight: 80, reps: 8)
        let state = makeState(session, skipWarmup: false)
        XCTAssertEqual(WatchMirrorPublisher.state(for: state).phase, .warmup)
        XCTAssertFalse(WatchMirrorPublisher.state(for: state).canLogFromWatch)

        state.finishWarmup()
        state.logSet(weight: 80, reps: 10)
        XCTAssertEqual(WatchMirrorPublisher.state(for: state).phase, .awaitingFinish)

        XCTAssertTrue(state.discard())
        XCTAssertEqual(WatchMirrorPublisher.state(for: state).phase, .idle)
    }

    func testSequencesOnlyGoForward() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var sequence = WatchMirrorSequence(last: 0)
        let first = sequence.next(now: now)
        let second = sequence.next(now: now)
        let earlierClock = sequence.next(now: now.addingTimeInterval(-60))
        XCTAssertGreaterThan(second, first)
        XCTAssertGreaterThan(earlierClock, second)
    }

    // MARK: - Commandes : même chemin que les boutons

    func testValidatingFromTheWatchTakesTheSamePathAsTheButton() async throws {
        let session = try makeSession()
        try addPastSession(weight: 80, reps: 8)
        let state = makeState(session)
        let key = state.liveActivitySlotKey
        let command = envelope(.logSet(slotKey: key, weightKilograms: 82.5, reps: 9), workoutId: state.activeWorkout?.id)

        let reply = await WatchCommandHandler.handle(command)
        XCTAssertNil(reply.rejection)
        XCTAssertEqual(reply.commandId, command.id)
        let logged = state.loggedSets.filter { $0.role == .working }
        XCTAssertEqual(logged.count, 1)
        XCTAssertEqual(logged.first?.weight, 82.5)
        XCTAssertEqual(logged.first?.reps, 9)
        // Meme repos que le bouton, et l'etat renvoye le dit.
        XCTAssertTrue(restTimer.isRunning)
        XCTAssertEqual(reply.state.activity?.setNumber, 2)
        XCTAssertEqual(reply.state.activity?.restEndsAt, restTimer.endDate)

        // Double tap / etat en retard : la meme commande ne valide rien.
        let replay = await WatchCommandHandler.handle(command)
        XCTAssertEqual(replay.rejection, .staleSet)
        XCTAssertEqual(state.loggedSets.filter { $0.role == .working }.count, 1)
        XCTAssertEqual(replay.state.activity?.setNumber, 2)
    }

    func testRestCommandsUseTheAppTimer() async throws {
        let session = try makeSession()
        try addPastSession(weight: 80, reps: 8)
        let state = makeState(session)
        XCTAssertTrue(state.logProposedSet(slotKey: state.liveActivitySlotKey))
        let end = try XCTUnwrap(restTimer.endDate)

        let extended = await WatchCommandHandler.handle(envelope(.extendRest(seconds: 30)))
        XCTAssertNil(extended.rejection)
        XCTAssertEqual(try XCTUnwrap(restTimer.endDate).timeIntervalSince(end), 30, accuracy: 1)

        let skipped = await WatchCommandHandler.handle(envelope(.skipRest))
        XCTAssertNil(skipped.rejection)
        XCTAssertFalse(restTimer.isRunning)

        let again = await WatchCommandHandler.handle(envelope(.skipRest))
        XCTAssertEqual(again.rejection, .noRest)
    }

    func testAnUnknownLoadIsRefusedRatherThanLoggedAtZero() async throws {
        let session = try makeSession()
        let state = makeState(session)
        let reply = await WatchCommandHandler.handle(envelope(.logSet(slotKey: state.liveActivitySlotKey, weightKilograms: 0, reps: 10)))
        XCTAssertEqual(reply.rejection, .needsPhone)
        XCTAssertTrue(state.loggedSets.isEmpty)
    }

    func testTheWarmupCanBeSkippedFromTheWatch() async throws {
        let session = try makeSession()
        let state = makeState(session, skipWarmup: false)
        let reply = await WatchCommandHandler.handle(envelope(.finishWarmup))
        XCTAssertNil(reply.rejection)
        XCTAssertEqual(state.phase, .running)
        XCTAssertNotEqual(reply.state.phase, .warmup)
    }

    func testStartingFromTheWatchStartsOnThePhone() async throws {
        _ = try makeSession()
        let reply = await WatchCommandHandler.handle(envelope(.startNext))
        XCTAssertNil(reply.rejection)
        XCTAssertTrue(reply.state.hasWorkout)
        XCTAssertEqual(reply.state.sessionName, "Séance test")
        let pending = try XCTUnwrap(WorkoutState.pendingActiveWorkout(modelContext: context))
        XCTAssertEqual(pending.id, reply.state.activeWorkoutId)

        // Une seule seance active a la fois.
        let second = await WatchCommandHandler.handle(envelope(.startFree))
        XCTAssertEqual(second.rejection, .workoutAlreadyRunning)
        XCTAssertEqual(second.state.activeWorkoutId, reply.state.activeWorkoutId)

        LiveWorkoutActions.currentState()?.discard()
        let idle = await WatchCommandHandler.handle(envelope(.requestState))
        XCTAssertFalse(idle.state.hasWorkout)
    }

    func testStartingWithoutAProgramIsRefused() async {
        let reply = await WatchCommandHandler.handle(envelope(.startNext))
        XCTAssertEqual(reply.rejection, .noNextSession)
        XCTAssertNil(WorkoutState.pendingActiveWorkout(modelContext: context))
    }

    func testTheNextSessionGivesItsRealExerciseNames() throws {
        _ = try makeSession()
        let plan = WatchMirrorPublisher.planSummary(in: context)
        XCTAssertEqual(plan.sessionName, "Séance test")
        XCTAssertEqual(plan.programName, "Programme test")
        XCTAssertEqual(plan.exercises.map(\.name), ["Développé couché"])
        XCTAssertEqual(plan.exercises.first?.setCount, 3)
        XCTAssertEqual(plan.exercises.first?.reps, 10)
        // Pas de charge au programme : inconnue, jamais zero.
        XCTAssertNil(plan.exercises.first?.weightKilograms)
    }

    // MARK: - Politique des commandes (pure)

    private func context(
        workout: UUID? = UUID(),
        phase: WatchMirrorState.Phase = .running,
        slot: String = "slot",
        canQuickLog: Bool = true,
        resting: Bool = false,
        canExtend: Bool = false,
        hasNext: Bool = true
    ) -> WatchCommandContext {
        WatchCommandContext(
            activeWorkoutId: workout,
            phase: phase,
            slotKey: slot,
            canQuickLog: canQuickLog,
            isResting: resting,
            canExtendRest: canExtend,
            hasNextSession: hasNext
        )
    }

    func testThePolicyGuardsEveryCommand() {
        let id = UUID()
        let log = WatchCommand.logSet(slotKey: "slot", weightKilograms: 80, reps: 8)
        XCTAssertEqual(WatchCommandPolicy.evaluate(envelope(log, workoutId: id), in: context(workout: id)), .perform)
        XCTAssertEqual(WatchCommandPolicy.evaluate(envelope(log, workoutId: UUID()), in: context(workout: id)), .reject(.noWorkout))
        XCTAssertEqual(WatchCommandPolicy.evaluate(envelope(log), in: context(workout: nil, phase: .idle)), .reject(.noWorkout))
        XCTAssertEqual(WatchCommandPolicy.evaluate(envelope(log), in: context(slot: "autre")), .reject(.staleSet))
        XCTAssertEqual(WatchCommandPolicy.evaluate(envelope(log), in: context(canQuickLog: false)), .reject(.needsPhone))
        XCTAssertEqual(WatchCommandPolicy.evaluate(envelope(log), in: context(phase: .warmup)), .reject(.staleSet))
        XCTAssertEqual(WatchCommandPolicy.evaluate(envelope(log), in: context(phase: .needsPhone)), .reject(.needsPhone))

        for invalid in [
            WatchCommand.logSet(slotKey: "slot", weightKilograms: -1, reps: 8),
            .logSet(slotKey: "slot", weightKilograms: .nan, reps: 8),
            .logSet(slotKey: "slot", weightKilograms: 80, reps: 0),
            .logSet(slotKey: "slot", weightKilograms: 80, reps: 500),
        ] {
            XCTAssertEqual(WatchCommandPolicy.evaluate(envelope(invalid), in: context()), .reject(.invalidValues))
        }

        XCTAssertEqual(WatchCommandPolicy.evaluate(envelope(.skipRest), in: context(resting: true)), .perform)
        XCTAssertEqual(WatchCommandPolicy.evaluate(envelope(.skipRest), in: context()), .reject(.noRest))
        XCTAssertEqual(WatchCommandPolicy.evaluate(envelope(.extendRest(seconds: 30)), in: context(resting: true, canExtend: true)), .perform)
        XCTAssertEqual(WatchCommandPolicy.evaluate(envelope(.extendRest(seconds: 30)), in: context(resting: true)), .reject(.noRest))
        XCTAssertEqual(WatchCommandPolicy.evaluate(envelope(.extendRest(seconds: 90)), in: context(canExtend: true)), .reject(.invalidValues))
        XCTAssertEqual(WatchCommandPolicy.evaluate(envelope(.finishWarmup), in: context(phase: .warmup)), .perform)
        XCTAssertEqual(WatchCommandPolicy.evaluate(envelope(.finishWarmup), in: context()), .reject(.staleSet))

        XCTAssertEqual(WatchCommandPolicy.evaluate(envelope(.startNext), in: context()), .reject(.workoutAlreadyRunning))
        XCTAssertEqual(WatchCommandPolicy.evaluate(envelope(.startNext), in: context(workout: nil, phase: .idle, hasNext: false)), .reject(.noNextSession))
        XCTAssertEqual(WatchCommandPolicy.evaluate(envelope(.startFree), in: context(workout: nil, phase: .idle, hasNext: false)), .perform)
        XCTAssertEqual(WatchCommandPolicy.evaluate(envelope(.requestState), in: context(workout: nil, phase: .idle)), .perform)

        var future = envelope(.requestState)
        future.version = WatchCommandEnvelope.currentVersion + 1
        XCTAssertEqual(WatchCommandPolicy.evaluate(future, in: context()), .reject(.unsupported))
    }

    // MARK: - Machine d'état de la montre (pure)

    private func mirror(sequence: Int, workout: UUID? = UUID(), phase: WatchMirrorState.Phase = .running) -> WatchMirrorState {
        WatchMirrorState(sequence: sequence, phase: phase, activeWorkoutId: workout)
    }

    func testALateStateNeverReplacesANewerOne() {
        var machine = WatchMirrorMachine()
        let id = UUID()
        XCTAssertTrue(machine.receive(mirror(sequence: 10, workout: id)))
        XCTAssertFalse(machine.receive(mirror(sequence: 9, workout: id, phase: .awaitingFinish)))
        XCTAssertEqual(machine.state?.phase, .running)
        XCTAssertTrue(machine.receive(mirror(sequence: 11, workout: nil, phase: .idle)))
        XCTAssertFalse(machine.state?.hasWorkout ?? true)

        var future = mirror(sequence: 12)
        future.version = WatchMirrorState.currentVersion + 1
        XCTAssertFalse(machine.receive(future))
    }

    func testOneCommandAtATimeAndNoneWhenUnreachable() {
        var machine = WatchMirrorMachine(state: mirror(sequence: 1))
        XCTAssertEqual(machine.prepare(.skipRest, reachable: false), .refused(.unreachable))
        XCTAssertEqual(machine.notice, .unreachable)
        XCTAssertFalse(machine.isBusy)

        let first = UUID()
        guard case .send(let envelope) = machine.prepare(.skipRest, reachable: true, id: first) else {
            return XCTFail("La commande devait partir")
        }
        XCTAssertEqual(envelope.workoutId, machine.state?.activeWorkoutId)
        XCTAssertNil(machine.notice)
        // Second tap pendant l'envoi : rien ne part.
        XCTAssertEqual(machine.prepare(.skipRest, reachable: true), .busy)

        // Reponse a une autre commande : la commande en cours reste en route.
        machine.receive(WatchCommandReply(commandId: UUID(), rejection: nil, state: mirror(sequence: 2, workout: machine.state?.activeWorkoutId)))
        XCTAssertTrue(machine.isBusy)
        XCTAssertEqual(machine.state?.sequence, 2)

        machine.receive(WatchCommandReply(commandId: first, rejection: .staleSet, state: mirror(sequence: 3, workout: machine.state?.activeWorkoutId)))
        XCTAssertFalse(machine.isBusy)
        XCTAssertEqual(machine.notice, .staleSet)
        XCTAssertEqual(machine.state?.sequence, 3)

        let lost = UUID()
        _ = machine.prepare(.skipRest, reachable: true, id: lost)
        machine.sendFailed(commandId: lost)
        XCTAssertFalse(machine.isBusy)
        XCTAssertEqual(machine.notice, .unreachable)
    }

    func testANewWorkoutClearsAnOldRefusal() {
        var machine = WatchMirrorMachine(state: mirror(sequence: 1))
        _ = machine.prepare(.skipRest, reachable: false)
        XCTAssertNotNil(machine.notice)
        machine.receive(mirror(sequence: 2, workout: UUID()))
        XCTAssertNil(machine.notice)
    }

    // MARK: - Digital Crown

    func testTheProposalIsSentExactlyWhenUntouched() {
        let state = WatchMirrorState(
            sequence: 1,
            phase: .running,
            activeWorkoutId: UUID(),
            plannedWeightKilograms: 82.5,
            plannedReps: 8,
            massUnitSymbol: "lb"
        )
        var adjustment = WatchSetAdjustment(proposal: state)
        XCTAssertEqual(adjustment.unit, .pounds)
        // Aucun arrondi parasite d'un aller-retour kg -> lb -> kg.
        XCTAssertEqual(adjustment.weightKilograms, 82.5)
        XCTAssertEqual(adjustment.displayWeight, 82.5 * WatchMassUnit.poundsPerKilogram, accuracy: 0.001)

        adjustment.setDisplayWeight(185)
        XCTAssertEqual(adjustment.weightKilograms, 185 / WatchMassUnit.poundsPerKilogram, accuracy: 0.0001)

        adjustment.setDisplayWeight(-20)
        XCTAssertEqual(adjustment.displayWeight, 0)
        adjustment.setDisplayWeight(10_000)
        XCTAssertEqual(adjustment.displayWeight, WatchMassUnit.pounds.maximum)
        adjustment.setReps(0)
        XCTAssertEqual(adjustment.reps, 1)
        adjustment.setReps(999)
        XCTAssertEqual(adjustment.reps, WatchCommandPolicy.repsRange.upperBound)
    }

    // MARK: - Haptique du repos

    func testTheLastThreeSecondsAndTheEndVibrateOnce() {
        let end = Date(timeIntervalSince1970: 1_800_000_000)
        var tracker = RestHapticTracker()
        XCTAssertEqual(tracker.cues(at: end.addingTimeInterval(-10), restEndsAt: end), [])
        XCTAssertEqual(tracker.cues(at: end.addingTimeInterval(-2.9), restEndsAt: end), [.countdown(secondsRemaining: 3)])
        XCTAssertEqual(tracker.cues(at: end.addingTimeInterval(-2.5), restEndsAt: end), [])
        XCTAssertEqual(tracker.cues(at: end.addingTimeInterval(-1.5), restEndsAt: end), [.countdown(secondsRemaining: 2)])
        XCTAssertEqual(tracker.cues(at: end.addingTimeInterval(-0.4), restEndsAt: end), [.countdown(secondsRemaining: 1)])
        XCTAssertEqual(tracker.cues(at: end, restEndsAt: end), [.finished])
        XCTAssertEqual(tracker.cues(at: end.addingTimeInterval(1), restEndsAt: end), [])
    }

    func testNoBurstAfterTheWristWasDown() {
        let end = Date(timeIntervalSince1970: 1_800_000_000)
        var tracker = RestHapticTracker()
        _ = tracker.cues(at: end.addingTimeInterval(-30), restEndsAt: end)
        // Suspendue de -30 s a -1 s : un seul signal, le courant.
        XCTAssertEqual(tracker.cues(at: end.addingTimeInterval(-0.5), restEndsAt: end), [.countdown(secondsRemaining: 1)])

        var late = RestHapticTracker()
        _ = late.cues(at: end.addingTimeInterval(-30), restEndsAt: end)
        // Fin passee depuis trop longtemps : pas de vibration a contretemps.
        XCTAssertEqual(late.cues(at: end.addingTimeInterval(60), restEndsAt: end), [])
    }

    func testThirtyMoreSecondsRestartTheCountdown() {
        let end = Date(timeIntervalSince1970: 1_800_000_000)
        var tracker = RestHapticTracker()
        XCTAssertEqual(tracker.cues(at: end.addingTimeInterval(-2.5), restEndsAt: end), [.countdown(secondsRemaining: 3)])
        let extended = end.addingTimeInterval(30)
        XCTAssertEqual(tracker.cues(at: end.addingTimeInterval(-2), restEndsAt: extended), [])
        XCTAssertEqual(tracker.cues(at: extended.addingTimeInterval(-2.5), restEndsAt: extended), [.countdown(secondsRemaining: 3)])
        XCTAssertEqual(tracker.cues(at: extended, restEndsAt: nil), [])
    }

    // MARK: - Encodage

    func testMessagesRoundTrip() throws {
        let activity = WorkoutActivityState(exerciseName: "Squat", setNumber: 2, totalSets: 4, restEndsAt: Date(timeIntervalSince1970: 1_800_000_000), slotKey: "k")
        let state = WatchMirrorState(sequence: 42, phase: .running, activeWorkoutId: UUID(), sessionName: "Jambes", activity: activity, plannedWeightKilograms: 100, plannedReps: 5, healthHost: .watch, healthEnabled: true)
        XCTAssertEqual(WatchMessageCodec.decode(WatchMirrorState.self, from: WatchMessageCodec.encode(state)), state)

        let command = WatchCommandEnvelope(workoutId: UUID(), command: .logSet(slotKey: "k", weightKilograms: 100, reps: 5))
        XCTAssertEqual(WatchMessageCodec.decode(WatchCommandEnvelope.self, from: WatchMessageCodec.encode(command)), command)

        let reply = WatchCommandReply(commandId: command.id, rejection: .staleSet, state: state)
        XCTAssertEqual(WatchMessageCodec.decode(WatchCommandReply.self, from: WatchMessageCodec.encode(reply)), reply)

        let health = WatchHealthCommand.finish(activeWorkoutId: UUID(), completedSessionId: UUID(), endDate: Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(WatchMessageCodec.decode(WatchHealthCommand.self, from: WatchMessageCodec.encode(health)), health)

        let message = try XCTUnwrap(WatchMessageCodec.message(state, key: WatchTransferKey.mirror))
        XCTAssertNotNil(message[WatchTransferKey.mirror] as? Data)
        XCTAssertNil(WatchMessageCodec.decode(WatchMirrorState.self, from: Data("illisible".utf8)))
    }

    func testAnOlderWatchSessionStillDecodes() throws {
        // Seance envoyee par une montre anterieure au lot 7 : ni Sante, ni
        // dates ISO 8601.
        let json = #"{"version":1,"id":"\#(UUID().uuidString)","sessionName":"Haut","startedAt":800000000,"durationSeconds":1800,"sets":[]}"#
        let payload = try JSONDecoder().decode(WatchSessionPayload.self, from: Data(json.utf8))
        XCTAssertNil(payload.healthWorkoutIdentifier)
        XCTAssertNil(payload.cardio)
    }

    // MARK: - Complication

    func testTheComplicationShowsTheRunningSetOrTheNextSession() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let idle = WatchComplicationState.make(mirror: nil, nextSessionName: "Jambes", now: now)
        XCTAssertFalse(idle.isWorkoutRunning)
        XCTAssertEqual(idle.title, "Jambes")
        XCTAssertNil(WatchComplicationState.make(mirror: nil, nextSessionName: nil, now: now).title)

        let activity = WorkoutActivityState(
            exerciseName: "Squat",
            setNumber: 2,
            totalSets: 4,
            restEndsAt: now.addingTimeInterval(40),
            completedSets: 5
        )
        let running = WatchMirrorState(sequence: 1, phase: .running, activeWorkoutId: UUID(), sessionName: "Jambes", activity: activity)
        let state = WatchComplicationState.make(mirror: running, nextSessionName: "Autre", now: now)
        XCTAssertTrue(state.isWorkoutRunning)
        XCTAssertEqual(state.title, "Squat")
        XCTAssertEqual(state.detail, "Série 2/4")
        XCTAssertEqual(state.restEndsAt, now.addingTimeInterval(40))
        XCTAssertEqual(state.completedSets, 5)

        // Un repos termine n'est plus un decompte.
        XCTAssertNil(WatchComplicationState.make(mirror: running, nextSessionName: nil, now: now.addingTimeInterval(60)).restEndsAt)
    }

    // MARK: - Santé à la montre

    func testTheWatchRecordsOnlyTheSessionItWasGiven() {
        let id = UUID()
        var state = WatchMirrorState(sequence: 1, phase: .running, activeWorkoutId: id, healthHost: .watch, healthEnabled: true)
        XCTAssertEqual(WatchHealthPlanner.action(for: state, isRecording: false, recordingWorkoutId: nil, closedWorkoutIds: []), .start(id))
        XCTAssertEqual(WatchHealthPlanner.action(for: state, isRecording: true, recordingWorkoutId: nil, closedWorkoutIds: []), .associate(id))
        XCTAssertEqual(WatchHealthPlanner.action(for: state, isRecording: true, recordingWorkoutId: id, closedWorkoutIds: []), .none)
        XCTAssertEqual(WatchHealthPlanner.action(for: state, isRecording: false, recordingWorkoutId: nil, closedWorkoutIds: [id]), .none)

        state.healthHost = .phone
        XCTAssertEqual(WatchHealthPlanner.action(for: state, isRecording: false, recordingWorkoutId: nil, closedWorkoutIds: []), .none)
        state.healthHost = .watch
        state.healthEnabled = false
        XCTAssertEqual(WatchHealthPlanner.action(for: state, isRecording: false, recordingWorkoutId: nil, closedWorkoutIds: []), .none)
    }

    private func addCompleted() throws -> CompletedSession {
        let session = CompletedSession(
            date: Date.now.addingTimeInterval(-60),
            programName: "Programme test",
            sessionName: "Séance test",
            durationSeconds: 3_000
        )
        context.insert(session)
        try context.save()
        return session
    }

    private func links(for id: UUID) -> [HealthWorkoutLink] {
        ((try? context.fetch(FetchDescriptor<HealthWorkoutLink>())) ?? [])
            .filter { $0.completedSessionId == id && $0.deletedAt == nil }
    }

    func testTheWatchWorkoutIsLinkedOnceWithItsCardio() async throws {
        let session = try addCompleted()
        let store = InMemoryHealthStore(status: .authorized)
        store.insertWorkout(identifier: "watch-1", sessionId: session.id, start: session.date, duration: 3_000)
        let cardio = WatchCardio(averageHeartRate: 128.6, minimumHeartRate: 80, maximumHeartRate: 170, activeEnergyKilocalories: 290.2)

        for _ in 0..<3 {
            await LiveHealthWorkoutController.shared.attachWatchWorkout(
                identifier: "watch-1",
                completedSessionId: session.id,
                cardio: cardio,
                in: context,
                store: store
            )
        }
        XCTAssertEqual(links(for: session.id).count, 1, "Une confirmation rejouée ne crée aucun doublon")
        XCTAssertEqual(links(for: session.id).first?.sourceRaw, "watch")
        XCTAssertEqual(links(for: session.id).first?.healthKitWorkoutIdentifier, "watch-1")
        XCTAssertEqual(store.writtenWorkoutIdentifiers, ["watch-1"], "Rejouer ne retire jamais l'entraînement")
        XCTAssertEqual(session.avgHeartRate, 129)
        XCTAssertEqual(session.maxHeartRate, 170)
        XCTAssertEqual(session.minHeartRate, 80)
        XCTAssertEqual(session.activeEnergyKcal, 290)

        let outcome = await HealthSyncService.synchronize(in: context, store: store)
        XCTAssertEqual(outcome.written, 0, "La séance n'est jamais réécrite après coup")
    }

    func testALateWatchWorkoutReplacesTheAfterTheFactOne() async throws {
        let session = try addCompleted()
        let store = InMemoryHealthStore(status: .authorized)
        HealthSettings.isEnabled = true

        _ = await HealthSyncService.synchronize(in: context, store: store)
        XCTAssertEqual(links(for: session.id).count, 1)

        store.insertWorkout(identifier: "watch-late", sessionId: session.id, start: session.date, duration: 3_000)
        await LiveHealthWorkoutController.shared.attachWatchWorkout(
            identifier: "watch-late",
            completedSessionId: session.id,
            cardio: WatchCardio(),
            in: context,
            store: store
        )
        XCTAssertEqual(links(for: session.id).map(\.healthKitWorkoutIdentifier), ["watch-late"])
        XCTAssertEqual(store.writtenWorkoutIdentifiers, ["watch-late"], "Jamais deux entraînements pour une séance")
    }

    func testAWatchWorkoutForADeletedSessionIsRemoved() async throws {
        let store = InMemoryHealthStore(status: .authorized)
        let ghost = UUID()
        store.insertWorkout(identifier: "watch-ghost", sessionId: ghost, start: .now, duration: 1_800)
        await LiveHealthWorkoutController.shared.attachWatchWorkout(
            identifier: "watch-ghost",
            completedSessionId: ghost,
            cardio: WatchCardio(),
            in: context,
            store: store
        )
        XCTAssertTrue(store.writtenWorkoutIdentifiers.isEmpty)
        XCTAssertTrue(links(for: ghost).isEmpty)
    }
}
