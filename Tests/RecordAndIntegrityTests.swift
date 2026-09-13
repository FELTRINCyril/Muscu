import XCTest
import SwiftData
import MuscuEngine
@testable import Muscu

@MainActor
final class RecordAndIntegrityTests: XCTestCase {
    // Une traction assistee ne produit ni record de charge (la charge est
    // reduite) ni record de repetitions non qualifie (8 tractions avec 30 kg
    // d'aide ne valent pas 8 tractions strictes). Une serie de 20 reps sort
    // de la plage 1-12 ou l'estimation de 1RM a un sens.
    func testRecordDetectionIgnoresAssistanceAndHighRepWeightedSets() {
        let assisted = CompletedSet(
            exerciseId: "pullup", displayName: "Tractions", orderIndex: 0, setIndex: 0,
            weight: 30, reps: 8, loadTypeRaw: ExerciseLoadType.assisted.rawValue
        )
        let highReps = CompletedSet(
            exerciseId: "squat", displayName: "Squat", orderIndex: 1, setIndex: 0,
            weight: 40, reps: 20, loadTypeRaw: ExerciseLoadType.external.rawValue
        )
        let session = CompletedSession(programName: "Test", sessionName: "Test", sets: [assisted, highReps])

        XCTAssertTrue(RecordDetection.check(session: session, records: []).isEmpty)
    }

    // Une traction lestee vaut par le total souleve (poids de corps + lest),
    // mais seulement si le poids de corps est connu.
    func testWeightedSetNeedsBodyweightToProduceARecord() {
        let weighted = CompletedSet(
            exerciseId: "pullup", displayName: "Tractions", orderIndex: 0, setIndex: 0,
            weight: 20, reps: 5, loadTypeRaw: ExerciseLoadType.weighted.rawValue
        )
        let withoutBodyweight = CompletedSession(programName: "Test", sessionName: "Test", sets: [weighted])
        XCTAssertTrue(RecordDetection.check(session: withoutBodyweight, records: []).isEmpty)

        let known = CompletedSet(
            exerciseId: "pullup", displayName: "Tractions", orderIndex: 0, setIndex: 0,
            weight: 20, reps: 5, loadTypeRaw: ExerciseLoadType.weighted.rawValue
        )
        let withBodyweight = CompletedSession(
            programName: "Test",
            sessionName: "Test",
            bodyweightKilograms: 80,
            sets: [known]
        )
        let suggestions = RecordDetection.check(session: withBodyweight, records: [])
        XCTAssertEqual(suggestions.count, 1)
        if case .oneRepMax(let new, _) = suggestions[0].kind {
            XCTAssertEqual(new, OneRepMax.epley(weight: 100, reps: 5), accuracy: 0.001)
        } else {
            XCTFail("Un record de charge était attendu")
        }
    }

    // Les series enregistrees avant le typage explicite gardent leur
    // comportement : charge nulle = poids de corps, charge saisie = externe.
    func testLegacyUntypedSetsKeepTheirRecords() {
        let legacyBodyweight = CompletedSet(
            exerciseId: "pushup", displayName: "Pompes", orderIndex: 0, setIndex: 0,
            weight: 0, reps: 30
        )
        let legacyLoaded = CompletedSet(
            exerciseId: "bench", displayName: "Développé couché", orderIndex: 1, setIndex: 0,
            weight: 80, reps: 5
        )
        let session = CompletedSession(
            programName: "Test",
            sessionName: "Test",
            sets: [legacyBodyweight, legacyLoaded]
        )
        let suggestions = RecordDetection.check(session: session, records: [])
        XCTAssertEqual(suggestions.count, 2)
    }

    func testRecordDetectionSeparatesExternalAndBodyweightRecords() {
        let weighted = CompletedSet(
            exerciseId: "bench", displayName: "Développé couché", orderIndex: 0, setIndex: 0,
            weight: 80, reps: 8, loadTypeRaw: ExerciseLoadType.external.rawValue
        )
        let bodyweight = CompletedSet(
            exerciseId: "pushup", displayName: "Pompes", orderIndex: 1, setIndex: 0,
            weight: 0, reps: 25, loadTypeRaw: ExerciseLoadType.bodyweight.rawValue
        )
        let session = CompletedSession(programName: "Test", sessionName: "Test", sets: [weighted, bodyweight])
        let suggestions = RecordDetection.check(session: session, records: [])

        XCTAssertEqual(suggestions.count, 2)
        XCTAssertTrue(suggestions.contains { suggestion in
            if case .oneRepMax = suggestion.kind { return suggestion.exerciseId == "bench" }
            return false
        })
        XCTAssertTrue(suggestions.contains { suggestion in
            if case .maxReps(new: 25, old: nil) = suggestion.kind { return suggestion.exerciseId == "pushup" }
            return false
        })
    }

    func testIntegrityRepairKeepsOneActiveProgramWorkoutAndMergedRecord() throws {
        let container = try TestStore.makeContainer()
        let context = container.mainContext
        let oldProgram = Program(name: "Ancien", isActive: true, createdAt: Date(timeIntervalSince1970: 1))
        let recentProgram = Program(name: "Récent", isActive: true, createdAt: Date(timeIntervalSince1970: 2))
        context.insert(oldProgram)
        context.insert(recentProgram)
        context.insert(ActiveWorkout(startedAt: Date(timeIntervalSince1970: 1), programSessionId: UUID()))
        context.insert(ActiveWorkout(startedAt: Date(timeIntervalSince1970: 2), programSessionId: UUID()))
        context.insert(ExerciseRecord(exerciseId: "bench", displayName: "Bench", oneRepMax: 100, updatedAt: Date(timeIntervalSince1970: 1)))
        context.insert(ExerciseRecord(exerciseId: "bench", displayName: "Bench", maxReps: 12, updatedAt: Date(timeIntervalSince1970: 2)))
        try context.save()

        try DataIntegrityRepair.run(context: context)

        let programs = try context.fetch(FetchDescriptor<Program>())
        XCTAssertEqual(programs.filter(\.isActive).map(\.id), [recentProgram.id])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ActiveWorkout>()), 1)
        let records = try context.fetch(FetchDescriptor<ExerciseRecord>())
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.oneRepMax, 100)
        XCTAssertEqual(records.first?.maxReps, 12)
    }

    func testDoubleProgressionSuggestsNextWeightAfterCompletingRepRange() throws {
        let container = try TestStore.makeContainer()
        let context = container.mainContext
        let exercise = PrescribedExercise(
            exerciseId: "Barbell_Bench_Press_-_Medium_Grip",
            displayName: "Développé couché",
            orderIndex: 0,
            sets: 3,
            repsLower: 8,
            repsUpper: 10,
            restSeconds: 90
        )
        let programSession = ProgramSession(name: "Push", orderIndex: 0, exercises: [exercise])
        context.insert(Program(name: "PPL", sessions: [programSession]))
        let sets = (0..<3).map {
            CompletedSet(
                exerciseId: exercise.exerciseId, displayName: exercise.displayName,
                orderIndex: 0, setIndex: $0, weight: 80, reps: 10,
                loadTypeRaw: ExerciseLoadType.external.rawValue
            )
        }
        context.insert(CompletedSession(programName: "PPL", sessionName: "Push", sets: sets))
        try context.save()

        let state = WorkoutState(
            programSession: programSession,
            modelContext: context,
            catalogStore: CatalogStore(),
            restTimer: RestTimer()
        )

        XCTAssertEqual(state.suggestedWeight(for: try XCTUnwrap(state.currentExercise)), 82.5)
    }
}
