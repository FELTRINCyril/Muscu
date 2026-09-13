import XCTest
import SwiftData
import MuscuEngine
@testable import Muscu

@MainActor
final class WorkoutPersistenceTests: XCTestCase {
    func testWorkoutIsPersistedBeforeFirstSet() throws {
        let container = try TestStore.makeContainer()
        let context = container.mainContext
        let prescribed = PrescribedExercise(
            exerciseId: "Bench_Press",
            displayName: "Développé couché",
            orderIndex: 0,
            sets: 3,
            repsLower: 8,
            repsUpper: 12,
            restSeconds: 90
        )
        let session = ProgramSession(name: "Push", orderIndex: 0, exercises: [prescribed])
        context.insert(Program(name: "PPL", sessions: [session]))
        try context.save()

        _ = WorkoutState(
            programSession: session,
            modelContext: context,
            catalogStore: CatalogStore(),
            restTimer: RestTimer()
        )

        let active = try context.fetch(FetchDescriptor<ActiveWorkout>())
        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(active.first?.phaseRaw, RunnerPhase.warmup.rawValue)
        XCTAssertEqual(active.first?.programSessionId, session.id)
    }

    func testWorkoutRuntimeRoundTripRestoresAmrapState() throws {
        let container = try TestStore.makeContainer()
        let context = container.mainContext
        let prescribed = PrescribedExercise(
            exerciseId: "Pushups", displayName: "Pompes", orderIndex: 0,
            formatRaw: SetFormat.amrap.rawValue, amrapSeconds: 60
        )
        let session = ProgramSession(name: "Circuit", orderIndex: 0, exercises: [prescribed])
        context.insert(Program(name: "Maison", sessions: [session]))
        try context.save()
        let state = WorkoutState(
            programSession: session, modelContext: context,
            catalogStore: CatalogStore(), restTimer: RestTimer()
        )
        let endDate = Date.now.addingTimeInterval(30)
        state.updateAmrapRuntime(AmrapRuntimeState(exerciseId: "Pushups", endDate: endDate, isFinished: false, counter: 17))
        let active = try XCTUnwrap(context.fetch(FetchDescriptor<ActiveWorkout>()).first)

        let resumed = try XCTUnwrap(WorkoutState.resume(
            from: active, modelContext: context,
            catalogStore: CatalogStore(), restTimer: RestTimer()
        ))

        XCTAssertEqual(resumed.runtimeState.amrap?.counter, 17)
        let restoredEndDate = try XCTUnwrap(resumed.runtimeState.amrap?.endDate)
        XCTAssertEqual(restoredEndDate.timeIntervalSince1970, endDate.timeIntervalSince1970, accuracy: 0.001)
    }

    func testExpiredIntervalCatchesUpAllMissedSegments() {
        let segments = IntervalPlan(workSeconds: 10, restSeconds: 10, rounds: 2).segments()
        let runtime = IntervalRuntimeState(
            exerciseId: "bike", index: 0,
            segmentEndDate: Date.now.addingTimeInterval(-60),
            isPaused: false, pausedRemaining: 0,
            showingRepsEntry: false, totalReps: 0
        )
        let controller = IntervalController(segments: segments, restoring: runtime)
        var didFinish = false
        controller.onFinished = { didFinish = true }

        controller.start()

        XCTAssertTrue(didFinish)
        XCTAssertEqual(controller.index, segments.count)
        XCTAssertNil(controller.segmentEndDate)
    }
}
