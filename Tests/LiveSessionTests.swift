import XCTest
import SwiftData
import MuscuEngine
@testable import Muscu

/// Seance en direct (lot 2) : valeur precedente par serie, bandeau des
/// dernieres seances et record celebre sans ecriture.
@MainActor
final class LiveSessionTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private var restTimer: RestTimer!

    // Variantes asynchrones : elles s'executent sur l'acteur principal de
    // la classe, sans avertissement d'isolation.
    override func setUp() async throws {
        container = try TestStore.makeContainer()
        restTimer = RestTimer()
    }

    override func tearDown() async throws {
        restTimer.skip()
        restTimer = nil
        container = nil
    }

    private func makeSession() throws -> ProgramSession {
        let session = ProgramSession(name: "Séance test", orderIndex: 0)
        let program = Program(name: "Programme test", isActive: true, sessions: [session])
        session.program = program
        context.insert(program)
        let exercise = PrescribedExercise(
            exerciseId: "bench",
            displayName: "Développé couché",
            orderIndex: 0,
            formatRaw: SetFormat.classic.rawValue,
            sets: 3,
            repsLower: 8,
            repsUpper: 10,
            restSeconds: 0,
            loadKindRaw: LoadKind.external.rawValue
        )
        exercise.session = session
        session.exercises.append(exercise)
        context.insert(exercise)
        try context.save()
        return session
    }

    /// Seance passee : un echauffement puis des series de travail.
    private func addPastSession(daysAgo: Double, programSessionId: UUID?, sets: [(Double, Int)]) throws {
        let past = CompletedSession(
            date: Date.now.addingTimeInterval(-daysAgo * 86_400),
            programSessionId: programSessionId,
            programName: "Programme test",
            sessionName: "Séance test"
        )
        context.insert(past)
        let warmup = CompletedSet(exerciseId: "bench", displayName: "Développé couché", orderIndex: 0, setIndex: 0, weight: 40, reps: 10, isWarmup: true, loadTypeRaw: ExerciseLoadType.external.rawValue, roleRaw: SetRole.warmup.rawValue)
        warmup.session = past
        past.sets.append(warmup)
        for (index, set) in sets.enumerated() {
            let completed = CompletedSet(
                exerciseId: "bench",
                displayName: "Développé couché",
                orderIndex: 0,
                setIndex: index,
                weight: set.0,
                reps: set.1,
                loadTypeRaw: ExerciseLoadType.external.rawValue,
                roleRaw: SetRole.working.rawValue,
                sequenceIndex: index + 1
            )
            completed.session = past
            past.sets.append(completed)
        }
        try context.save()
    }

    private func makeState(_ session: ProgramSession) -> WorkoutState {
        let state = WorkoutState(programSession: session, modelContext: context, catalogStore: CatalogStore(), restTimer: restTimer)
        state.finishWarmup()
        return state
    }

    func testPreviousSetComesFromSameRankOfComparableSession() throws {
        let session = try makeSession()
        try addPastSession(daysAgo: 10, programSessionId: session.id, sets: [(80, 8), (80, 7), (77.5, 6)])
        // Plus recente, mais d'une autre seance : la seance comparable gagne.
        try addPastSession(daysAgo: 2, programSessionId: UUID(), sets: [(60, 12)])
        let state = makeState(session)

        let first = try XCTUnwrap(state.currentTarget)
        XCTAssertEqual(state.previousSet(for: first)?.weightKilograms, 80)
        XCTAssertEqual(state.previousSet(for: first)?.reps, 8)

        state.logSet(weight: 80, reps: 8)
        let second = try XCTUnwrap(state.currentTarget)
        XCTAssertEqual(state.previousSet(for: second)?.reps, 7)
    }

    func testStripListsSessionsOldestFirstGroupedByLoad() throws {
        let session = try makeSession()
        try addPastSession(daysAgo: 21, programSessionId: session.id, sets: [(20, 15), (20, 9)])
        try addPastSession(daysAgo: 1, programSessionId: session.id, sets: [(22.5, 10)])
        let state = makeState(session)
        let exercise = try XCTUnwrap(state.currentExercise)

        let entries = state.previousSessionsStrip(for: exercise)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.first?.runs, [.init(weightKilograms: 20, reps: [15, 9])])
        XCTAssertEqual(entries.first?.age, .weeks(3))
        XCTAssertEqual(entries.last?.age, .yesterday)
    }

    func testLiveRecordCelebratesOnceAndWritesNothing() throws {
        let session = try makeSession()
        try addPastSession(daysAgo: 7, programSessionId: session.id, sets: [(80, 8)])
        context.insert(PersonalBest(
            exerciseId: "bench",
            displayName: "Développé couché",
            kindRaw: PersonalBestKind.estimatedOneRepMax.rawValue,
            value: OneRepMax.epley(weight: 80, reps: 8)
        ))
        try context.save()
        let bestsBefore = try context.fetchCount(FetchDescriptor<PersonalBest>())
        let state = makeState(session)

        state.logSet(weight: 70, reps: 8)
        XCTAssertNil(state.liveRecordCelebration)

        state.logSet(weight: 85, reps: 8)
        let celebration = try XCTUnwrap(state.liveRecordCelebration)
        XCTAssertEqual(celebration.exerciseName, "Développé couché")
        state.dismissLiveRecordCelebration(id: celebration.id)

        // Encore mieux, mais deja celebre pour cet exercice.
        state.logSet(weight: 90, reps: 8)
        XCTAssertNil(state.liveRecordCelebration)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PersonalBest>()), bestsBefore)
    }

    func testPlateInventoryRoundTripsPerUnit() {
        let defaults = UserDefaults.standard
        defer {
            WorkoutSettings.resetPlateInventory(for: .kilograms)
            WorkoutSettings.resetPlateInventory(for: .pounds)
        }
        XCTAssertEqual(WorkoutSettings.plateInventory(for: .kilograms), .standard(for: .kilograms))
        var inventory = PlateInventory.standard(for: .kilograms)
        inventory.barWeight = 15
        WorkoutSettings.storePlateInventory(inventory)
        XCTAssertEqual(WorkoutSettings.plateInventory(for: .kilograms).barWeight, 15)
        XCTAssertEqual(WorkoutSettings.plateInventory(for: .pounds).barWeight, 45)

        defaults.set(Data("pas du json".utf8), forKey: WorkoutSettings.plateInventoryKey(for: .kilograms))
        XCTAssertEqual(WorkoutSettings.plateInventory(for: .kilograms), .standard(for: .kilograms))
    }
}
