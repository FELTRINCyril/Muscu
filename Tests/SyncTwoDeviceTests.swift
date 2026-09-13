import XCTest
import SwiftData
import MuscuEngine
@testable import Muscu

/// Scénario à deux appareils : c'est le jalon de la phase 5.
///
/// Deux stores SwiftData distincts partagent un même « serveur » en mémoire.
/// On y rejoue ce qui casse réellement une synchronisation : travail hors
/// ligne, ordre d'arrivée inversé, rejeu, suppression concurrente,
/// modification concurrente et changement de compte.
@MainActor
final class SyncTwoDeviceTests: XCTestCase {
    private var transport: InMemorySyncTransport!
    private var phone: ModelContainer!
    private var tablet: ModelContainer!
    private var phoneSync: SyncService!
    private var tabletSync: SyncService!

    private var phoneContext: ModelContext { phone.mainContext }
    private var tabletContext: ModelContext { tablet.mainContext }

    override func setUpWithError() throws {
        transport = InMemorySyncTransport()
        phone = try TestStore.makeContainer()
        tablet = try TestStore.makeContainer()
        phoneSync = SyncService(modelContext: phone.mainContext, transport: transport)
        tabletSync = SyncService(modelContext: tablet.mainContext, transport: transport)
        phoneSync.setEnabled(true)
        tabletSync.setEnabled(true)
    }

    override func tearDownWithError() throws {
        phoneSync = nil
        tabletSync = nil
        phone = nil
        tablet = nil
        transport = nil
    }

    // MARK: - Fabriques

    @discardableResult
    private func addProgram(to context: ModelContext, name: String, id: UUID = UUID()) -> Program {
        let exercise = PrescribedExercise(
            exerciseId: "bench",
            displayName: "Développé couché",
            orderIndex: 0,
            sets: 3,
            repsLower: 8,
            repsUpper: 12,
            restSeconds: 90
        )
        let session = ProgramSession(name: "Push", orderIndex: 0, exercises: [exercise])
        let program = Program(id: id, name: name, sessions: [session])
        session.program = program
        exercise.session = session
        context.insert(program)
        try? context.save()
        return program
    }

    @discardableResult
    private func addMeasurement(to context: ModelContext, value: Double, id: UUID = UUID()) -> BodyMeasurement {
        let measurement = BodyMeasurement(
            id: id,
            kindRaw: BodyMeasurementKind.bodyweight.rawValue,
            value: value
        )
        context.insert(measurement)
        try? context.save()
        return measurement
    }

    /// Instant postérieur à la création des entités. Les modèles naissent
    /// avec `updatedAt = maintenant` : une modification doit donc porter une
    /// date ultérieure, sinon la fusion la traite — à raison — comme obsolète.
    private func later(_ seconds: TimeInterval) -> Date {
        Date.now.addingTimeInterval(seconds)
    }

    private func syncAll() async {
        await phoneSync.synchronize()
        await tabletSync.synchronize()
        await phoneSync.synchronize()
    }

    // MARK: - Aller simple

    func testProgramCreatedOnPhoneReachesTabletExactlyOnce() async throws {
        let program = addProgram(to: phoneContext, name: "PPL")
        phoneSync.enqueue(kind: .program, identifier: program.id, updatedAt: program.updatedAt)

        await syncAll()

        let programs = try tabletContext.fetch(FetchDescriptor<Program>())
        XCTAssertEqual(programs.count, 1)
        XCTAssertEqual(programs.first?.name, "PPL")
        XCTAssertEqual(programs.first?.orderedSessions.first?.orderedExercises.count, 1)
    }

