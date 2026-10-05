import XCTest
import SwiftData
import MuscuEngine
@testable import Muscu

/// Fin du repos sans « Repos dépassé » ni latence, −15 s / +15 s, et
/// emplacement réel de la base pour la copie de secours.
@MainActor
final class RestEndTests: XCTestCase {
    private var timer: RestTimer!
    /// Retenu jusqu'au `tearDown` : le chrono y est arrete AVANT que la base
    /// ne disparaisse (son `onStateChange` ecrit dans la seance).
    private var container: ModelContainer?

    override func setUp() async throws {
        timer = RestTimer()
    }

    override func tearDown() async throws {
        timer.skip()
        timer = nil
        container = nil
    }

    // MARK: - −15 s / +15 s

    func testStepsMoveTheEndBothWays() throws {
        timer.start(seconds: 60)
        let end = try XCTUnwrap(timer.endDate)

        timer.adjust(by: 15)
        XCTAssertEqual(try XCTUnwrap(timer.endDate).timeIntervalSince(end), 15, accuracy: 1)
        XCTAssertEqual(timer.totalSeconds, 75)

        timer.adjust(by: -15)
        timer.adjust(by: -15)
        XCTAssertEqual(try XCTUnwrap(timer.endDate).timeIntervalSince(end), -15, accuracy: 1)
        XCTAssertEqual(timer.totalSeconds, 45)
    }

    func testOnlyTheFifteenSecondStepIsAccepted() throws {
        timer.start(seconds: 60)
        let end = try XCTUnwrap(timer.endDate)
        timer.adjust(by: 30)
        timer.adjust(by: -60)
        XCTAssertEqual(timer.endDate, end)
    }

    func testMinusFifteenNearTheEndFinishesTheRest() {
        var finished = 0
        var lastEnd: Date? = .distantPast
        timer.onFinished = { finished += 1 }
        timer.onStateChange = { end, _ in lastEnd = end }
        timer.start(seconds: 10)

        timer.adjust(by: -15)
        XCTAssertFalse(timer.isRunning)
        XCTAssertNil(timer.endDate)
        XCTAssertEqual(timer.remaining, 0)
        XCTAssertEqual(finished, 1)
        XCTAssertNil(lastEnd)

        // Plus de repos : rien a ajuster.
        timer.adjust(by: 15)
        XCTAssertFalse(timer.isRunning)
    }

    // MARK: - Fin du repos

    /// A la fin prevue, le repos est termine tout de suite : plus de fin,
    /// plus de « dépassement », et la fin est signalee (Live Activity et
    /// montre mises a jour par `onStateChange`).
    func testTheRestEndsCleanlyAtItsEnd() async throws {
        let ended = expectation(description: "fin du repos")
        var states: [Date?] = []
        timer.onStateChange = { end, _ in states.append(end) }
        timer.onFinished = { ended.fulfill() }
        timer.start(seconds: 1)
        XCTAssertTrue(timer.isRunning)

        await fulfillment(of: [ended], timeout: 3)
        XCTAssertFalse(timer.isRunning)
        XCTAssertNil(timer.endDate)
        XCTAssertEqual(timer.totalSeconds, 0)
        XCTAssertEqual(states.count, 2)
        XCTAssertNotNil(states.first ?? nil)
        XCTAssertNil(states.last ?? Date())
    }

    func testARestThatEndedWhileTheAppWasClosedIsNotResumed() {
        timer.restore(endDate: Date.now.addingTimeInterval(-20), totalSeconds: 90)
        XCTAssertFalse(timer.isRunning)
        XCTAssertNil(timer.endDate)

        timer.restore(endDate: Date.now.addingTimeInterval(40), totalSeconds: 90)
        XCTAssertTrue(timer.isRunning)
        XCTAssertEqual(timer.remaining, 40, accuracy: 1)
    }

    func testStoppingWithoutARestWritesNothing() {
        var changes = 0
        timer.onStateChange = { _, _ in changes += 1 }
        timer.stopIfRunning()
        XCTAssertEqual(changes, 0)
        timer.start(seconds: 30)
        timer.stopIfRunning()
        XCTAssertEqual(changes, 2)
        XCTAssertFalse(timer.isRunning)
    }

    /// Le repos reellement pris reste enregistre avec la serie suivante,
    /// sans aucun etat de depassement.
    func testTheActualRestIsStillRecorded() throws {
        let container = try TestStore.makeContainer()
        self.container = container
        let context = container.mainContext
        let session = ProgramSession(name: "Séance", orderIndex: 0)
        let program = Program(name: "Programme", isActive: true, sessions: [session])
        session.program = program
        context.insert(program)
        let exercise = PrescribedExercise(
            exerciseId: "squat",
            displayName: "Squat",
            orderIndex: 0,
            formatRaw: SetFormat.classic.rawValue,
            sets: 2,
            repsLower: 5,
            repsUpper: 5,
            restSeconds: 90,
            loadKindRaw: LoadKind.external.rawValue
        )
        exercise.session = session
        session.exercises.append(exercise)
        context.insert(exercise)
        try context.save()

        let state = WorkoutState(programSession: session, modelContext: context, catalogStore: CatalogStore(), restTimer: timer)
        state.finishWarmup()
        state.logSet(weight: 100, reps: 5)
        XCTAssertTrue(timer.isRunning)
        state.logSet(weight: 100, reps: 5)
        XCTAssertFalse(timer.isRunning)
        let second = try XCTUnwrap(state.loggedSets.last)
        XCTAssertNotNil(second.actualRestSeconds)
    }

    // MARK: - Copie de secours : la vraie base

    func testTheRecoveryCopyTargetsTheStoreOfTheModelContainer() throws {
        // Meme configuration par defaut que `MuscuApp` : la base reellement
        // ouverte par l'application.
        let schema = Schema(versionedSchema: MuscuCurrentSchema.self)
        let container = try ModelContainer(for: schema, migrationPlan: MuscuMigrationPlan.self)
        let opened = try XCTUnwrap(container.configurations.first?.url)
        XCTAssertEqual(StoreRecovery.storeURL.standardizedFileURL, opened.standardizedFileURL)

        // Avec le groupe d'applications, la base vit dans son conteneur, pas
        // dans l'Application Support prive de l'application.
        if let group = AppGroup.containerURL {
            XCTAssertTrue(
                StoreRecovery.storeURL.standardizedFileURL.path.hasPrefix(group.standardizedFileURL.path),
                "\(StoreRecovery.storeURL.path) hors de \(group.path)"
            )
        }
        XCTAssertEqual(StoreRecovery.storeURL.lastPathComponent, "default.store")
        XCTAssertTrue(StoreRecovery.storeExists)
    }
}
