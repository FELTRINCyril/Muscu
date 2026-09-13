import XCTest
import SwiftData
import MuscuEngine
@testable import Muscu

@MainActor
final class ExportV4Tests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUpWithError() throws {
        container = try TestStore.makeContainer()
    }

    override func tearDownWithError() throws {
        container = nil
    }

    private func seedVersionFourEntities() throws {
        let place = PlaceProfile(name: "Salle", kindRaw: PlaceKind.gym.rawValue, isDefault: true)
        place.inventory = EquipmentInventory(items: [
            EquipmentAvailability(equipmentId: "dumbbell", minimumLoad: 2, maximumLoad: 40, increment: 2),
        ])
        context.insert(place)

        let schedule = PlanningSchedule(name: "Semaine type", hour: 19, minute: 30, placeId: place.id)
        schedule.weekdays = [2, 5]
        schedule.pausedWeekOffsets = [3]
        schedule.remindersEnabled = true
        context.insert(schedule)

        let template = SessionTemplate(
            name: "Haut du corps",
            payloadData: try JSONEncoder().encode(TemplatePayload(sessions: [
                TemplateSession(name: "Haut", exercises: []),
            ]))
        )
        context.insert(template)

        let entry = ExerciseLibraryEntry(exerciseId: "bench", isFavorite: true)
        entry.tags = ["force"]
        context.insert(entry)

        let collection = ExerciseCollection(name: "Voyage")
        collection.exerciseIds = ["pushup", "squat"]
        context.insert(collection)

        try context.save()
    }

    func testExportIsVersionFourAndCountsNewEntities() throws {
        try seedVersionFourEntities()
        let data = try ExportImport.exportAll(context: context)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(ExportImport.Envelope.self, from: data)

        XCTAssertEqual(envelope.version, 4)
        XCTAssertEqual(envelope.manifest.counts["places"], 1)
        XCTAssertEqual(envelope.manifest.counts["schedules"], 1)
        XCTAssertEqual(envelope.manifest.counts["templates"], 1)
        XCTAssertEqual(envelope.manifest.counts["libraryEntries"], 1)
        XCTAssertEqual(envelope.manifest.counts["collections"], 1)
    }

    func testRoundTripRestoresNewEntities() throws {
        try seedVersionFourEntities()
        let data = try ExportImport.exportAll(context: context)

        let destination = try TestStore.makeContainer()
        let target = destination.mainContext
        _ = try ExportImport.importAll(data: data, context: target)

        let place = try XCTUnwrap(try target.fetch(FetchDescriptor<PlaceProfile>()).first)
        XCTAssertEqual(place.name, "Salle")
        XCTAssertEqual(place.inventory.practicableLoad(17, equipmentId: "dumbbell"), 18)

        let schedule = try XCTUnwrap(try target.fetch(FetchDescriptor<PlanningSchedule>()).first)
        XCTAssertEqual(schedule.weekdays, [2, 5])
        XCTAssertEqual(schedule.pausedWeekOffsets, [3])
        XCTAssertEqual(schedule.hour, 19)

        let template = try XCTUnwrap(try target.fetch(FetchDescriptor<SessionTemplate>()).first)
        XCTAssertEqual(TemplateService.payload(of: template)?.sessions.first?.name, "Haut")

        let entry = try XCTUnwrap(try target.fetch(FetchDescriptor<ExerciseLibraryEntry>()).first)
        XCTAssertTrue(entry.isFavorite)
        XCTAssertEqual(entry.tags, ["force"])

        let collection = try XCTUnwrap(try target.fetch(FetchDescriptor<ExerciseCollection>()).first)
        XCTAssertEqual(collection.exerciseIds, ["pushup", "squat"])
    }

    /// Une archive ne peut pas rallumer les notifications : l'autorisation
    /// appartient a l'appareil, pas au fichier.
    func testImportedRemindersAreAlwaysDisabled() throws {
        try seedVersionFourEntities()
        let data = try ExportImport.exportAll(context: context)

        let destination = try TestStore.makeContainer()
        _ = try ExportImport.importAll(data: data, context: destination.mainContext)

        let schedule = try XCTUnwrap(try destination.mainContext.fetch(FetchDescriptor<PlanningSchedule>()).first)
        XCTAssertFalse(schedule.remindersEnabled)
    }

    func testImportingTwiceCreatesNoDuplicate() throws {
        try seedVersionFourEntities()
        let data = try ExportImport.exportAll(context: context)

        let destination = try TestStore.makeContainer()
        _ = try ExportImport.importAll(data: data, context: destination.mainContext)
        _ = try ExportImport.importAll(data: data, context: destination.mainContext)

        XCTAssertEqual(try destination.mainContext.fetch(FetchDescriptor<PlaceProfile>()).count, 1)
        XCTAssertEqual(try destination.mainContext.fetch(FetchDescriptor<SessionTemplate>()).count, 1)
        XCTAssertEqual(try destination.mainContext.fetch(FetchDescriptor<ExerciseLibraryEntry>()).count, 1)
    }

    func testOlderBackupsWithoutVersionFourSectionsStillImport() throws {
        let bundle = Bundle(for: ExportV4Tests.self)
        for name in ["export-v1", "export-v2"] {
            let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "json"), "Fixture \(name) absente")
            let destination = try TestStore.makeContainer()
            let summary = try ExportImport.importAll(data: try Data(contentsOf: url), context: destination.mainContext)
            XCTAssertGreaterThan(summary.programsCount + summary.sessionsCount, 0, "\(name) doit encore s’importer")
            XCTAssertTrue(try destination.mainContext.fetch(FetchDescriptor<PlaceProfile>()).isEmpty)
        }
    }

    func testTamperedVersionFourArchiveIsRejectedWithoutWriting() throws {
        try seedVersionFourEntities()
        let data = try ExportImport.exportAll(context: context)
        var text = try XCTUnwrap(String(data: data, encoding: .utf8))
        text = text.replacingOccurrences(of: "\"Salle\"", with: "\"Salle modifiée\"")

        let destination = try TestStore.makeContainer()
        XCTAssertThrowsError(try ExportImport.importAll(data: Data(text.utf8), context: destination.mainContext))
        XCTAssertTrue(try destination.mainContext.fetch(FetchDescriptor<PlaceProfile>()).isEmpty)
    }
}