    /// Critère de la roadmap : une séance créée hors ligne apparaît **une
    /// seule fois** sur les autres appareils, même après plusieurs cycles.
    func testRepeatedSyncNeverDuplicates() async throws {
        let program = addProgram(to: phoneContext, name: "PPL")
        phoneSync.enqueue(kind: .program, identifier: program.id, updatedAt: program.updatedAt)

        for _ in 0..<4 { await syncAll() }

        XCTAssertEqual(try tabletContext.fetchCount(FetchDescriptor<Program>()), 1)
        XCTAssertEqual(try phoneContext.fetchCount(FetchDescriptor<Program>()), 1)
        XCTAssertEqual(try tabletContext.fetchCount(FetchDescriptor<ProgramSession>()), 1)
    }

    // MARK: - Hors ligne

    /// Le travail fait hors ligne n'est jamais perdu : il part au retour du
    /// réseau.
    func testOfflineWorkIsQueuedThenDelivered() async throws {
        await transport.setOffline(true)

        let measurement = addMeasurement(to: phoneContext, value: 78.5)
        phoneSync.enqueue(kind: .bodyMeasurement, identifier: measurement.id, updatedAt: measurement.updatedAt)
        await phoneSync.synchronize()

        XCTAssertEqual(phoneSync.status.pendingCount, 1, "La modification reste en file d'attente")
        XCTAssertEqual(phoneSync.status.lastFailure, .network)
        XCTAssertEqual(try tabletContext.fetchCount(FetchDescriptor<BodyMeasurement>()), 0)

        await transport.setOffline(false)
        await syncAll()

        XCTAssertEqual(phoneSync.status.pendingCount, 0)
        XCTAssertEqual(try tabletContext.fetchCount(FetchDescriptor<BodyMeasurement>()), 1)
    }

    /// Une panne réseau ne supprime jamais de données locales.
    func testFailureNeverDeletesLocalData() async throws {
        let program = addProgram(to: phoneContext, name: "PPL")
        phoneSync.enqueue(kind: .program, identifier: program.id, updatedAt: program.updatedAt)

        await transport.setForcedFailure(.quotaExceeded)
        await phoneSync.synchronize()

        XCTAssertEqual(phoneSync.status.lastFailure, .quotaExceeded)
        XCTAssertEqual(try phoneContext.fetchCount(FetchDescriptor<Program>()), 1)
        XCTAssertEqual(phoneSync.status.pendingCount, 1)
    }

    /// Une erreur de compte ne réinitialise rien : elle désactive seulement
    /// la synchronisation.
    func testAccountErrorDisablesSyncWithoutTouchingData() async throws {
        addProgram(to: phoneContext, name: "PPL")
        await transport.setAccountFingerprint(nil)

        await phoneSync.synchronize()

        XCTAssertEqual(phoneSync.status.lastFailure, .accountUnavailable)
        XCTAssertEqual(try phoneContext.fetchCount(FetchDescriptor<Program>()), 1)
    }

    /// Changer de compte iCloud ne fusionne pas les données d'un autre
    /// compte : la synchronisation se désactive et attend une décision.
    func testAccountChangeStopsSyncInsteadOfMerging() async throws {
        let program = addProgram(to: phoneContext, name: "PPL")
        phoneSync.enqueue(kind: .program, identifier: program.id, updatedAt: program.updatedAt)
        await phoneSync.synchronize()
        XCTAssertNil(phoneSync.status.lastFailure)

        await transport.setAccountFingerprint("un-autre-compte")
        await phoneSync.synchronize()

        XCTAssertEqual(phoneSync.status.lastFailure, .accountUnavailable)
        XCTAssertFalse(phoneSync.status.isEnabled, "La synchronisation doit s'arrêter, pas fusionner")
        XCTAssertEqual(try phoneContext.fetchCount(FetchDescriptor<Program>()), 1)
    }

    // MARK: - Suppressions

