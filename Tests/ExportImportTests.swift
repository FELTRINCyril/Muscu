import XCTest
import SwiftData
@testable import Muscu

@MainActor
final class ExportImportTests: XCTestCase {
    func testRoundTripIsCompleteAndIdempotent() throws {
        let source = try TestStore.makeContainer()
        let context = source.mainContext
        let exercise = PrescribedExercise(
            exerciseId: "Bench_Press",
            displayName: "Développé couché",
            orderIndex: 0,
            sets: 3,
            repsLower: 8,
            repsUpper: 12,
            restSeconds: 90
        )
        let session = ProgramSession(name: "Push", orderIndex: 0, warmupEnabled: true, exercises: [exercise])
        let program = Program(name: "PPL", isActive: true, sessions: [session])
        context.insert(program)

        let loggedSet = CompletedSet(
            exerciseId: exercise.exerciseId,
            displayName: exercise.displayName,
            orderIndex: 0,
            setIndex: 0,
            weight: 80,
            reps: 8
        )
        let completed = CompletedSession(
            programId: program.id,
            programSessionId: session.id,
            programName: program.name,
            sessionName: session.name,
            durationSeconds: 1_200,
            sets: [loggedSet]
        )
        context.insert(completed)
        context.insert(ExerciseRecord(exerciseId: exercise.exerciseId, displayName: exercise.displayName, oneRepMax: 100))
        context.insert(CustomExercise(name: "Mon exercice", primaryMuscles: ["chest"], equipment: "bands"))

        let active = ActiveWorkout(programSessionId: session.id, phaseRaw: "running")
        context.insert(active)
        try context.save()

        let data = try ExportImport.exportAll(context: context)
        let destination = try TestStore.makeContainer()
        let destinationContext = destination.mainContext
        let firstImport = try ExportImport.importAll(data: data, context: destinationContext)
        let secondImport = try ExportImport.importAll(data: data, context: destinationContext)

        XCTAssertEqual(firstImport.programsCount, 1)
        XCTAssertEqual(secondImport.programsCount, 0)
        XCTAssertEqual(secondImport.sessionsCount, 0)
        XCTAssertEqual(secondImport.recordsCount, 0)
        XCTAssertEqual(secondImport.customExercisesCount, 0)

        XCTAssertEqual(try destinationContext.fetchCount(FetchDescriptor<Program>()), 1)
        XCTAssertEqual(try destinationContext.fetchCount(FetchDescriptor<CompletedSession>()), 1)
        XCTAssertEqual(try destinationContext.fetchCount(FetchDescriptor<ExerciseRecord>()), 1)
        XCTAssertEqual(try destinationContext.fetchCount(FetchDescriptor<CustomExercise>()), 1)
        XCTAssertEqual(try destinationContext.fetchCount(FetchDescriptor<ActiveWorkout>()), 1)

        let restored = try XCTUnwrap(destinationContext.fetch(FetchDescriptor<CompletedSession>()).first)
        XCTAssertEqual(restored.programId, program.id)
        XCTAssertEqual(restored.programSessionId, session.id)
    }

