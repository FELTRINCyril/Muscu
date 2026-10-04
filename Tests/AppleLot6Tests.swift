import XCTest
import SwiftData
import MuscuEngine
@testable import Muscu

/// Lot 6 : Live Activity interactive, widget « Dernière séance », liens
/// directs et intents Siri.
@MainActor
final class AppleLot6Tests: XCTestCase {
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

    // MARK: - Fabriques

    private func makeSession(loadKind: LoadKind = .external, sets: Int = 3) throws -> ProgramSession {
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
            loadKindRaw: loadKind.rawValue
        )
        exercise.session = session
        session.exercises.append(exercise)
        context.insert(exercise)
        try context.save()
        return session
    }

    private func addPastSession(daysAgo: Double, weight: Double, reps: Int, count: Int = 3) throws -> CompletedSession {
        let past = CompletedSession(
            date: Date.now.addingTimeInterval(-daysAgo * 86_400),
            programName: "Programme test",
            sessionName: "Séance passée",
            durationSeconds: 3_120
        )
        context.insert(past)
        for index in 0..<count {
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
        return past
    }

    private func makeState(_ session: ProgramSession, skipWarmup: Bool = true) -> WorkoutState {
        let state = WorkoutState(programSession: session, modelContext: context, catalogStore: CatalogStore(), restTimer: restTimer)
        if skipWarmup { state.finishWarmup() }
        return state
    }

    // MARK: - État de la Live Activity

    func testTheActivityStateDescribesTheSetTheLoggerProposes() throws {
        let session = try makeSession()
        _ = try addPastSession(daysAgo: 3, weight: 80, reps: 8)
        let state = makeState(session)

        let activity = state.liveActivityState()
        XCTAssertEqual(activity.exerciseName, "Développé couché")
        XCTAssertEqual(activity.setNumber, 1)
        XCTAssertEqual(activity.totalSets, 3)
        XCTAssertTrue(activity.canQuickLog)
        XCTAssertEqual(activity.plannedSetText, "80 kg × 10")
        XCTAssertEqual(activity.nextStepText, "Série 2/3")
        XCTAssertEqual(activity.slotKey, state.liveActivitySlotKey)
        XCTAssertNil(activity.restEndsAt)

        // Meme valeurs que la saisie de l'application.
        let target = try XCTUnwrap(state.currentTarget)
        XCTAssertEqual(state.prefillWeight(for: target), 80)
        XCTAssertEqual(state.prefillReps(for: target), 10)
    }

    func testAnUnknownLoadOpensTheAppInsteadOfLoggingZero() throws {
        let session = try makeSession()
        let state = makeState(session)

        let activity = state.liveActivityState()
        XCTAssertFalse(activity.canQuickLog)
        XCTAssertNil(state.quickLogProposal())
        XCTAssertEqual(activity.plannedSetText, "10 reps")
    }

    func testTheWarmupIsNeverValidatedFromTheLockScreen() throws {
        let session = try makeSession()
        _ = try addPastSession(daysAgo: 3, weight: 80, reps: 8)
        let state = makeState(session, skipWarmup: false)
        XCTAssertEqual(state.phase, .warmup)
        XCTAssertFalse(state.liveActivityState().canQuickLog)
    }

    func testTheLastSetAnnouncesTheEndOfTheSession() throws {
        let session = try makeSession(sets: 1)
        _ = try addPastSession(daysAgo: 3, weight: 80, reps: 8)
        let state = makeState(session)
        XCTAssertEqual(state.liveActivityState().nextStepText, "Fin de la séance")
    }

    // MARK: - « Valider la série » depuis la Live Activity

    func testValidatingFromTheActivityTakesTheSamePathAsTheButton() throws {
        let session = try makeSession()
        _ = try addPastSession(daysAgo: 3, weight: 80, reps: 8)
        let state = makeState(session)
        let key = state.liveActivitySlotKey

        XCTAssertTrue(state.logProposedSet(slotKey: key))

        let logged = state.loggedSets.filter { $0.role == .working }
        XCTAssertEqual(logged.count, 1)
        XCTAssertEqual(logged.first?.weight, 80)
        XCTAssertEqual(logged.first?.reps, 10)
        XCTAssertEqual(state.currentTarget?.setNumber, 2)
        // Meme persistance que le bouton : la reprise retrouve la position.
        let workout = try XCTUnwrap(state.activeWorkout)
        let position = try JSONDecoder().decode(WorkoutPosition.self, from: try XCTUnwrap(workout.positionData))
        XCTAssertEqual(position.setIndex, 1)
        // Meme repos que le bouton.
        XCTAssertTrue(restTimer.isRunning)
        XCTAssertEqual(state.liveActivityState().restEndsAt, restTimer.endDate)
        XCTAssertNotNil(state.liveActivityState().restStartedAt)
    }

    func testAStaleOrRepeatedTapNeverValidatesAnotherSet() throws {
        let session = try makeSession()
        _ = try addPastSession(daysAgo: 3, weight: 80, reps: 8)
        let state = makeState(session)
        let key = state.liveActivitySlotKey

        XCTAssertTrue(state.logProposedSet(slotKey: key))
        // Second tap sur l'ancienne activite : la serie affichee n'est plus
        // la serie courante, rien n'est valide.
        XCTAssertFalse(state.logProposedSet(slotKey: key))
        XCTAssertFalse(state.logProposedSet(slotKey: "inconnue"))
        XCTAssertEqual(state.loggedSets.filter { $0.role == .working }.count, 1)
    }

    func testNothingIsLoggedOnAClosedSession() throws {
        let session = try makeSession()
        _ = try addPastSession(daysAgo: 3, weight: 80, reps: 8)
        let state = makeState(session)
        let key = state.liveActivitySlotKey
        XCTAssertTrue(state.discard())
        XCTAssertFalse(state.logProposedSet(slotKey: key))
        state.logSet(weight: 80, reps: 10)
        XCTAssertNil(state.activeWorkout)
        XCTAssertTrue(((try? context.fetch(FetchDescriptor<ActiveWorkout>())) ?? []).isEmpty)
    }

    // MARK: - Repos : décompte puis dépassement

    func testRestPhasesMatchTheAppTimer() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        var state = WorkoutActivityState(exerciseName: "Squat", setNumber: 1, totalSets: 3)
        XCTAssertEqual(state.restPhase(at: now), .none)

        state.restEndsAt = now.addingTimeInterval(45)
        XCTAssertEqual(state.restPhase(at: now), .counting(endsAt: now.addingTimeInterval(45)))
        XCTAssertTrue(state.canExtendRest(at: now))

        state.restEndsAt = now.addingTimeInterval(-12)
        XCTAssertEqual(state.restPhase(at: now), .overtime(since: now.addingTimeInterval(-12)))
        XCTAssertFalse(state.canExtendRest(at: now))

        // Meme borne que `RestCountdown` : au-dela d'une heure, plus rien.
        state.restEndsAt = now.addingTimeInterval(-Double(RestCountdown.maximumOvertimeSeconds) - 1)
        XCTAssertEqual(state.restPhase(at: now), .none)
    }

    func testTheActivityIsRedrawnWhenTheRestEnds() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let resting = WorkoutActivityState(exerciseName: "Squat", setNumber: 1, totalSets: 3, restEndsAt: now.addingTimeInterval(60))
        #if !targetEnvironment(macCatalyst)
        XCTAssertEqual(WorkoutActivityController.staleDate(for: resting, now: now), now.addingTimeInterval(60))
        let idle = WorkoutActivityState(exerciseName: "Squat", setNumber: 1, totalSets: 3)
        XCTAssertEqual(WorkoutActivityController.staleDate(for: idle, now: now), now.addingTimeInterval(4 * 3_600))
        #endif
    }

    func testAStateFromAPreviousVersionStillDecodes() throws {
        let json = #"{"exerciseName":"Squat","setNumber":2,"totalSets":4,"completedSets":1}"#
        let state = try JSONDecoder().decode(WorkoutActivityState.self, from: Data(json.utf8))
        XCTAssertEqual(state.exerciseName, "Squat")
        XCTAssertFalse(state.canQuickLog)
        XCTAssertNil(state.plannedSetText)
        XCTAssertEqual(state.slotKey, "")
    }

    // MARK: - Widget « Dernière séance »

    func testTheLastSessionCardShowsWhatTheHistoryShows() throws {
        _ = try addPastSession(daysAgo: 9, weight: 60, reps: 10)
        let last = try addPastSession(daysAgo: 1, weight: 100, reps: 5)
        let best = PersonalBest(
            exerciseId: "bench",
            displayName: "Développé couché",
            kindRaw: PersonalBestKind.maxWeight.rawValue,
            value: 100,
            sourceSessionId: last.id
        )
        context.insert(best)
        try context.save()

        let summary = try XCTUnwrap(WidgetSnapshotService.makeSnapshot(in: context).lastSession)
        XCTAssertEqual(summary.sessionId, last.id)
        XCTAssertEqual(summary.name, "Séance passée")
        XCTAssertEqual(summary.durationSeconds, 3_120)
        XCTAssertEqual(summary.workingSets, 3)
        XCTAssertEqual(summary.tonnageText, "1500 kg")
        XCTAssertFalse(summary.tonnageIsPartial)
        XCTAssertEqual(summary.recordExerciseName, "Développé couché")
        XCTAssertEqual(summary.recordCount, 1)
    }

    func testAnUnmeasurableTonnageIsAbsentNotZero() throws {
        let past = CompletedSession(date: .now, programName: "", sessionName: "Gainage", durationSeconds: 600)
        context.insert(past)
        let set = CompletedSet(
            exerciseId: "plank",
            displayName: "Gainage",
            orderIndex: 0,
            setIndex: 0,
            weight: 0,
            reps: 0,
            loadTypeRaw: ExerciseLoadType.bodyweight.rawValue,
            roleRaw: SetRole.working.rawValue,
            durationSeconds: 60
        )
        set.session = past
        past.sets.append(set)
        context.insert(set)
        try context.save()

        let summary = try XCTUnwrap(WidgetSnapshotService.makeSnapshot(in: context).lastSession)
        XCTAssertNil(summary.tonnageText)
        XCTAssertNil(summary.recordExerciseName)
        XCTAssertEqual(summary.recordCount, 0)
    }

    func testADeletedSessionIsNotTheLastSession() throws {
        let past = try addPastSession(daysAgo: 1, weight: 100, reps: 5)
        past.deletedAt = .now
        try context.save()
        XCTAssertNil(WidgetSnapshotService.makeSnapshot(in: context).lastSession)
    }

    func testAnOlderSnapshotWithoutLastSessionStillDecodes() throws {
        let json = #"{"version":1,"generatedAt":"2026-09-01T10:00:00Z","sessionsThisWeek":2,"workingSetsThisWeek":12,"weeklyStreak":3}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(WidgetSnapshot.self, from: Data(json.utf8))
        XCTAssertNil(snapshot.lastSession)
        XCTAssertEqual(snapshot.sessionsThisWeek, 2)
    }

    // MARK: - Liens directs

    func testDeepLinksRoundTrip() {
        let id = UUID()
        for link in [MuscuDeepLink.resumeWorkout, .startNextSession, .replaySession(id)] {
            XCTAssertEqual(MuscuDeepLink(url: link.url), link)
        }
        XCTAssertEqual(MuscuDeepLink.replaySession(id).url.absoluteString, "muscu://replay?session=\(id.uuidString)")
    }

    func testUnknownLinksAreIgnored() {
        let urls = [
            "https://example.com/workout",
            "muscu://delete-everything",
            "muscu://replay",
            "muscu://replay?session=pas-un-uuid",
            "autre://workout",
        ]
        for url in urls {
            XCTAssertNil(MuscuDeepLink(url: URL(string: url)!), url)
        }
    }

    func testDeepLinksAreHandledByHome() {
        XCTAssertTrue(IntentDestination(.resumeWorkout).isHandledByHome)
        XCTAssertTrue(IntentDestination(.startNextSession).isHandledByHome)
        XCTAssertTrue(IntentDestination(.replaySession(UUID())).isHandledByHome)
        XCTAssertFalse(IntentDestination.home.isHandledByHome)
    }

    // MARK: - Intents : terminer, abandonner

    func testFinishingWithoutASessionIsRefused() {
        XCTAssertEqual(IntentAnswers.endCheck(for: nil), .noSession)
    }

    func testFinishingAnEmptySessionIsRefused() throws {
        let state = makeState(try makeSession())
        XCTAssertEqual(IntentAnswers.endCheck(for: state), .nothingLogged)
    }

    func testFinishingFromSiriTakesTheSamePathAsTheApp() throws {
        let session = try makeSession()
        _ = try addPastSession(daysAgo: 3, weight: 80, reps: 8)
        let state = makeState(session)
        XCTAssertTrue(state.logProposedSet(slotKey: state.liveActivitySlotKey))
        XCTAssertEqual(IntentAnswers.endCheck(for: state), .canFinish(workingSets: 1, remainingSlots: 2))

        let completion = try XCTUnwrap(state.complete(outsideRunner: true))
        XCTAssertTrue(state.isClosed)
        XCTAssertTrue(state.endedOutsideRunner)
        XCTAssertFalse(restTimer.isRunning)
        XCTAssertEqual(completion.session.workingSets.count, 1)
        XCTAssertTrue(((try? context.fetch(FetchDescriptor<ActiveWorkout>())) ?? []).isEmpty)
        // Records types enregistres, comme a la fin dans l'application.
        let bests = (try? context.fetch(FetchDescriptor<PersonalBest>())) ?? []
        XCTAssertTrue(bests.contains { $0.sourceSessionId == completion.session.id })
        // Une seance terminee ne se termine pas deux fois.
        XCTAssertNil(state.complete(outsideRunner: true))
        XCTAssertEqual(IntentAnswers.endCheck(for: state), .noSession)

        let text = IntentAnswers.finishedText(completion.session)
        XCTAssertTrue(text.contains("1 série(s)"), text)
    }

    func testDiscardingFromSiriWritesNothingToTheHistory() throws {
        let session = try makeSession()
        _ = try addPastSession(daysAgo: 3, weight: 80, reps: 8)
        let state = makeState(session)
        XCTAssertTrue(state.logProposedSet(slotKey: state.liveActivitySlotKey))
        let before = ((try? context.fetch(FetchDescriptor<CompletedSession>())) ?? []).count

        XCTAssertTrue(state.discard(outsideRunner: true))
        XCTAssertTrue(state.endedOutsideRunner)
        XCTAssertEqual(((try? context.fetch(FetchDescriptor<CompletedSession>())) ?? []).count, before)
        XCTAssertTrue(((try? context.fetch(FetchDescriptor<ActiveWorkout>())) ?? []).isEmpty)
        XCTAssertFalse(state.discard(outsideRunner: true))
    }

    func testConfirmationsSayWhatWillHappen() {
        let finish = IntentAnswers.finishConfirmationText(sessionTitle: "Push", workingSets: 4, remainingSlots: 5)
        XCTAssertTrue(finish.contains("« Push »"), finish)
        XCTAssertTrue(finish.contains("5 série(s) prévue(s)"), finish)
        let complete = IntentAnswers.finishConfirmationText(sessionTitle: "Push", workingSets: 4, remainingSlots: 0)
        XCTAssertFalse(complete.contains("prévue"), complete)
        let discard = IntentAnswers.discardConfirmationText(sessionTitle: "Push", loggedSets: 3)
        XCTAssertTrue(discard.contains("supprimées"), discard)
    }

    // MARK: - Intents : 1RM et records

    func testOneRepMaxAnswerSeparatesEstimateAndReference() throws {
        let achieved = Date(timeIntervalSince1970: 1_790_000_000)
        context.insert(PersonalBest(
            exerciseId: "bench",
            displayName: "Développé couché",
            kindRaw: PersonalBestKind.estimatedOneRepMax.rawValue,
            value: 102.5,
            achievedAt: achieved
        ))
        context.insert(ExerciseRecord(exerciseId: "bench", displayName: "Développé couché", oneRepMax: 100, updatedAt: achieved))
        try context.save()

        let answer = IntentAnswers.oneRepMax(exerciseId: "bench", in: context)
        XCTAssertEqual(answer.estimated?.value, 102.5)
        XCTAssertEqual(answer.reference?.value, 100)

        let text = IntentAnswers.oneRepMaxText(answer, exerciseName: "Développé couché", unit: .kilograms)
        XCTAssertTrue(text.contains("1RM estimé"), text)
        XCTAssertTrue(text.contains("102,5 kg"), text)
        XCTAssertTrue(text.contains("1RM de référence"), text)
        XCTAssertTrue(text.contains("100 kg"), text)
    }

    func testOneRepMaxAnswerAdmitsWhenNothingIsKnown() {
        let answer = IntentAnswers.oneRepMax(exerciseId: "squat", in: context)
        XCTAssertTrue(answer.isEmpty)
        let text = IntentAnswers.oneRepMaxText(answer, exerciseName: "Squat", unit: .kilograms)
        XCTAssertTrue(text.hasPrefix("Aucun 1RM connu"), text)
    }

    func testRecentRecordsAreListedNewestFirst() throws {
        let now = Date.now
        context.insert(PersonalBest(exerciseId: "bench", displayName: "Développé couché", kindRaw: PersonalBestKind.maxWeight.rawValue, value: 100, achievedAt: now.addingTimeInterval(-86_400 * 5)))
        context.insert(PersonalBest(exerciseId: "squat", displayName: "Squat", kindRaw: PersonalBestKind.maxReps.rawValue, value: 12, achievedAt: now.addingTimeInterval(-86_400)))
        let deleted = PersonalBest(exerciseId: "dl", displayName: "Soulevé de terre", value: 180, achievedAt: now)
        deleted.deletedAt = now
        context.insert(deleted)
        try context.save()

        let records = IntentAnswers.recentRecords(in: context, now: now)
        XCTAssertEqual(records.map(\.exerciseName), ["Squat", "Développé couché"])
        XCTAssertEqual(records.first?.valueText, "12 reps")
        XCTAssertTrue(IntentAnswers.recentRecordsText(records).hasPrefix("Records récents"))
        XCTAssertTrue(IntentAnswers.recentRecordsText([]).hasPrefix("Aucun record"))
    }
}
