import XCTest
import SwiftData
import MuscuEngine
@testable import Muscu

/// Attributs ajoutés en v7 : aller-retour par l'export JSON, validation à
/// l'import, et mesures Santé tenues hors de la synchronisation iCloud.
@MainActor
final class SchemaV7FieldsTests: XCTestCase {
    // MARK: - Export / import

    func testVersionSevenFieldsRoundTripThroughExport() throws {
        let source = try TestStore.makeContainer()
        let context = source.mainContext
        let editedAt = Date(timeIntervalSince1970: 1_750_000_000)

        let set = CompletedSet(
            exerciseId: "bench", displayName: "Développé couché",
            orderIndex: 0, setIndex: 1, weight: 100, reps: 5,
            actualRestSeconds: 0
        )
        let session = CompletedSession(
            programName: "P", sessionName: "A", durationSeconds: 1_800,
            effortRating: 7, avgHeartRate: 128, maxHeartRate: 171, minHeartRate: 88,
            activeEnergyKcal: 0, editedAt: editedAt, sets: [set]
        )
        context.insert(session)
        context.insert(CustomExercise(name: "Doublon", mergedIntoExerciseId: "bench"))
        context.insert(ExerciseLibraryEntry(exerciseId: "bench", demoURL: "https://example.com/bench"))
        context.insert(BodyMeasurement(value: 80, sourceRaw: MeasurementSource.healthKit.rawValue, healthSampleUUID: "ABC-123"))
        try context.save()

        let data = try ExportImport.exportAll(context: context)
        let destinationContainer = try TestStore.makeContainer()
        let destination = destinationContainer.mainContext
        _ = try ExportImport.importAll(data: data, context: destination)

        let restored = try XCTUnwrap(try destination.fetch(FetchDescriptor<CompletedSession>()).first)
        XCTAssertEqual(restored.effortRating, 7)
        XCTAssertEqual(restored.avgHeartRate, 128)
        XCTAssertEqual(restored.maxHeartRate, 171)
        XCTAssertEqual(restored.minHeartRate, 88)
        XCTAssertEqual(restored.activeEnergyKcal, 0, "Zéro mesuré n'est pas une absence")
        XCTAssertEqual(restored.editedAt, editedAt)
        XCTAssertEqual(restored.sets.first?.actualRestSeconds, 0)

        XCTAssertEqual(try destination.fetch(FetchDescriptor<CustomExercise>()).first?.mergedIntoExerciseId, "bench")
        XCTAssertEqual(try destination.fetch(FetchDescriptor<ExerciseLibraryEntry>()).first?.demoURL, "https://example.com/bench")
        XCTAssertEqual(try destination.fetch(FetchDescriptor<BodyMeasurement>()).first?.healthSampleUUID, "ABC-123")
    }

    func testAbsentVersionSevenFieldsStayAbsent() throws {
        let source = try TestStore.makeContainer()
        let context = source.mainContext
        context.insert(CompletedSession(programName: "P", sessionName: "A", sets: [
            CompletedSet(exerciseId: "bench", displayName: "Développé", orderIndex: 0, setIndex: 0, weight: 60, reps: 8),
        ]))
        try context.save()

        let data = try ExportImport.exportAll(context: context)
        let destinationContainer = try TestStore.makeContainer()
        let destination = destinationContainer.mainContext
        _ = try ExportImport.importAll(data: data, context: destination)

        let restored = try XCTUnwrap(try destination.fetch(FetchDescriptor<CompletedSession>()).first)
        XCTAssertNil(restored.effortRating)
        XCTAssertNil(restored.avgHeartRate)
        XCTAssertNil(restored.activeEnergyKcal)
        XCTAssertNil(restored.editedAt)
        XCTAssertNil(restored.sets.first?.actualRestSeconds)
    }

    func testImportRejectsImplausibleVersionSevenValues() throws {
        func payload(_ mutate: (inout ExportImport.CompletedSessionDTO) -> Void) -> ExportImport.Payload {
            var session = ExportImport.CompletedSessionDTO(
                id: UUID(), date: .now, programName: "P", sessionName: "A",
                durationSeconds: 60, sets: []
            )
            mutate(&session)
            var payload = ExportImport.Payload()
            payload.sessions = [session]
            return payload
        }

        let invalid: [ExportImport.Payload] = [
            payload { $0.effortRating = 0 },
            payload { $0.effortRating = 11 },
            payload { $0.avgHeartRate = 0 },
            payload { $0.maxHeartRate = .infinity },
            payload { $0.activeEnergyKcal = -1 },
        ]
        for candidate in invalid {
            let container = try TestStore.makeContainer()
            XCTAssertThrowsError(try ExportImport.importAll(data: try encoded(candidate), context: container.mainContext))
            XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<CompletedSession>()), 0)
        }

        var dangerousLink = ExportImport.Payload()
        dangerousLink.libraryEntries = [ExportImport.LibraryEntryDTO(
            exerciseId: "bench", isFavorite: false, tags: [], lastUsedAt: nil,
            createdAt: .now, updatedAt: .now, deletedAt: nil, demoURL: "javascript:alert(1)"
        )]
        let container = try TestStore.makeContainer()
        XCTAssertThrowsError(try ExportImport.importAll(data: try encoded(dangerousLink), context: container.mainContext))
    }

    // MARK: - Synchronisation

    func testSyncPayloadOmitsHealthMeasuresButKeepsEffort() throws {
        // Le conteneur doit survivre au contexte : on le garde en variable.
        let container = try TestStore.makeContainer()
        let context = container.mainContext
        let session = CompletedSession(
            programName: "P", sessionName: "A",
            effortRating: 6, avgHeartRate: 120, maxHeartRate: 160, minHeartRate: 80, activeEnergyKcal: 350
        )
        context.insert(session)
        try context.save()

        let record = try XCTUnwrap(try SyncSerialization.localRecords(context: context)[session.id])
        let dto = try SyncSerialization.decoder().decode(ExportImport.CompletedSessionDTO.self, from: record.payload)
        XCTAssertEqual(dto.effortRating, 6)
        XCTAssertNil(dto.avgHeartRate)
        XCTAssertNil(dto.maxHeartRate)
        XCTAssertNil(dto.minHeartRate)
        XCTAssertNil(dto.activeEnergyKcal)
    }

    func testApplyingRemoteSessionKeepsLocalHealthMeasures() throws {
        // Le conteneur doit survivre au contexte : on le garde en variable.
        let container = try TestStore.makeContainer()
        let context = container.mainContext
        let session = CompletedSession(
            programName: "P", sessionName: "A", avgHeartRate: 120, activeEnergyKcal: 350
        )
        context.insert(session)
        try context.save()

        let record = try XCTUnwrap(try SyncSerialization.localRecords(context: context)[session.id])
        try SyncSerialization.apply(record, into: context)
        try context.save()

        let restored = try XCTUnwrap(try context.fetch(FetchDescriptor<CompletedSession>()).first)
        XCTAssertEqual(restored.avgHeartRate, 120)
        XCTAssertEqual(restored.activeEnergyKcal, 350)
    }

    // MARK: - Bibliothèque

    func testDemoLinkKeepsLibraryEntryAlive() {
        let entry = ExerciseLibraryEntry(exerciseId: "bench")
        XCTAssertTrue(entry.isEmpty)
        entry.demoURL = "https://example.com"
        XCTAssertFalse(entry.isEmpty, "Une annotation qui ne porte qu'un lien ne doit pas être purgée")
    }

    // MARK: - Helpers

    private func encoded(_ payload: ExportImport.Payload) throws -> Data {
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
