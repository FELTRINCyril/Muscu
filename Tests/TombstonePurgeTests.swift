import XCTest
import SwiftData
import MuscuEngine
@testable import Muscu

@MainActor
final class TombstonePurgeTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private let now = Date(timeIntervalSince1970: 1_760_000_000)

    override func setUp() async throws {
        try await super.setUp()
        container = try TestStore.makeContainer()
        context = ModelContext(container)
        DiagnosticsCenter.reset()
    }

    override func tearDown() async throws {
        DiagnosticsCenter.reset()
        container = nil
        context = nil
        try await super.tearDown()
    }

    private func old(_ days: Double) -> Date {
        now.addingTimeInterval(-days * 24 * 60 * 60)
    }

    /// Le sursis existe pour qu'un appareil resté longtemps hors ligne
    /// reçoive quand même la suppression. Purger avant serait perdre
    /// l'information.
    func testATombstoneInsideItsRetentionWindowIsKept() throws {
        let session = CompletedSession(programName: "P", sessionName: "A")
        session.deletedAt = old(30)
        context.insert(session)
        try context.save()

        let report = try TombstonePurge.run(context: context, now: now)
        XCTAssertEqual(report.total, 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CompletedSession>()), 1)
    }

    func testATombstonePastItsRetentionWindowIsRemoved() throws {
        let session = CompletedSession(programName: "P", sessionName: "A")
        session.deletedAt = old(120)
        context.insert(session)
        try context.save()

        let report = try TombstonePurge.run(context: context, now: now)
        XCTAssertEqual(report.countsByModel["CompletedSession"], 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CompletedSession>()), 0)
    }

    /// Une entité VIVANTE ne doit jamais être touchée, même très ancienne :
    /// c'est la garantie qui rend cette purge acceptable au démarrage.
    func testALivingEntityIsNeverTouchedHoweverOldItIs() throws {
        let session = CompletedSession(date: old(3000), programName: "P", sessionName: "A")
        session.createdAt = old(3000)
        session.updatedAt = old(3000)
        context.insert(session)

        let program = Program(name: "Programme")
        program.createdAt = old(3000)
        program.updatedAt = old(3000)
        context.insert(program)
        try context.save()

        let report = try TombstonePurge.run(context: context, now: now)
        XCTAssertEqual(report.total, 0, "Aucune donnée vivante ne doit disparaître")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CompletedSession>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Program>()), 1)
    }

    /// Le sursis se compte depuis `deletedAt`, jamais depuis `updatedAt` :
    /// une entité supprimée hier mais créée il y a trois ans doit rester.
    func testTheDelayIsCountedFromTheDeletionNotTheLastChange() throws {
        let measurement = BodyMeasurement(
            kindRaw: BodyMeasurementKind.bodyweight.rawValue,
            measuredAt: old(1000),
            value: 80
        )
        measurement.createdAt = old(1000)
        measurement.updatedAt = old(1000)
        measurement.deletedAt = old(1)
        context.insert(measurement)
        try context.save()

        let report = try TombstonePurge.run(context: context, now: now)
        XCTAssertEqual(report.total, 0)
    }

    func testPurgingIsIdempotent() throws {
        let program = Program(name: "Programme")
        program.deletedAt = old(200)
        context.insert(program)
        try context.save()

        XCTAssertEqual(try TombstonePurge.run(context: context, now: now).total, 1)
        XCTAssertEqual(try TombstonePurge.run(context: context, now: now).total, 0)
    }

    /// La purge est journalisée : sans trace, une disparition de données au
    /// démarrage serait impossible à expliquer après coup.
    func testAPurgeLeavesATraceInTheDiagnosticsJournal() throws {
        let program = Program(name: "Programme")
        program.deletedAt = old(200)
        context.insert(program)
        try context.save()

        _ = try TombstonePurge.run(context: context, now: now)
        XCTAssertEqual(DiagnosticsCenter.events.first?.code, "store.tombstones.purged")
    }

    /// Garde-fou de couverture : un modèle synchronisé ajouté au schéma sans
    /// être inscrit dans la purge verrait ses tombstones s'accumuler à vie.
    func testEveryTombstonedModelOfTheSchemaIsCovered() {
        let tombstoned = MuscuCurrentSchema.models
            .filter { $0 is any SyncTombstoned.Type }
            .map { String(describing: $0) }
        XCTAssertFalse(tombstoned.isEmpty, "Le filtre de conformité doit trouver quelque chose")
        XCTAssertEqual(
            Set(tombstoned),
            TombstonePurge.coveredModelNames,
            "Un modèle portant `deletedAt` n'est pas purgé, ou la liste cite un modèle disparu"
        )
    }

    /// Un store sans aucune suppression ne doit rien écrire du tout : la
    /// purge ne doit pas réveiller le disque à chaque démarrage.
    func testAnUntouchedStoreProducesNoWrite() throws {
        let report = try TombstonePurge.run(context: context, now: now)
        XCTAssertEqual(report.total, 0)
        XCTAssertTrue(DiagnosticsCenter.events.isEmpty)
    }
}