    /// Une suppression faite hors ligne se propage vraiment.
    func testDeletionPropagatesToTheOtherDevice() async throws {
        let measurement = addMeasurement(to: phoneContext, value: 80)
        phoneSync.enqueue(kind: .bodyMeasurement, identifier: measurement.id, updatedAt: measurement.updatedAt)
        await syncAll()
        XCTAssertEqual(try tabletContext.fetchCount(FetchDescriptor<BodyMeasurement>()), 1)

        measurement.deletedAt = .now
        measurement.updatedAt = .now
        try phoneContext.save()
        phoneSync.enqueue(kind: .bodyMeasurement, identifier: measurement.id, updatedAt: measurement.updatedAt)
        await syncAll()

        XCTAssertEqual(try tabletContext.fetchCount(FetchDescriptor<BodyMeasurement>()), 0)
    }

    /// Une suppression plus ANCIENNE qu'une modification concurrente ne
    /// gagne pas : la donnée modifiée survit.
    func testOlderDeletionDoesNotBeatANewerEdit() async throws {
        let identifier = UUID()
        let phoneMeasurement = addMeasurement(to: phoneContext, value: 80, id: identifier)
        phoneSync.enqueue(kind: .bodyMeasurement, identifier: identifier, updatedAt: phoneMeasurement.updatedAt)
        await syncAll()

        // La tablette supprime, le téléphone modifie plus tard.
        let tabletMeasurement = try XCTUnwrap(tabletContext.fetch(FetchDescriptor<BodyMeasurement>()).first)
        tabletMeasurement.deletedAt = later(10)
        tabletMeasurement.updatedAt = later(10)
        try tabletContext.save()
        tabletSync.enqueue(kind: .bodyMeasurement, identifier: identifier, updatedAt: tabletMeasurement.updatedAt)

        phoneMeasurement.value = 79
        phoneMeasurement.updatedAt = later(20)
        try phoneContext.save()
        phoneSync.enqueue(kind: .bodyMeasurement, identifier: identifier, updatedAt: phoneMeasurement.updatedAt)

        await tabletSync.synchronize()
        await phoneSync.synchronize()
        await tabletSync.synchronize()

        let remaining = try tabletContext.fetch(FetchDescriptor<BodyMeasurement>()).filter { $0.deletedAt == nil }
        XCTAssertEqual(remaining.count, 1, "La modification plus récente doit survivre à la suppression")
        XCTAssertEqual(remaining.first?.value, 79)
    }

    // MARK: - Conflits

    /// Deux modifications concurrentes d'un programme produisent un conflit
    /// VISIBLE, et aucune version n'est perdue.
    func testConcurrentProgramEditsProduceAVisibleConflict() async throws {
        let identifier = UUID()
        let program = addProgram(to: phoneContext, name: "Origine", id: identifier)
        phoneSync.enqueue(kind: .program, identifier: identifier, updatedAt: program.updatedAt)
        await syncAll()
        XCTAssertEqual(try tabletContext.fetchCount(FetchDescriptor<Program>()), 1)

        // Chaque appareil renomme le programme de son côté.
        let tabletProgram = try XCTUnwrap(tabletContext.fetch(FetchDescriptor<Program>()).first)
        tabletProgram.name = "Version tablette"
        tabletProgram.updatedAt = later(10)
        try tabletContext.save()
        tabletSync.enqueue(kind: .program, identifier: identifier, updatedAt: tabletProgram.updatedAt)
        await tabletSync.synchronize()

        program.name = "Version téléphone"
        program.updatedAt = later(20)
        try phoneContext.save()
        phoneSync.enqueue(kind: .program, identifier: identifier, updatedAt: program.updatedAt)
        await phoneSync.synchronize()

        XCTAssertEqual(phoneSync.conflicts.count, 1, "Le conflit doit être signalé")
        XCTAssertEqual(
            try phoneContext.fetch(FetchDescriptor<Program>()).first?.name,
            "Version téléphone",
            "La version locale ne doit pas être écrasée en silence"
        )
    }

