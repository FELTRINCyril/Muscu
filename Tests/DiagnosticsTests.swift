import XCTest
import SwiftData
import MuscuEngine
@testable import Muscu

@MainActor
final class DiagnosticsCenterTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        DiagnosticsCenter.reset()
    }

    override func tearDown() async throws {
        DiagnosticsCenter.reset()
        try await super.tearDown()
    }

    func testTheJournalIsOnByDefaultAndRecords() {
        XCTAssertTrue(DiagnosticsCenter.isEnabled, "Sans journal, un échec vécu ne laisse aucune trace")
        DiagnosticsCenter.record(.store, .failure, code: "store.save.failed", detail: "Sauvegarde")
        XCTAssertEqual(DiagnosticsCenter.events.count, 1)
        XCTAssertEqual(DiagnosticsCenter.events.first?.code, "store.save.failed")
    }

    /// Couper le journal doit AUSSI effacer ce qu'il a retenu : sinon la
    /// désactivation ne veut rien dire.
    func testDisablingStopsRecordingAndErasesWhatWasKept() {
        DiagnosticsCenter.record(.sync, .warning, code: "sync.retry")
        XCTAssertFalse(DiagnosticsCenter.events.isEmpty)

        DiagnosticsCenter.isEnabled = false
        XCTAssertTrue(DiagnosticsCenter.events.isEmpty, "Désactiver le journal doit effacer les lignes déjà écrites")

        DiagnosticsCenter.record(.sync, .failure, code: "sync.cycle.failed")
        XCTAssertTrue(DiagnosticsCenter.events.isEmpty, "Un journal éteint n'enregistre rien")
    }

    func testTheJournalNeverGrowsBeyondItsCapacity() {
        for index in 0..<(DiagnosticsBuffer.defaultCapacity + 50) {
            DiagnosticsCenter.record(.store, .info, code: "evenement.\(index)")
        }
        XCTAssertEqual(DiagnosticsCenter.events.count, DiagnosticsBuffer.defaultCapacity)
        XCTAssertEqual(DiagnosticsCenter.events.first?.code, "evenement.\(DiagnosticsBuffer.defaultCapacity + 49)")
    }

    /// Le point de sauvegarde unique alimente le journal : c'est ce qui
    /// garantit qu'aucun échec de stockage ne passe inaperçu.
    func testAFailedSaveIsRecorded() throws {
        let container = try TestStore.makeContainer()
        let context = ModelContext(container)
        PersistenceSupport.report(
            NSError(domain: "test", code: 42, userInfo: [NSLocalizedDescriptionKey: "Disque plein"]),
            action: "Suppression de Historique des séances"
        )
        XCTAssertEqual(DiagnosticsCenter.events.first?.code, "store.operation.failed")
        XCTAssertEqual(DiagnosticsCenter.events.first?.category, .store)
        _ = context
    }

    func testTheEnvironmentNeverCarriesTheDeviceName() {
        let environment = DiagnosticsCenter.environment
        XCTAssertFalse(environment.deviceModel.isEmpty)
        // `UIDevice.current.name` contient tres souvent un prenom : le
        // modele materiel, lui, est generique.
        XCTAssertNotEqual(environment.deviceModel, UIDevice.current.name)
    }

    func testTheStoreHealthReportsCountsAndSchema() throws {
        let container = try TestStore.makeContainer()
        let context = ModelContext(container)
        context.insert(CompletedSession(programName: "Programme", sessionName: "Séance A"))
        try context.save()

        let health = DiagnosticsHealth.snapshot(context: context, migrationSucceeded: true)
        XCTAssertEqual(health.schemaVersion, Int(MuscuCurrentSchema.versionIdentifier.major))
        XCTAssertEqual(health.entityCounts["Séances terminées"], 1)
        XCTAssertEqual(health.pendingSyncOperations, 0)

        // Le nom de la séance ne doit jamais atteindre le rapport.
        let text = DiagnosticReportBuilder.text(
            environment: DiagnosticsCenter.environment,
            health: health,
            events: DiagnosticsCenter.events,
            generatedAt: .now
        )
        XCTAssertFalse(text.contains("Séance A"))
    }

    /// La suppression totale doit réellement tout effacer, y compris ce qui
    /// ne vit pas dans SwiftData.
    func testDeletingEverythingAlsoClearsTheJournal() throws {
        let container = try TestStore.makeContainer()
        let context = ModelContext(container)
        DiagnosticsCenter.record(.store, .failure, code: "store.save.failed")
        XCTAssertFalse(DiagnosticsCenter.events.isEmpty)

        let report = try DataDeletion.deleteEverything(context: context)
        XCTAssertTrue(DiagnosticsCenter.events.isEmpty)
        XCTAssertEqual(report.countsByModel["lignes de journal"], 1)
    }
}
