import XCTest
import SwiftData
import MuscuEngine
@testable import Muscu

/// Ouvre des stores SwiftData figes, representatifs des versions reellement
/// presentes sur disque avant le schema v3, et verifie qu'aucune donnee
/// n'est perdue apres migration.
///
/// Les fixtures sont des fichiers binaires generes une fois (cf.
/// `docs/decisions/0001-schema-v3.md`) et ne doivent jamais etre
/// regeneres depuis le schema courant : ce sont des temoins.
@MainActor
final class MigrationTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("muscu-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory { try? FileManager.default.removeItem(at: temporaryDirectory) }
    }

    // MARK: - Ouverture

    /// Copie le fixture dans un dossier temporaire : le fichier de reference
    /// du bundle de test ne doit jamais etre modifie par une migration.
    private func copiedFixture(named name: String) throws -> URL {
        let bundle = Bundle(for: MigrationTests.self)
        let source = try XCTUnwrap(
            bundle.url(forResource: name, withExtension: "store"),
            "Fixture \(name).store absent du bundle de test"
        )
        let destination = temporaryDirectory.appendingPathComponent("\(name).store")
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    private func migratedContainer(fixture name: String) throws -> (ModelContainer, URL) {
        let url = try copiedFixture(named: name)
        let container = try ModelContainer(
            for: Schema(versionedSchema: MuscuCurrentSchema.self),
            migrationPlan: MuscuMigrationPlan.self,
            configurations: ModelConfiguration(url: url)
        )
        return (container, url)
    }

    // MARK: - Tests

    func testPreChangeStoreMigratesWithoutLoss() throws {
        let (container, _) = try migratedContainer(fixture: "v1-prechange")
        let context = ModelContext(container)

        let programs = try context.fetch(FetchDescriptor<Program>())
        XCTAssertEqual(programs.count, 1)
        let program = try XCTUnwrap(programs.first)
        XCTAssertEqual(program.name, "Programme historique")
        XCTAssertEqual(program.notes, "Cree avant la migration")
        XCTAssertTrue(program.isActive)
        XCTAssertEqual(program.sessions.count, 2)

        let sessionA = try XCTUnwrap(program.orderedSessions.first)
        XCTAssertEqual(sessionA.name, "Séance A")
        XCTAssertTrue(sessionA.warmupEnabled)
        XCTAssertEqual(sessionA.orderedExercises.map(\.displayName), ["Développé couché", "Tractions"])

        let bench = try XCTUnwrap(sessionA.orderedExercises.first)
        XCTAssertEqual(bench.format, .classic)
        XCTAssertEqual(bench.sets, 4)
        XCTAssertEqual(bench.repsLower, 6)
        XCTAssertEqual(bench.repsUpper, 8)
        XCTAssertEqual(bench.restSeconds, 120)
        XCTAssertEqual(bench.percentOneRepMax, 75)
        XCTAssertEqual(bench.notes, "Garder les omoplates serrées")

        let pullups = sessionA.orderedExercises[1]
        XCTAssertEqual(pullups.format, .pyramid)
        XCTAssertEqual(pullups.pyramidReps, [2, 4, 6, 4, 2])

        let history = try context.fetch(FetchDescriptor<CompletedSession>())
        XCTAssertEqual(history.count, 1)
        let completed = try XCTUnwrap(history.first)
        XCTAssertEqual(completed.durationSeconds, 3_600)
        XCTAssertEqual(completed.sets.count, 3)
        XCTAssertEqual(completed.programId, program.id)
        XCTAssertEqual(completed.programSessionId, sessionA.id)

        let records = try context.fetch(FetchDescriptor<ExerciseRecord>())
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records.first(where: { $0.exerciseId == "Barbell_Bench_Press_-_Medium_Grip" })?.oneRepMax, 96)
        XCTAssertEqual(records.first(where: { $0.exerciseId == "Pullups" })?.maxReps, 14)

        XCTAssertEqual(try context.fetch(FetchDescriptor<CustomExercise>()).count, 1)

        let active = try context.fetch(FetchDescriptor<ActiveWorkout>())
        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(active.first?.loggedSets.count, 1)
    }

    /// Le tout premier schema distribue (sans `loadTypeRaw` sur les series,
    /// sans identifiants de programme sur l'historique) doit rester ouvrable.
    func testInitialStoreMigratesWithoutLoss() throws {
        let (container, _) = try migratedContainer(fixture: "v1-initial")
        let context = ModelContext(container)

        XCTAssertEqual(try context.fetch(FetchDescriptor<Program>()).count, 1)
        let completed = try XCTUnwrap(try context.fetch(FetchDescriptor<CompletedSession>()).first)
        XCTAssertEqual(completed.sets.count, 3)
        // Les series anterieures au typage de charge conservent `unknown`,
        // qui n'est jamais reinterprete silencieusement.
        XCTAssertTrue(completed.sets.allSatisfy { $0.loadType == .unknown })
        XCTAssertNil(completed.programId)
    }

    /// Les champs v3 absents du store d'origine prennent une valeur neutre,
    /// jamais une valeur inventee.
    func testMigratedDataGetsNeutralDefaultsForNewFields() throws {
        let (container, _) = try migratedContainer(fixture: "v1-prechange")
        let context = ModelContext(container)

        let bench = try XCTUnwrap(
            try context.fetch(FetchDescriptor<PrescribedExercise>())
                .first { $0.exerciseId == "Barbell_Bench_Press_-_Medium_Grip" }
        )
        XCTAssertNil(bench.tempo)
        XCTAssertNil(bench.targetEffort)
        XCTAssertNil(bench.progressionRule)
        XCTAssertNil(bench.prescribedLoadKind)
        XCTAssertNil(bench.group)
        XCTAssertEqual(bench.sideConvention, .bilateral)

        let warmup = try XCTUnwrap(
            try context.fetch(FetchDescriptor<CompletedSet>()).first { $0.isWarmup }
        )
        // `role` retombe sur `isWarmup` tant qu'aucun role explicite n'a ete
        // enregistre : aucune donnee n'est reecrite pour autant.
        XCTAssertEqual(warmup.role, .warmup)
        XCTAssertEqual(warmup.roleRaw, "")
        XCTAssertEqual(warmup.roundIndex, 0)
        XCTAssertEqual(warmup.subSetIndex, 0)
        XCTAssertNil(warmup.effort)
    }

    /// Les nouvelles entites sont vides apres migration, et insérables.
    func testNewEntitiesAreEmptyThenUsable() throws {
        let (container, _) = try migratedContainer(fixture: "v1-prechange")
        let context = ModelContext(container)

        XCTAssertTrue(try context.fetch(FetchDescriptor<AthleteProfile>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<BodyMeasurement>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ReadinessEntry>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<TrainingPlan>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ExerciseGroup>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PersonalBest>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<HealthWorkoutLink>()).isEmpty)

        let profile = AthleteProfile(firstName: "Test", bodyweightKilograms: 78)
        context.insert(profile)
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<AthleteProfile>()).count, 1)
    }

    /// La normalisation post-migration reprend les records existants sous
    /// forme de records types, sans supprimer les originaux ni doublonner.
    func testSchemaUpgradeBackfillsPersonalBestsIdempotently() throws {
        let (container, _) = try migratedContainer(fixture: "v1-prechange")
        let context = ModelContext(container)

        try SchemaUpgrade.run(context: context, force: true)
        let bests = try context.fetch(FetchDescriptor<PersonalBest>())
        XCTAssertEqual(bests.count, 2)
        XCTAssertEqual(bests.first(where: { $0.kind == .estimatedOneRepMax })?.value, 96)
        XCTAssertEqual(bests.first(where: { $0.kind == .maxReps })?.value, 14)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ExerciseRecord>()).count, 2)

        try SchemaUpgrade.run(context: context, force: true)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PersonalBest>()).count, 2)
    }

    /// Ouvrir deux fois de suite ne doit ni echouer ni dupliquer.
    func testReopeningMigratedStoreIsStable() throws {
        let url = try copiedFixture(named: "v1-prechange")
        for _ in 0..<2 {
            let container = try ModelContainer(
                for: Schema(versionedSchema: MuscuCurrentSchema.self),
                migrationPlan: MuscuMigrationPlan.self,
                configurations: ModelConfiguration(url: url)
            )
            let context = ModelContext(container)
            XCTAssertEqual(try context.fetch(FetchDescriptor<Program>()).count, 1)
            XCTAssertEqual(try context.fetch(FetchDescriptor<CompletedSession>()).count, 1)
        }
    }

    /// Un store corrompu ne doit pas faire disparaitre le fichier d'origine :
    /// l'ouverture echoue proprement et les octets restent sur disque.
    func testCorruptedStoreFailsWithoutDestroyingTheFile() throws {
        let url = temporaryDirectory.appendingPathComponent("corrupted.store")
        let garbage = Data(repeating: 0x42, count: 4_096)
        try garbage.write(to: url)

        XCTAssertThrowsError(
            try ModelContainer(
                for: Schema(versionedSchema: MuscuCurrentSchema.self),
                migrationPlan: MuscuMigrationPlan.self,
                configurations: ModelConfiguration(url: url)
            )
        )
        XCTAssertEqual(try Data(contentsOf: url), garbage, "Le store d'origine doit rester intact")
    }
}