    func testResolvingAConflictKeepingLocalClearsItAndRequeues() async throws {
        let identifier = UUID()
        let program = addProgram(to: phoneContext, name: "Origine", id: identifier)
        phoneSync.enqueue(kind: .program, identifier: identifier, updatedAt: program.updatedAt)
        await syncAll()

        let tabletProgram = try XCTUnwrap(tabletContext.fetch(FetchDescriptor<Program>()).first)
        tabletProgram.name = "Tablette"
        tabletProgram.updatedAt = later(10)
        try tabletContext.save()
        tabletSync.enqueue(kind: .program, identifier: identifier, updatedAt: tabletProgram.updatedAt)
        await tabletSync.synchronize()

        program.name = "Téléphone"
        program.updatedAt = later(20)
        try phoneContext.save()
        phoneSync.enqueue(kind: .program, identifier: identifier, updatedAt: program.updatedAt)
        await phoneSync.synchronize()

        let conflict = try XCTUnwrap(phoneSync.conflicts.first)
        phoneSync.resolveKeepingLocal(conflict)

        XCTAssertTrue(phoneSync.conflicts.isEmpty)
        XCTAssertEqual(phoneSync.status.pendingCount, 1)
    }

    // MARK: - Historique immuable

    /// Une séance terminée ne peut pas être réécrite par un autre appareil.
    func testCompletedSessionIsNeverRewrittenByTheOtherDevice() async throws {
        let identifier = UUID()
        let set = CompletedSet(
            exerciseId: "bench",
            displayName: "Développé",
            orderIndex: 0,
            setIndex: 0,
            weight: 80,
            reps: 8
        )
        let session = CompletedSession(
            id: identifier,
            programName: "PPL",
            sessionName: "Push",
            durationSeconds: 3_600,
            sets: [set]
        )
        phoneContext.insert(session)
        try phoneContext.save()
        phoneSync.enqueue(kind: .completedSession, identifier: identifier, updatedAt: session.updatedAt)
        await syncAll()

        // La tablette tente de modifier l'historique.
        let tabletSession = try XCTUnwrap(tabletContext.fetch(FetchDescriptor<CompletedSession>()).first)
        tabletSession.sessionName = "Modifiée"
        tabletSession.updatedAt = later(30)
        try tabletContext.save()
        tabletSync.enqueue(kind: .completedSession, identifier: identifier, updatedAt: tabletSession.updatedAt)
        await tabletSync.synchronize()
        await phoneSync.synchronize()

        XCTAssertEqual(
            try phoneContext.fetch(FetchDescriptor<CompletedSession>()).first?.sessionName,
            "Push",
            "L'historique terminé est immuable"
        )
    }

    // MARK: - Diagnostic

    /// Le diagnostic exportable ne doit contenir aucune donnée métier.
    func testDiagnosticContainsNoPersonalData() async throws {
        let program = addProgram(to: phoneContext, name: "Mon programme secret")
        addMeasurement(to: phoneContext, value: 78.5)
        phoneSync.enqueue(kind: .program, identifier: program.id, updatedAt: program.updatedAt)

        let report = phoneSync.diagnosticReport()

        XCTAssertFalse(report.contains("Mon programme secret"))
        XCTAssertFalse(report.contains("78.5"))
        XCTAssertFalse(report.contains("Développé"))
        XCTAssertTrue(report.contains("Éléments en attente : 1"))
        XCTAssertTrue(report.contains("Version du schéma"))
    }

    // MARK: - Désactivation

    /// Désactiver la synchronisation ne supprime rien et n'envoie rien.
    func testDisablingSyncKeepsEverythingLocal() async throws {
        phoneSync.setEnabled(false)
        let program = addProgram(to: phoneContext, name: "Local seulement")
        phoneSync.enqueue(kind: .program, identifier: program.id, updatedAt: program.updatedAt)

        await phoneSync.synchronize()

        let storedCount = await transport.storedCount
        XCTAssertEqual(storedCount, 0, "Rien ne doit partir quand la synchronisation est désactivée")
        XCTAssertEqual(try phoneContext.fetchCount(FetchDescriptor<Program>()), 1)
        XCTAssertTrue(phoneSync.status.summary.contains("restent sur cet appareil"))
    }

