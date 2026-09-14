import XCTest
import SwiftData
import MuscuEngine
@testable import Muscu

@MainActor
final class HealthSyncServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let reference = Date(timeIntervalSince1970: 1_772_000_000)

    override func setUpWithError() throws {
        container = try TestStore.makeContainer()
        HealthSettings.reset()
    }

    override func tearDownWithError() throws {
        HealthSettings.reset()
        container = nil
    }

    @discardableResult
    private func addSession(offsetDays: Int = 0, duration: Int = 3_600, deleted: Bool = false) -> CompletedSession {
        let session = CompletedSession(
            date: reference.addingTimeInterval(Double(offsetDays) * 86_400),
            programName: "Programme",
            sessionName: "Séance A",
            durationSeconds: duration
        )
        if deleted { session.deletedAt = reference }
        context.insert(session)
        try? context.save()
        return session
    }

    // MARK: - Autorisation

    func testNothingIsSharedUntilTheUserEnablesIt() async throws {
        addSession()
        let store = InMemoryHealthStore(status: .notDetermined)

        await HealthSyncService.synchronize(in: context, store: store)

        XCTAssertEqual(store.authorizationRequestCount, 0, "La synchronisation ne demande jamais l’autorisation d’elle-même")
        XCTAssertTrue(store.writtenWorkoutIdentifiers.isEmpty)
    }

    func testEnablingAsksOnceAndWrites() async throws {
        let session = addSession()
        let store = InMemoryHealthStore(status: .notDetermined)

        let outcome = await HealthSyncService.enable(in: context, store: store)

        XCTAssertEqual(store.authorizationRequestCount, 1)
        XCTAssertEqual(outcome.authorization, .authorized)
        XCTAssertEqual(outcome.written, 1)
        XCTAssertTrue(store.containsWorkout(for: session.id))
        XCTAssertTrue(HealthSettings.isEnabled)
    }

    func testARefusalChangesNothingAndBlocksNothing() async throws {
        addSession()
        let store = InMemoryHealthStore(status: .notDetermined)
        store.answerOnRequest = .denied

        let outcome = await HealthSyncService.enable(in: context, store: store)

        XCTAssertEqual(outcome.authorization, .denied)
        XCTAssertFalse(HealthSettings.isEnabled)
        XCTAssertTrue(store.writtenWorkoutIdentifiers.isEmpty)
        // L'historique local reste intact : un refus n'altère aucune donnée.
        XCTAssertEqual(try context.fetch(FetchDescriptor<CompletedSession>()).count, 1)
    }

    func testAnUnavailableDeviceIsNotARefusal() async throws {
        addSession()
        let store = InMemoryHealthStore(status: .notDetermined, isAvailable: false)

        let outcome = await HealthSyncService.enable(in: context, store: store)

        XCTAssertEqual(outcome.authorization, .unavailable)
        XCTAssertEqual(store.authorizationRequestCount, 0)
        XCTAssertFalse(HealthSettings.isEnabled)
    }

    // MARK: - Déduplication

    func testASessionIsWrittenOnlyOnce() async throws {
        let session = addSession()
        let store = InMemoryHealthStore(status: .authorized)
        HealthSettings.isEnabled = true

        let first = await HealthSyncService.synchronize(in: context, store: store)
        let second = await HealthSyncService.synchronize(in: context, store: store)

        XCTAssertEqual(first.written, 1)
        XCTAssertEqual(second.written, 0, "Une séance déjà écrite ne l’est jamais deux fois")
        XCTAssertEqual(second.alreadyWritten, 1)
        XCTAssertEqual(store.writtenWorkoutIdentifiers.count, 1)
        XCTAssertEqual(HealthSyncService.links(in: context).filter { $0.deletedAt == nil }.count, 1)
        XCTAssertTrue(store.containsWorkout(for: session.id))
    }

    func testAThirdPassStillWritesNothing() async throws {
        addSession()
        let store = InMemoryHealthStore(status: .authorized)
        HealthSettings.isEnabled = true

        for _ in 0..<3 { await HealthSyncService.synchronize(in: context, store: store) }

        XCTAssertEqual(store.writtenWorkoutIdentifiers.count, 1)
    }

    func testADeletedSessionRemovesItsWorkout() async throws {
        let session = addSession()
        let store = InMemoryHealthStore(status: .authorized)
        HealthSettings.isEnabled = true
        await HealthSyncService.synchronize(in: context, store: store)

        session.deletedAt = reference
        try context.save()
        let outcome = await HealthSyncService.synchronize(in: context, store: store)

        XCTAssertEqual(outcome.deleted, 1)
        XCTAssertTrue(store.writtenWorkoutIdentifiers.isEmpty)
        XCTAssertTrue(HealthSyncService.links(in: context).allSatisfy { $0.deletedAt != nil })
    }

    func testAFailedWriteLeavesNoLinkBehind() async throws {
        addSession()
        let store = InMemoryHealthStore(status: .authorized)
        store.nextWriteError = .writeFailed("service indisponible")
        HealthSettings.isEnabled = true

        let outcome = await HealthSyncService.synchronize(in: context, store: store)

        XCTAssertEqual(outcome.written, 0)
        XCTAssertFalse(outcome.failures.isEmpty)
        XCTAssertTrue(
            HealthSyncService.links(in: context).isEmpty,
            "Un lien sans entraînement ferait croire à un doublon protégé"
        )
    }

    func testARetryAfterAFailureWritesTheSession() async throws {
        addSession()
        let store = InMemoryHealthStore(status: .authorized)
        store.nextWriteError = .writeFailed("service indisponible")
        HealthSettings.isEnabled = true
        await HealthSyncService.synchronize(in: context, store: store)

        store.nextWriteError = nil
        let outcome = await HealthSyncService.synchronize(in: context, store: store)

        XCTAssertEqual(outcome.written, 1)
    }

    func testAShortSessionIsNotWritten() async throws {
        addSession(duration: 30)
        let store = InMemoryHealthStore(status: .authorized)
        HealthSettings.isEnabled = true

        let outcome = await HealthSyncService.synchronize(in: context, store: store)
        XCTAssertEqual(outcome.written, 0)
    }

    // MARK: - Poids corporel

    func testBodyweightIsImportedOnlyWhenShared() async throws {
        let store = InMemoryHealthStore(status: .authorized)
        store.insertExternalBodyweight(kilograms: 77.5, date: reference)
        HealthSettings.isEnabled = true
        HealthSettings.sharesBodyweight = false

        let withoutSharing = await HealthSyncService.synchronize(in: context, store: store)
        XCTAssertEqual(withoutSharing.importedMeasurements, 0)

        HealthSettings.sharesBodyweight = true
        HealthSettings.lastImportDate = nil
        let withSharing = await HealthSyncService.synchronize(in: context, store: store, now: reference.addingTimeInterval(60))

        XCTAssertEqual(withSharing.importedMeasurements, 1)
        let measurement = try XCTUnwrap(try context.fetch(FetchDescriptor<BodyMeasurement>()).first)
        XCTAssertEqual(measurement.value, 77.5)
        XCTAssertEqual(measurement.source, .healthKit)
    }

    func testOurOwnMeasurementIsNeverReimported() async throws {
        let store = InMemoryHealthStore(status: .authorized)
        HealthSettings.isEnabled = true
        HealthSettings.sharesBodyweight = true

        await HealthSyncService.exportBodyweight(kilograms: 78, date: reference, store: store)
        HealthSettings.lastImportDate = nil
        let outcome = await HealthSyncService.synchronize(in: context, store: store, now: reference.addingTimeInterval(60))

        XCTAssertEqual(outcome.importedMeasurements, 0, "Ce que Muscu a écrit ne doit pas revenir comme une nouveauté")
    }

    func testExportingBodyweightRequiresBothSwitches() async throws {
        let store = InMemoryHealthStore(status: .authorized)
        HealthSettings.isEnabled = true
        HealthSettings.sharesBodyweight = false

        await HealthSyncService.exportBodyweight(kilograms: 78, date: reference, store: store)

        let samples = try await store.readBodyweightSamples(since: reference.addingTimeInterval(-86_400))
        XCTAssertTrue(samples.isEmpty)
    }

    // MARK: - Désactivation et suppression

    func testDisablingKeepsWhatWasAlreadyWritten() async throws {
        addSession()
        let store = InMemoryHealthStore(status: .authorized)
        HealthSettings.isEnabled = true
        await HealthSyncService.synchronize(in: context, store: store)

        HealthSyncService.disable()

        XCTAssertFalse(HealthSettings.isEnabled)
        XCTAssertEqual(store.writtenWorkoutIdentifiers.count, 1, "Les entraînements appartiennent à l’app Santé")
    }

    func testDeletingTheHealthCategoryClearsLinksAndSettings() async throws {
        addSession()
        let store = InMemoryHealthStore(status: .authorized)
        HealthSettings.isEnabled = true
        await HealthSyncService.synchronize(in: context, store: store)

        let report = try DataDeletion.delete(.healthSharing, context: context)

        XCTAssertEqual(report.countsByModel["liens Santé"], 1)
        XCTAssertFalse(HealthSettings.isEnabled)
        XCTAssertTrue(HealthSyncService.links(in: context).isEmpty)
        XCTAssertEqual(store.writtenWorkoutIdentifiers.count, 1, "Rien n’est supprimé dans l’app Santé sans le demander")
    }
}
