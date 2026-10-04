import XCTest
import SwiftData
import MuscuEngine
@testable import Muscu

@MainActor
final class WidgetSnapshotTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let reference = Date(timeIntervalSince1970: 1_772_000_000)

    override func setUpWithError() throws {
        container = try TestStore.makeContainer()
        WidgetSnapshotStore.clear()
    }

    override func tearDownWithError() throws {
        WidgetSnapshotStore.clear()
        container = nil
    }

    @discardableResult
    private func addSession(daysAgo: Int, workingSets: Int = 3) -> CompletedSession {
        let session = CompletedSession(
            date: reference.addingTimeInterval(-Double(daysAgo) * 86_400),
            programName: "Programme",
            sessionName: "Séance A",
            durationSeconds: 3_600
        )
        context.insert(session)
        for index in 0..<workingSets {
            let set = CompletedSet(
                exerciseId: "bench",
                displayName: "Développé",
                orderIndex: 0,
                setIndex: index,
                weight: 60,
                reps: 10,
                loadTypeRaw: ExerciseLoadType.external.rawValue,
                roleRaw: SetRole.working.rawValue,
                sequenceIndex: index
            )
            set.session = session
            session.sets.append(set)
            context.insert(set)
        }
        try? context.save()
        return session
    }

    // MARK: - Conteneur partagé

    func testTheAppGroupContainerIsReachable() throws {
        XCTAssertNotNil(
            AppGroup.containerURL,
            "Conteneur « \(AppGroup.identifier) » introuvable : l’entitlement de groupe "
            + "d’applications est absent du binaire de test. C’est le cas si la compilation "
            + "a été faite avec CODE_SIGNING_ALLOWED=NO, qui retire les entitlements."
        )
    }

    func testSnapshotSurvivesAWriteAndARead() throws {
        let snapshot = WidgetSnapshot(
            generatedAt: reference,
            nextSessionName: "Séance B",
            nextSessionDate: reference.addingTimeInterval(86_400),
            programName: "Programme",
            sessionsThisWeek: 3,
            workingSetsThisWeek: 42,
            weeklyStreak: 5
        )
        WidgetSnapshotStore.write(snapshot)

        let read = WidgetSnapshotStore.read()
        XCTAssertEqual(read.nextSessionName, "Séance B")
        XCTAssertEqual(read.workingSetsThisWeek, 42)
        XCTAssertEqual(read.weeklyStreak, 5)
    }

    func testAnAbsentSnapshotReadsAsEmptyRatherThanFailing() {
        WidgetSnapshotStore.clear()
        XCTAssertEqual(WidgetSnapshotStore.read(), .empty)
        XCTAssertFalse(WidgetSnapshot.empty.hasContent)
    }

    func testASnapshotFromANewerVersionIsIgnored() throws {
        var future = WidgetSnapshot(nextSessionName: "Séance du futur")
        future.version = WidgetSnapshot.currentVersion + 1
        WidgetSnapshotStore.write(future)

        // Mieux vaut ne rien afficher qu'afficher de travers.
        XCTAssertEqual(WidgetSnapshotStore.read(), .empty)
    }

    func testClearingRemovesEverything() throws {
        WidgetSnapshotStore.write(WidgetSnapshot(nextSessionName: "Séance A"))
        WidgetSnapshotStore.clear()
        XCTAssertNil(WidgetSnapshotStore.read().nextSessionName)
    }

    // MARK: - Contenu

    func testTheSnapshotCountsOnlyTheLastSevenDays() throws {
        addSession(daysAgo: 1)
        addSession(daysAgo: 3)
        addSession(daysAgo: 30)

        let snapshot = WidgetSnapshotService.makeSnapshot(in: context, now: reference)

        XCTAssertEqual(snapshot.sessionsThisWeek, 2)
        XCTAssertEqual(snapshot.workingSetsThisWeek, 6)
    }

    func testAPlannedSessionTakesPrecedenceAndCarriesItsDate() throws {
        let program = Program(name: "Programme", isActive: true)
        context.insert(program)
        let workout = ScheduledWorkout(
            plannedDate: reference.addingTimeInterval(2 * 86_400),
            displayName: "Séance planifiée"
        )
        context.insert(workout)
        try context.save()

        let snapshot = WidgetSnapshotService.makeSnapshot(in: context, now: reference)

        XCTAssertEqual(snapshot.nextSessionName, "Séance planifiée")
        XCTAssertEqual(snapshot.nextSessionDate, workout.plannedDate)
        XCTAssertEqual(snapshot.programName, "Programme")
    }

    func testWithoutPlanningTheRotationGivesANameButNoDate() throws {
        let program = Program(name: "Programme", isActive: true)
        context.insert(program)
        let session = ProgramSession(name: "Séance A", orderIndex: 0)
        session.program = program
        program.sessions.append(session)
        context.insert(session)
        try context.save()

        let snapshot = WidgetSnapshotService.makeSnapshot(in: context, now: reference)

        XCTAssertEqual(snapshot.nextSessionName, "Séance A")
        XCTAssertNil(snapshot.nextSessionDate, "Une séance non planifiée n’a pas de date : on n’en invente pas")
    }

    func testAPastPlannedSessionIsNotProposed() throws {
        context.insert(ScheduledWorkout(
            plannedDate: reference.addingTimeInterval(-86_400),
            displayName: "Séance passée"
        ))
        try context.save()

        let snapshot = WidgetSnapshotService.makeSnapshot(in: context, now: reference)
        XCTAssertNil(snapshot.nextSessionName)
    }

    func testASettledPlannedSessionIsNotProposed() throws {
        let workout = ScheduledWorkout(
            plannedDate: reference.addingTimeInterval(86_400),
            displayName: "Séance faite"
        )
        workout.state = .completed
        context.insert(workout)
        try context.save()

        let snapshot = WidgetSnapshotService.makeSnapshot(in: context, now: reference)
        XCTAssertNil(snapshot.nextSessionName)
    }

    func testAnEmptyStoreProducesAnHonestlyEmptySnapshot() {
        let snapshot = WidgetSnapshotService.makeSnapshot(in: context, now: reference)
        XCTAssertFalse(snapshot.hasContent)
        XCTAssertEqual(snapshot.sessionsThisWeek, 0)
    }

    /// Le widget ne doit rien contenir de plus que ce qu'il affiche.
    func testTheSnapshotCarriesNoSensitiveData() throws {
        let profile = AthleteProfile(firstName: "Cyril", bodyweightKilograms: 78)
        context.insert(profile)
        let session = addSession(daysAgo: 1)
        session.notes = "Douleur à l’épaule droite"
        try context.save()

        var snapshot = WidgetSnapshotService.makeSnapshot(in: context, now: reference)
        // L'identifiant de la derniere seance est aleatoire : il pourrait
        // contenir « 78 » par hasard. Il est verifie, puis neutralise.
        XCTAssertEqual(snapshot.lastSession?.sessionId, session.id)
        snapshot.lastSession?.sessionId = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let text = try XCTUnwrap(String(data: try encoder.encode(snapshot), encoding: .utf8))

        XCTAssertFalse(text.contains("Cyril"))
        XCTAssertFalse(text.contains("78"))
        XCTAssertFalse(text.contains("épaule"))
    }
}

/// État publié sur l'écran verrouillé : rien de plus que ce que le runner
/// affiche déjà.
final class WorkoutActivityStateTests: XCTestCase {
    func testTheStateIsCodableAndStable() throws {
        let state = WorkoutActivityState(
            exerciseName: "Développé couché",
            setNumber: 2,
            totalSets: 4,
            restEndsAt: Date(timeIntervalSince1970: 1_772_000_000),
            completedSets: 5
        )
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(WorkoutActivityState.self, from: data)
        XCTAssertEqual(decoded, state)
    }

    func testNoRestMeansNoEndDate() {
        let state = WorkoutActivityState(exerciseName: "Squat", setNumber: 1, totalSets: 3)
        XCTAssertNil(state.restEndsAt)
    }
}