    /// La première activation met tout l'existant en file d'attente.
    func testEnablingSyncQueuesExistingData() async throws {
        addProgram(to: phoneContext, name: "PPL")
        addMeasurement(to: phoneContext, value: 80)

        try phoneSync.enqueueEverything()

        XCTAssertGreaterThanOrEqual(phoneSync.status.pendingCount, 2)
        await syncAll()
        XCTAssertEqual(try tabletContext.fetchCount(FetchDescriptor<Program>()), 1)
        XCTAssertEqual(try tabletContext.fetchCount(FetchDescriptor<BodyMeasurement>()), 1)
    }
}

/// Sauvegarde de sécurité et modes d'import : remplacer des données ne doit
/// jamais être irréversible.
@MainActor
final class BackupAndImportModeTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUpWithError() throws {
        container = try TestStore.makeContainer()
        try? FileManager.default.removeItem(at: BackupService.directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: BackupService.directory)
        container = nil
    }

    private func addProgram(name: String) {
        context.insert(Program(name: name))
        try? context.save()
    }

    func testMergeKeepsExistingDataAndAddsWhatIsMissing() throws {
        addProgram(name: "Existant")
        let source = try TestStore.makeContainer()
        source.mainContext.insert(Program(name: "Importé"))
        try source.mainContext.save()
        let data = try ExportImport.exportAll(context: source.mainContext)

        let result = try ExportImport.importAll(data: data, context: context, mode: .merge)

        XCTAssertNil(result.safetyBackup, "Une fusion n'efface rien : pas de sauvegarde nécessaire")
        let names = try context.fetch(FetchDescriptor<Program>()).map(\.name).sorted()
        XCTAssertEqual(names, ["Existant", "Importé"])
    }

    /// Remplacer crée une sauvegarde AVANT d'effacer, et cette sauvegarde
    /// contient bien les données d'origine.
    func testReplaceCreatesARestorableSafetyBackup() throws {
        addProgram(name: "À écraser")
        let source = try TestStore.makeContainer()
        source.mainContext.insert(Program(name: "Nouveau"))
        try source.mainContext.save()
        let data = try ExportImport.exportAll(context: source.mainContext)

        let result = try ExportImport.importAll(data: data, context: context, mode: .replace)

        let backup = try XCTUnwrap(result.safetyBackup)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
        XCTAssertEqual(try context.fetch(FetchDescriptor<Program>()).map(\.name), ["Nouveau"])

        // La sauvegarde permet réellement de revenir en arrière.
        let restored = try TestStore.makeContainer()
        try ExportImport.importAll(data: try Data(contentsOf: backup), context: restored.mainContext)
        XCTAssertEqual(try restored.mainContext.fetch(FetchDescriptor<Program>()).map(\.name), ["À écraser"])
    }

    /// Un fichier illisible ne doit rien effacer : la validation passe avant
    /// la sauvegarde et la suppression.
    func testInvalidArchiveNeverDeletesAnything() throws {
        addProgram(name: "Intact")
        let garbage = Data("pas du json".utf8)

        XCTAssertThrowsError(try ExportImport.importAll(data: garbage, context: context, mode: .replace))

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Program>()), 1)
        XCTAssertTrue(BackupService.existingBackups().isEmpty, "Aucune sauvegarde ne doit être créée pour un fichier invalide")
    }

    func testOldBackupsArePruned() throws {
        addProgram(name: "Programme")
        for index in 0..<(BackupService.retainedBackups + 3) {
            _ = try BackupService.createSafetyBackup(
                context: context,
                now: Date(timeIntervalSince1970: 1_750_000_000 + Double(index) * 60)
            )
        }
        XCTAssertEqual(BackupService.existingBackups().count, BackupService.retainedBackups)
    }
}
