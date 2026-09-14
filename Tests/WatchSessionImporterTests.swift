import XCTest
import SwiftData
import MuscuEngine
@testable import Muscu

@MainActor
final class WatchSessionImporterTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let reference = Date(timeIntervalSince1970: 1_772_000_000)

    override func setUpWithError() throws {
        container = try TestStore.makeContainer()
    }

    override func tearDownWithError() throws {
        container = nil
    }

    private func payload(id: UUID = UUID(), sets: Int = 3, version: Int = 1) -> WatchSessionPayload {
        WatchSessionPayload(
            version: version,
            id: id,
            sessionName: "Séance A",
            startedAt: reference,
            durationSeconds: 2_400,
            sets: (0..<sets).map {
                WatchSetPayload(exerciseName: "Développé", setIndex: $0, weightKilograms: 60, reps: 8)
            }
        )
    }

    func testAWatchSessionJoinsTheHistory() throws {
        let decision = WatchSessionImporter.importSession(payload(), in: context)

        XCTAssertEqual(decision, .accept)
        let sessions = try context.fetch(FetchDescriptor<CompletedSession>())
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.sessionName, "Séance A")
        XCTAssertEqual(sessions.first?.sets.count, 3)
        XCTAssertEqual(sessions.first?.importSource, WatchSessionImporter.sourceName)
    }

    /// Le jalon de la phase : une séance Watch rejoint l'historique UNE SEULE
    /// FOIS, quel que soit le nombre de transferts.
    func testAReplayedTransferAddsNothing() throws {
        let sent = payload()

        XCTAssertEqual(WatchSessionImporter.importSession(sent, in: context), .accept)
        XCTAssertEqual(WatchSessionImporter.importSession(sent, in: context), .duplicate)
        XCTAssertEqual(WatchSessionImporter.importSession(sent, in: context), .duplicate)

        XCTAssertEqual(try context.fetch(FetchDescriptor<CompletedSession>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CompletedSet>()).count, 3)
    }

    func testTwoDifferentSessionsBothArrive() throws {
        WatchSessionImporter.importSession(payload(), in: context)
        WatchSessionImporter.importSession(payload(), in: context)

        XCTAssertEqual(try context.fetch(FetchDescriptor<CompletedSession>()).count, 2)
    }

    func testTheSessionKeepsTheIdentifierMintedOnTheWatch() throws {
        let id = UUID()
        WatchSessionImporter.importSession(payload(id: id), in: context)

        let session = try XCTUnwrap(try context.fetch(FetchDescriptor<CompletedSession>()).first)
        XCTAssertEqual(session.id, id, "C’est cet identifiant qui protège des doublons")
    }

    func testAnEmptySessionIsNotWritten() throws {
        let decision = WatchSessionImporter.importSession(payload(sets: 0), in: context)

        XCTAssertEqual(decision, .empty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CompletedSession>()).isEmpty)
    }

    func testAnUnsupportedVersionIsRefusedWithoutWriting() throws {
        let decision = WatchSessionImporter.importSession(payload(version: 99), in: context)

        XCTAssertEqual(decision, .unsupportedVersion(99))
        XCTAssertTrue(try context.fetch(FetchDescriptor<CompletedSession>()).isEmpty)
    }

    func testReceivedSetsCountAsWorkingSets() throws {
        WatchSessionImporter.importSession(payload(), in: context)

        let sets = try context.fetch(FetchDescriptor<CompletedSet>())
        XCTAssertTrue(sets.allSatisfy { $0.role == .working })
        XCTAssertTrue(sets.allSatisfy { !$0.isWarmup })
    }

    func testAnExistingPhoneSessionIsNeverOverwritten() throws {
        let id = UUID()
        let existing = CompletedSession(
            id: id,
            date: reference,
            programName: "Programme",
            sessionName: "Séance du téléphone"
        )
        context.insert(existing)
        try context.save()

        let decision = WatchSessionImporter.importSession(payload(id: id), in: context)

        XCTAssertEqual(decision, .duplicate)
        XCTAssertEqual(existing.sessionName, "Séance du téléphone")
    }

    func testThePayloadSurvivesEncodingAndDecoding() throws {
        let sent = payload()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(WatchSessionPayload.self, from: try encoder.encode(sent))
        XCTAssertEqual(decoded, sent)
    }
}
