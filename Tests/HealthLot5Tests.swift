import XCTest
import SwiftData
import MuscuEngine
@testable import Muscu

/// Lot 5 : note d'effort ecrite dans Sante, seance en direct reliee, cardio
/// lu apres coup, import de la masse grasse et du tour de taille.
@MainActor
final class HealthLot5Tests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let reference = Date(timeIntervalSince1970: 1_772_000_000)

    override func setUpWithError() throws {
        container = try TestStore.makeContainer()
        HealthSettings.reset()
        HealthSettings.isEnabled = true
    }

    override func tearDownWithError() throws {
        HealthSettings.reset()
        container = nil
    }

    @discardableResult
    private func addSession(effort: Int? = nil, duration: Int = 3_600) -> CompletedSession {
        let session = CompletedSession(
            date: reference,
            programName: "Programme",
            sessionName: "Séance A",
            durationSeconds: duration,
            effortRating: effort
        )
        context.insert(session)
        try? context.save()
        return session
    }

    private func liveLinks() -> [HealthWorkoutLink] {
        HealthSyncService.links(in: context).filter { $0.deletedAt == nil }
    }

    // MARK: - Note d'effort

    func testEffortIsWrittenWithTheWorkout() async throws {
        addSession(effort: 7)
        let store = InMemoryHealthStore(status: .authorized)

        let outcome = await HealthSyncService.synchronize(in: context, store: store, now: reference.addingTimeInterval(60))

        XCTAssertEqual(outcome.written, 1)
        XCTAssertTrue(outcome.failures.isEmpty)
        let link = try XCTUnwrap(liveLinks().first)
        XCTAssertEqual(store.effortScores[link.healthKitWorkoutIdentifier], 7)
        XCTAssertEqual(link.writtenEffortRating, 7)
        XCTAssertNotNil(link.effortSampleIdentifier)
        XCTAssertEqual(link.writtenDurationSeconds, 3_600)
        XCTAssertEqual(link.writtenStartDate, reference.addingTimeInterval(-3_600))
    }

    func testCorrectedEffortReplacesOnlyItsSample() async throws {
        let session = addSession(effort: 7)
        let store = InMemoryHealthStore(status: .authorized)
        await HealthSyncService.synchronize(in: context, store: store, now: reference.addingTimeInterval(60))
        let workouts = store.writtenWorkoutIdentifiers

        session.effortRating = 9
        session.editedAt = reference.addingTimeInterval(120)
        try context.save()
        let outcome = await HealthSyncService.synchronize(in: context, store: store, now: reference.addingTimeInterval(180))

        XCTAssertEqual(outcome.written, 0, "Les horaires n’ont pas changé : l’entraînement est gardé")
        XCTAssertEqual(outcome.deleted, 0)
        XCTAssertEqual(store.writtenWorkoutIdentifiers, workouts)
        XCTAssertEqual(store.effortSampleCount, 1, "L’ancienne note est retirée")
        XCTAssertEqual(store.effortScores[workouts[0]], 9)
        XCTAssertEqual(liveLinks().first?.writtenEffortRating, 9)
    }

    func testRemovedEffortRemovesItsSample() async throws {
        let session = addSession(effort: 7)
        let store = InMemoryHealthStore(status: .authorized)
        await HealthSyncService.synchronize(in: context, store: store, now: reference.addingTimeInterval(60))

        session.effortRating = nil
        try context.save()
        await HealthSyncService.synchronize(in: context, store: store, now: reference.addingTimeInterval(120))

        XCTAssertEqual(store.effortSampleCount, 0)
        XCTAssertNil(liveLinks().first?.writtenEffortRating)
        XCTAssertNil(liveLinks().first?.effortSampleIdentifier)
    }

    func testARefusedEffortTypeIsNotAFailure() async throws {
        addSession(effort: 7)
        let store = InMemoryHealthStore(status: .authorized)
        store.effortAllowed = false

        let outcome = await HealthSyncService.synchronize(in: context, store: store, now: reference.addingTimeInterval(60))

        XCTAssertEqual(outcome.written, 1)
        XCTAssertTrue(outcome.failures.isEmpty)
        XCTAssertEqual(store.effortSampleCount, 0)
    }

    // MARK: - Séance en direct

    func testALiveWorkoutIsLinkedAndNeverRewritten() async throws {
        let session = addSession(effort: 6)
        let store = InMemoryHealthStore(status: .authorized)
        store.insertWorkout(identifier: "live-1", sessionId: session.id, start: reference.addingTimeInterval(-3_600), duration: 3_600)

        let attached = await HealthSyncService.attachLiveWorkout(
            identifier: "live-1",
            to: session.id,
            cardio: SessionCardio(averageHeartRate: 131.4, minimumHeartRate: 88, maximumHeartRate: 172, activeEnergyKilocalories: 310),
            in: context,
            store: store,
            now: reference.addingTimeInterval(5)
        )
        XCTAssertTrue(attached)
        XCTAssertEqual(session.avgHeartRate, 131)
        XCTAssertEqual(session.minHeartRate, 88)
        XCTAssertEqual(session.maxHeartRate, 172)
        XCTAssertEqual(session.activeEnergyKcal, 310)
        XCTAssertEqual(store.effortScores["live-1"], 6)

        let outcome = await HealthSyncService.synchronize(in: context, store: store, now: reference.addingTimeInterval(60))
        XCTAssertEqual(outcome.written, 0, "L’entraînement en direct remplace l’écriture après coup")
        XCTAssertEqual(outcome.alreadyWritten, 1)
        XCTAssertEqual(store.writtenWorkoutIdentifiers, ["live-1"])
        XCTAssertEqual(liveLinks().first?.sourceRaw, "iphone-live")
    }

    func testALiveWorkoutReplacesAnAfterTheFactOne() async throws {
        let session = addSession()
        let store = InMemoryHealthStore(status: .authorized)
        await HealthSyncService.synchronize(in: context, store: store, now: reference.addingTimeInterval(60))
        XCTAssertEqual(store.writtenWorkoutIdentifiers.count, 1)

        store.insertWorkout(identifier: "live-1", sessionId: session.id, start: reference.addingTimeInterval(-3_600), duration: 3_600)
        await HealthSyncService.attachLiveWorkout(
            identifier: "live-1",
            to: session.id,
            cardio: SessionCardio(averageHeartRate: nil, minimumHeartRate: nil, maximumHeartRate: nil, activeEnergyKilocalories: nil),
            in: context,
            store: store
        )

        XCTAssertEqual(store.writtenWorkoutIdentifiers, ["live-1"], "Jamais deux entraînements pour une séance")
        XCTAssertEqual(liveLinks().count, 1)
        XCTAssertNil(session.avgHeartRate, "Sans capteur, aucune fréquence : jamais zéro")
    }

    // MARK: - Cardio lu après coup

    func testCardioIsReadFromHealthAfterTheSession() async throws {
        let session = addSession()
        let store = InMemoryHealthStore(status: .authorized)
        store.insertCardio(
            HealthCardioReading(heartRates: [100, 120, 140], activeEnergyKilocalories: 280.6),
            start: reference.addingTimeInterval(-3_600),
            end: reference
        )

        await HealthSyncService.synchronize(in: context, store: store, now: reference.addingTimeInterval(60))

        XCTAssertEqual(session.avgHeartRate, 120)
        XCTAssertEqual(session.minHeartRate, 100)
        XCTAssertEqual(session.maxHeartRate, 140)
        XCTAssertEqual(session.activeEnergyKcal, 281)
    }

    func testMeasuredCardioIsNeverOverwritten() async throws {
        let session = addSession()
        session.avgHeartRate = 150
        try context.save()
        let store = InMemoryHealthStore(status: .authorized)
        store.insertCardio(HealthCardioReading(heartRates: [100], activeEnergyKilocalories: 50), start: reference.addingTimeInterval(-3_600), end: reference)

        await HealthSyncService.synchronize(in: context, store: store, now: reference.addingTimeInterval(60))

        XCTAssertEqual(session.avgHeartRate, 150)
        XCTAssertNil(session.activeEnergyKcal)
    }

    func testNoHeartRateLeavesNil() async throws {
        let session = addSession()
        let store = InMemoryHealthStore(status: .authorized)

        await HealthSyncService.synchronize(in: context, store: store, now: reference.addingTimeInterval(60))

        XCTAssertNil(session.avgHeartRate)
        XCTAssertNil(session.activeEnergyKcal)
        XCTAssertFalse(session.hasCardio)
    }

    // MARK: - Mesures

    func testBodyFatAndWaistAreImportedPerSwitch() async throws {
        let store = InMemoryHealthStore(status: .authorized)
        store.insertExternalMeasurement(.bodyFatPercent, value: 18.5, date: reference, identifier: "fat-1")
        store.insertExternalMeasurement(.waist, value: 82, date: reference, identifier: "waist-1")
        HealthSettings.writesWorkouts = false
        HealthSettings.importsBodyFat = true

        let first = await HealthSyncService.synchronize(in: context, store: store, now: reference.addingTimeInterval(60))
        XCTAssertEqual(first.importedMeasurements, 1)
        let fat = try XCTUnwrap(try context.fetch(FetchDescriptor<BodyMeasurement>()).first)
        XCTAssertEqual(fat.kind, .bodyFatPercent)
        XCTAssertEqual(fat.value, 18.5)
        XCTAssertEqual(fat.source, .healthKit)
        XCTAssertEqual(fat.healthSampleUUID, "fat-1")

        HealthSettings.importsWaist = true
        let second = await HealthSyncService.synchronize(in: context, store: store, now: reference.addingTimeInterval(120))
        XCTAssertEqual(second.importedMeasurements, 1)

        // Même en relisant tout, un échantillon connu n'est jamais réimporté.
        for kind in HealthMeasurementKind.allCases { HealthSettings.setLastImportDate(nil, for: kind) }
        let third = await HealthSyncService.synchronize(in: context, store: store, now: reference.addingTimeInterval(180))
        XCTAssertEqual(third.importedMeasurements, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<BodyMeasurement>()).count, 2)
    }

    func testADeletedImportIsNotReimported() async throws {
        let store = InMemoryHealthStore(status: .authorized)
        store.insertExternalMeasurement(.waist, value: 82, date: reference, identifier: "waist-1")
        HealthSettings.importsWaist = true
        await HealthSyncService.synchronize(in: context, store: store, now: reference.addingTimeInterval(60))
        let measurement = try XCTUnwrap(try context.fetch(FetchDescriptor<BodyMeasurement>()).first)
        measurement.deletedAt = reference.addingTimeInterval(90)
        try context.save()

        HealthSettings.setLastImportDate(nil, for: .waist)
        let outcome = await HealthSyncService.synchronize(in: context, store: store, now: reference.addingTimeInterval(120))

        XCTAssertEqual(outcome.importedMeasurements, 0, "Réimporter défierait la suppression")
    }

    func testMeasurementKindsMatchTheModel() {
        for kind in HealthMeasurementKind.allCases {
            XCTAssertNotNil(BodyMeasurementKind(rawValue: kind.rawValue))
        }
    }

    // MARK: - Autorisation des nouveaux types

    func testNewTypesAreAskedOnlyWhenTheUserEnables() async throws {
        let store = InMemoryHealthStore(status: .authorized)
        store.hasPendingTypes = true

        await HealthSyncService.synchronize(in: context, store: store, now: reference)
        XCTAssertEqual(store.authorizationRequestCount, 0, "La synchronisation ne demande jamais rien")

        HealthSettings.isEnabled = false
        _ = await HealthSyncService.enable(in: context, store: store, now: reference)
        XCTAssertEqual(store.authorizationRequestCount, 1)

        let status = await HealthSyncService.requestNewTypes(store: store)
        XCTAssertEqual(status, .authorized)
        XCTAssertEqual(store.authorizationRequestCount, 1, "Plus rien à demander")
    }
}
