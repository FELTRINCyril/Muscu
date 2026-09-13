import XCTest
import SwiftData
import MuscuEngine
@testable import Muscu

@MainActor
final class ProfileAndHistoryTests: XCTestCase {
    func testProfileIsOptionalAndCreatedOnlyOnce() throws {
        let container = try TestStore.makeContainer()
        let context = container.mainContext

        XCTAssertNil(ProfileStore.currentProfile(in: context), "L’app doit fonctionner sans profil")
        XCTAssertEqual(ProfileStore.massUnit(in: context), .kilograms)

        let first = ProfileStore.ensureProfile(in: context)
        try context.save()
        let second = ProfileStore.ensureProfile(in: context)
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AthleteProfile>()), 1)
    }

    func testLatestBodyweightPrefersMostRecentMeasurement() throws {
        let container = try TestStore.makeContainer()
        let context = container.mainContext

        let profile = ProfileStore.ensureProfile(in: context)
        profile.bodyweightKilograms = 80
        try context.save()
        XCTAssertEqual(ProfileStore.latestBodyweightKilograms(in: context), 80)

        let older = BodyMeasurement(
            kindRaw: BodyMeasurementKind.bodyweight.rawValue,
            measuredAt: Date(timeIntervalSince1970: 1_000),
            value: 82
        )
        let newer = BodyMeasurement(
            kindRaw: BodyMeasurementKind.bodyweight.rawValue,
            measuredAt: Date(timeIntervalSince1970: 2_000),
            value: 78.5
        )
        context.insert(older)
        context.insert(newer)
        try context.save()

        XCTAssertEqual(ProfileStore.latestBodyweightKilograms(in: context), 78.5)
    }

    func testDeletedMeasurementIsIgnored() throws {
        let container = try TestStore.makeContainer()
        let context = container.mainContext

        let measurement = BodyMeasurement(
            kindRaw: BodyMeasurementKind.bodyweight.rawValue,
            value: 90,
            deletedAt: .now
        )
        context.insert(measurement)
        try context.save()

        XCTAssertNil(ProfileStore.latestBodyweightKilograms(in: context))
    }

    /// Critere d'acceptation : une seance terminee ne change jamais quand son
    /// programme source est modifie ou supprime.
    func testCompletedSessionIsImmutableWhenProgramChanges() throws {
        let container = try TestStore.makeContainer()
        let context = container.mainContext

        let exercise = PrescribedExercise(
            exerciseId: "bench",
            displayName: "Développé couché",
            orderIndex: 0,
            sets: 3,
            repsLower: 8,
            repsUpper: 10
        )
        let session = ProgramSession(name: "Push", orderIndex: 0, exercises: [exercise])
        let program = Program(name: "PPL", sessions: [session])
        context.insert(program)

        let loggedSet = CompletedSet(
            exerciseId: "bench",
            displayName: "Développé couché",
            orderIndex: 0,
            setIndex: 0,
            weight: 80,
            reps: 8,
            loadTypeRaw: ExerciseLoadType.external.rawValue
        )
        let completed = CompletedSession(
            programId: program.id,
            programSessionId: session.id,
            programName: program.name,
            sessionName: session.name,
            durationSeconds: 1_800,
            bodyweightKilograms: 78,
            sets: [loggedSet]
        )
        context.insert(completed)
        try context.save()

        program.name = "PPL v2"
        session.name = "Poussée"
        exercise.displayName = "Développé incliné"
        exercise.sets = 5
        try context.save()

        let stored = try XCTUnwrap(context.fetch(FetchDescriptor<CompletedSession>()).first)
        XCTAssertEqual(stored.programName, "PPL")
        XCTAssertEqual(stored.sessionName, "Push")
        XCTAssertEqual(stored.sets.first?.displayName, "Développé couché")
        XCTAssertEqual(stored.bodyweightKilograms, 78)

        // Supprimer le programme ne doit pas emporter l'historique.
        context.delete(program)
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CompletedSession>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CompletedSet>()), 1)
    }

    /// Les quatre types de charge partagent le meme calcul, et une seance
    /// fige le poids de corps necessaire a ce calcul.
    func testSharedMetricsAcrossLoadTypes() throws {
        let external = CompletedSet(
            exerciseId: "bench", displayName: "Développé", orderIndex: 0, setIndex: 0,
            weight: 80, reps: 5, loadTypeRaw: ExerciseLoadType.external.rawValue
        )
        let weighted = CompletedSet(
            exerciseId: "pullup", displayName: "Tractions lestées", orderIndex: 1, setIndex: 0,
            weight: 20, reps: 5, loadTypeRaw: ExerciseLoadType.weighted.rawValue
        )
        let assisted = CompletedSet(
            exerciseId: "pullup-assisted", displayName: "Tractions assistées", orderIndex: 2, setIndex: 0,
            weight: 30, reps: 5, loadTypeRaw: ExerciseLoadType.assisted.rawValue
        )
        let bodyweight = CompletedSet(
            exerciseId: "pushup", displayName: "Pompes", orderIndex: 3, setIndex: 0,
            weight: 0, reps: 20, loadTypeRaw: ExerciseLoadType.bodyweight.rawValue
        )
        let session = CompletedSession(
            programName: "Test",
            sessionName: "Test",
            bodyweightKilograms: 80,
            sets: [external, weighted, assisted, bodyweight]
        )

        let inputs = session.metricsInputs()
        XCTAssertEqual(SetMetrics.effectiveLoad(inputs[0]), 80)
        XCTAssertEqual(SetMetrics.effectiveLoad(inputs[1]), 100)
        XCTAssertEqual(SetMetrics.effectiveLoad(inputs[2]), 50)
        XCTAssertEqual(SetMetrics.effectiveLoad(inputs[3]), 80)

        let expectedTonnage: Double = (80 * 5) + (100 * 5) + (50 * 5) + (80 * 20)
        let total = SetMetrics.totalTonnage(inputs)
        XCTAssertEqual(total.total, expectedTonnage)
        XCTAssertEqual(total.unknownSets, 0)
    }

    /// Sans poids de corps connu, le tonnage ne doit pas inventer un zero :
    /// les series concernees sont comptees comme « donnee manquante ».
    func testUnknownBodyweightIsReportedNotZeroed() throws {
        let bodyweight = CompletedSet(
            exerciseId: "pushup", displayName: "Pompes", orderIndex: 0, setIndex: 0,
            weight: 0, reps: 20, loadTypeRaw: ExerciseLoadType.bodyweight.rawValue
        )
        let session = CompletedSession(programName: "Test", sessionName: "Test", sets: [bodyweight])

        let result = SetMetrics.totalTonnage(session.metricsInputs())
        XCTAssertEqual(result.total, 0)
        XCTAssertEqual(result.unknownSets, 1)
    }
}