    func testRejectsInvalidPrescriptionBeforeInsertion() throws {
        let exercise = ExportImport.ExerciseDTO(
            id: UUID(), exerciseId: "Air_Bike", displayName: "Air Bike", orderIndex: 0,
            formatRaw: SetFormat.amrap.rawValue, sets: 0, repsLower: 0, repsUpper: 0,
            restSeconds: 0, percentOneRepMax: nil, percentMaxReps: nil, targetWeight: nil,
            pyramidReps: [], pyramidMinRest: 0, pyramidMaxRest: 0,
            intervalWork: 0, intervalRest: 0, intervalRounds: 0,
            amrapSeconds: -10, notes: ""
        )
        let program = ExportImport.ProgramDTO(
            id: UUID(),
            name: "Invalide",
            notes: "",
            isActive: false,
            createdAt: .now,
            sessions: [ExportImport.SessionDTO(
                id: UUID(), name: "Jour 1", orderIndex: 0, warmupEnabled: false,
                exercises: [exercise], groups: nil
            )]
        )
        let data = try encodedEnvelope(payload: ExportImport.Payload(programs: [program]))
        let container = try TestStore.makeContainer()

        XCTAssertThrowsError(try ExportImport.importAll(data: data, context: container.mainContext))
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Program>()), 0)
    }

    /// Une archive dont le payload a ete modifie apres coup doit etre
    /// refusee : la somme de controle du manifeste ne correspond plus.
    func testRejectsTamperedPayload() throws {
        let container = try TestStore.makeContainer()
        container.mainContext.insert(Program(name: "Original"))
        try container.mainContext.save()
        let data = try ExportImport.exportAll(context: container.mainContext)

        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        let tampered = try XCTUnwrap(text.replacingOccurrences(of: "Original", with: "Modifié").data(using: .utf8))

        let destination = try TestStore.makeContainer()
        XCTAssertThrowsError(try ExportImport.importAll(data: tampered, context: destination.mainContext)) { error in
            XCTAssertEqual(error as? ExportImport.ImportError, .checksumMismatch)
        }
        XCTAssertEqual(try destination.mainContext.fetchCount(FetchDescriptor<Program>()), 0)
    }

    /// Le manifeste doit decrire fidelement l'archive : un compteur fausse
    /// signale une archive tronquee ou bricolee.
    func testRejectsManifestWithWrongCounts() throws {
        let container = try TestStore.makeContainer()
        container.mainContext.insert(Program(name: "Original"))
        try container.mainContext.save()
        let data = try ExportImport.exportAll(context: container.mainContext)

        var json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var manifest = try XCTUnwrap(json["manifest"] as? [String: Any])
        var counts = try XCTUnwrap(manifest["counts"] as? [String: Int])
        counts["programs"] = 99
        manifest["counts"] = counts
        json["manifest"] = manifest
        let patched = try JSONSerialization.data(withJSONObject: json)

        let destination = try TestStore.makeContainer()
        XCTAssertThrowsError(try ExportImport.importAll(data: patched, context: destination.mainContext))
        XCTAssertEqual(try destination.mainContext.fetchCount(FetchDescriptor<Program>()), 0)
    }

    /// Une sauvegarde v1 (sans identifiants de programme sur l'historique,
    /// sans type de charge) reste importable.
    func testImportsLegacyVersionOneExport() throws {
        let data = try fixtureData(named: "export-v1")
        let container = try TestStore.makeContainer()
        let context = container.mainContext

        let preview = try ExportImport.preview(data: data)
        XCTAssertEqual(preview.sourceVersion, 1)
        XCTAssertEqual(preview.programsCount, 1)

        let summary = try ExportImport.importAll(data: data, context: context)
        XCTAssertEqual(summary.programsCount, 1)
        XCTAssertEqual(summary.sessionsCount, 1)
        XCTAssertEqual(summary.recordsCount, 1)

        let restoredSet = try XCTUnwrap(context.fetch(FetchDescriptor<CompletedSet>()).first)
        XCTAssertEqual(restoredSet.loadType, .unknown, "Un type de charge absent ne doit jamais être deviné")
        XCTAssertEqual(restoredSet.role, .working)

        // Un second import de la meme sauvegarde ne cree aucun doublon.
        let again = try ExportImport.importAll(data: data, context: context)
        XCTAssertEqual(again.programsCount, 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Program>()), 1)
    }

    func testImportsLegacyVersionTwoExport() throws {
        let data = try fixtureData(named: "export-v2")
        let container = try TestStore.makeContainer()
        let context = container.mainContext

        let summary = try ExportImport.importAll(data: data, context: context)
        XCTAssertEqual(summary.sourceVersion, 2)
        XCTAssertEqual(summary.customExercisesCount, 1)

        let restoredSet = try XCTUnwrap(context.fetch(FetchDescriptor<CompletedSet>()).first)
        XCTAssertEqual(restoredSet.loadType, .external)
        let restoredSession = try XCTUnwrap(context.fetch(FetchDescriptor<CompletedSession>()).first)
        XCTAssertNotNil(restoredSession.programId)

        let exercise = try XCTUnwrap(context.fetch(FetchDescriptor<PrescribedExercise>()).first)
        XCTAssertEqual(exercise.targetWeight, 72.5)
    }

    /// Les entites v3 (profil, mesures, check-in, records typés, plan)
    /// doivent faire l'aller-retour sans perte et rester idempotentes.
    func testVersionThreeEntitiesRoundTrip() throws {
        let source = try TestStore.makeContainer()
        let context = source.mainContext

        let profile = AthleteProfile(firstName: "Cyril", heightCentimeters: 181, bodyweightKilograms: 78.4)
        profile.massUnit = .pounds
        profile.avoidAreas = ["lower back"]
        profile.defaultProgressionRule = .linearLoad(incrementKilograms: 5, requiredSuccesses: 2)
        context.insert(profile)

        context.insert(BodyMeasurement(kindRaw: BodyMeasurementKind.waist.rawValue, value: 82.5))
        context.insert(ReadinessEntry(energy: 4, sleepQuality: 3, painIntensity: 2, painArea: "épaule"))
        context.insert(PersonalBest(
            exerciseId: "Pullups",
            displayName: "Tractions",
            kindRaw: PersonalBestKind.maxReps.rawValue,
            value: 15
        ))

        let plan = TrainingPlan(name: "Bloc hiver", startDate: .now)
        let block = TrainingBlock(kindRaw: TrainingBlockKind.accumulation.rawValue, orderIndex: 0)
        let week = TrainingWeek(weekNumber: 1)
        let scheduled = ScheduledWorkout(plannedDate: .now, displayName: "Séance A")
        week.scheduledWorkouts = [scheduled]
        scheduled.week = week
        block.weeks = [week]
        week.block = block
        plan.blocks = [block]
        block.plan = plan
        context.insert(plan)
        try context.save()

        let data = try ExportImport.exportAll(context: context)
        let destination = try TestStore.makeContainer()
        let destinationContext = destination.mainContext

        let first = try ExportImport.importAll(data: data, context: destinationContext)
        XCTAssertTrue(first.hasProfile)
        XCTAssertEqual(first.measurementsCount, 1)
        XCTAssertEqual(first.readinessEntriesCount, 1)
        XCTAssertEqual(first.personalBestsCount, 1)
        XCTAssertEqual(first.trainingPlansCount, 1)

        let restoredProfile = try XCTUnwrap(destinationContext.fetch(FetchDescriptor<AthleteProfile>()).first)
        XCTAssertEqual(restoredProfile.massUnit, .pounds)
        XCTAssertEqual(restoredProfile.bodyweightKilograms, 78.4)
        XCTAssertEqual(restoredProfile.avoidAreas, ["lower back"])
        XCTAssertEqual(restoredProfile.defaultProgressionRule, .linearLoad(incrementKilograms: 5, requiredSuccesses: 2))

        let restoredPlan = try XCTUnwrap(destinationContext.fetch(FetchDescriptor<TrainingPlan>()).first)
        XCTAssertEqual(restoredPlan.allWeeks.count, 1)
        XCTAssertEqual(restoredPlan.allWeeks.first?.orderedWorkouts.first?.displayName, "Séance A")

        let second = try ExportImport.importAll(data: data, context: destinationContext)
        XCTAssertFalse(second.hasProfile)
        XCTAssertEqual(second.measurementsCount, 0)
        XCTAssertEqual(second.trainingPlansCount, 0)
        XCTAssertEqual(try destinationContext.fetchCount(FetchDescriptor<PersonalBest>()), 1)
    }

    /// Un superset exporte doit revenir avec ses exercices rattaches au bon
    /// groupe, jamais a un groupe voisin.
    func testExerciseGroupsRoundTrip() throws {
        let source = try TestStore.makeContainer()
        let context = source.mainContext

        let first = PrescribedExercise(exerciseId: "A", displayName: "Développé", orderIndex: 0, sets: 3, repsLower: 8, repsUpper: 10)
        let second = PrescribedExercise(exerciseId: "B", displayName: "Rowing", orderIndex: 1, sets: 3, repsLower: 8, repsUpper: 10)
        second.groupOrderIndex = 1
        let session = ProgramSession(name: "Push/Pull", orderIndex: 0, exercises: [first, second])
        let group = ExerciseGroup(kindRaw: ExerciseGroupKind.superset.rawValue, orderIndex: 0, rounds: 3)
        group.session = session
        session.groups = [group]
        first.group = group
        second.group = group
        let program = Program(name: "Superset", sessions: [session])
        context.insert(program)
        try context.save()

        let data = try ExportImport.exportAll(context: context)
        let destination = try TestStore.makeContainer()
        try ExportImport.importAll(data: data, context: destination.mainContext)

        let restoredSession = try XCTUnwrap(destination.mainContext.fetch(FetchDescriptor<ProgramSession>()).first)
        XCTAssertEqual(restoredSession.orderedGroups.count, 1)
        let restoredGroup = try XCTUnwrap(restoredSession.orderedGroups.first)
        XCTAssertEqual(restoredGroup.kind, .superset)
        XCTAssertEqual(restoredGroup.rounds, 3)
        XCTAssertEqual(restoredGroup.orderedExercises.map(\.displayName), ["Développé", "Rowing"])
    }

    func testRejectsUnsupportedFutureVersion() throws {
        let json = #"{"version": 99, "exportedAt": "2026-01-01T00:00:00Z"}"#
        let data = try XCTUnwrap(json.data(using: .utf8))
        let container = try TestStore.makeContainer()
        XCTAssertThrowsError(try ExportImport.importAll(data: data, context: container.mainContext)) { error in
            XCTAssertEqual(error as? ExportImport.ImportError, .unsupportedVersion(99))
        }
    }

    func testRejectsOversizedInput() throws {
        let data = Data(repeating: 0, count: ExportImport.maximumImportBytes + 1)
        let container = try TestStore.makeContainer()
        XCTAssertThrowsError(try ExportImport.importAll(data: data, context: container.mainContext))
    }

    // MARK: - Helpers

    private func fixtureData(named name: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle(for: ExportImportTests.self).url(forResource: name, withExtension: "json"),
            "Fixture \(name).json absente du bundle de test"
        )
        return try Data(contentsOf: url)
    }

    /// Encode une enveloppe v3 coherente (manifeste + somme de controle) a
    /// partir d'un payload arbitraire, pour tester la validation metier sans
    /// declencher d'abord l'erreur de somme de controle.
    private func encodedEnvelope(payload: ExportImport.Payload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let canonical = try encoder.encode(payload)
        let envelope = ExportImport.Envelope(
            version: ExportImport.currentVersion,
            exportedAt: .now,
            manifest: ExportImport.Manifest(
                schemaVersion: 3,
                appVersion: "test",
                counts: [:],
                checksum: ExportImport.checksum(of: canonical)
            ),
            payload: payload
        )
        return try encoder.encode(envelope)
    }
}
