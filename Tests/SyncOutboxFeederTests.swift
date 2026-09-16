import XCTest
import SwiftData
import MuscuEngine
@testable import Muscu

/// La file d'attente de synchronisation se remplit-elle vraiment ?
///
/// `SyncService.enqueue` existait, était testé, et n'était appelé par **aucun
/// code applicatif** : ni la fin d'une séance, ni l'édition d'un programme,
/// ni une mesure. Le jour où un conteneur CloudKit sera branché, seule une
/// réinscription complète aurait fait partir quelque chose.
@MainActor
final class SyncOutboxFeederTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        container = try TestStore.makeContainer()
        context = ModelContext(container)
        SyncOutboxFeeder.isEnabled = false
    }

    override func tearDown() async throws {
        SyncOutboxFeeder.isEnabled = false
        container = nil
        context = nil
        try await super.tearDown()
    }

    private var outboxCount: Int {
        SyncService.state(in: context).outbox.count
    }

    /// Tant que la synchronisation est éteinte — c'est-à-dire toujours,
    /// aujourd'hui — rien ne doit être relevé ni écrit.
    func testNothingIsQueuedWhileSyncIsOff() {
        context.insert(Program(name: "Programme"))
        XCTAssertTrue(PersistenceSupport.save(context, action: "Test"))
        XCTAssertEqual(outboxCount, 0)
    }

    func testALocalWriteFillsTheOutboxWhenSyncIsOn() {
        SyncOutboxFeeder.isEnabled = true

        context.insert(Program(name: "Programme"))
        XCTAssertTrue(PersistenceSupport.save(context, action: "Création d'un programme"))
        XCTAssertEqual(outboxCount, 1, "Une écriture locale doit partir à la prochaine synchronisation")
    }

    /// Le cas qui compte vraiment : une séance terminée.
    func testAFinishedWorkoutIsQueued() {
        SyncOutboxFeeder.isEnabled = true

        let session = CompletedSession(programName: "P", sessionName: "Séance A")
        context.insert(session)
        XCTAssertTrue(PersistenceSupport.save(context, action: "Fin de séance"))

        let outbox = SyncService.state(in: context).outbox
        XCTAssertEqual(outbox.count, 1)
        XCTAssertTrue(
            outbox.ready(at: .now).contains { $0.identifier == session.id },
            "La séance terminée doit être identifiable dans la file"
        )
    }

    /// Une entité modifiée deux fois ne doit occuper qu'une place : la file
    /// décrit ce qu'il reste à envoyer, pas un journal.
    func testTheSameEntityIsNotQueuedTwice() {
        SyncOutboxFeeder.isEnabled = true

        let program = Program(name: "Programme")
        context.insert(program)
        _ = PersistenceSupport.save(context, action: "Création")

        program.name = "Programme renommé"
        program.touch()
        _ = PersistenceSupport.save(context, action: "Renommage")

        XCTAssertEqual(outboxCount, 1)
    }

    /// Alimenter la file écrit elle-même dans le store : ce second
    /// enregistrement ne doit pas relancer le mécanisme indéfiniment.
    func testFeedingTheOutboxDoesNotFeedItself() {
        SyncOutboxFeeder.isEnabled = true

        context.insert(BodyMeasurement(value: 80))
        _ = PersistenceSupport.save(context, action: "Mesure")

        // Une seule entrée : celle de la mesure, pas celle de `SyncState`.
        XCTAssertEqual(outboxCount, 1)
    }
}