/// Les entites exposees aux raccourcis doivent repondre en francais comme en
/// anglais : Siri peut etre configure dans l'une ou l'autre langue.
final class IntentEntityTests: XCTestCase {
    func testExerciseQueryAnswersInFrench() async throws {
        let results = try await ExerciseEntityQuery().entities(matching: "developpe couche")
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.contains { $0.name.contains("Développé couché") })
    }

    func testExerciseQueryAnswersInEnglish() async throws {
        let results = try await ExerciseEntityQuery().entities(matching: "bench press")
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.contains { $0.name.localizedCaseInsensitiveContains("développé") })
    }

    func testExerciseQueryToleratesATypo() async throws {
        let results = try await ExerciseEntityQuery().entities(matching: "develope couche")
        XCTAssertFalse(results.isEmpty)
    }

    func testExerciseQueryResolvesStableIdentifiers() async throws {
        let matches = try await ExerciseEntityQuery().entities(matching: "squat")
        let first = try XCTUnwrap(matches.first)
        let resolved = try await ExerciseEntityQuery().entities(for: [first.id])
        XCTAssertEqual(resolved.first?.id, first.id)
        XCTAssertEqual(resolved.first?.name, first.name)
    }

    func testUnknownQueryReturnsNothingRatherThanAWrongMatch() async throws {
        let results = try await ExerciseEntityQuery().entities(matching: "natation papillon")
        XCTAssertTrue(results.isEmpty)
    }
}
