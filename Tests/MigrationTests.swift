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

    // MARK: - V3 -> V4

    /// Ecrit un store avec le schema V3 FIGE, puis l'ouvre avec le schema
    /// courant. C'est le seul moyen de verifier l'etape V3 -> V4 telle
    /// qu'elle se produira sur l'appareil d'un utilisateur deja a jour.
    func testV3StoreMigratesToV4WithoutLoss() throws {
        let url = temporaryDirectory.appendingPathComponent("v3-written.store")

        do {
            let container = try ModelContainer(
                for: Schema(versionedSchema: MuscuSchemaV3.self),
                configurations: ModelConfiguration(url: url)
            )
            let context = ModelContext(container)

            let program = MuscuSchemaV3.Program(name: "Programme v3", notes: "Avant v4", isActive: true)
            context.insert(program)

            let session = MuscuSchemaV3.ProgramSession(name: "Séance A", orderIndex: 0)
            session.program = program
            context.insert(session)

            let exercise = MuscuSchemaV3.PrescribedExercise(
                exerciseId: "bench",
                displayName: "Développé couché",
                orderIndex: 0,
                sets: 3,
                repsLower: 8,
                repsUpper: 10,
                restSeconds: 90
            )
            exercise.session = session
            context.insert(exercise)

            let completed = MuscuSchemaV3.CompletedSession(
                date: Date(timeIntervalSince1970: 1_700_000_000),
                programName: "Programme v3",
                sessionName: "Séance A",
                durationSeconds: 3_600
            )
            context.insert(completed)

            let plan = MuscuSchemaV3.TrainingPlan(name: "Plan v3")
            context.insert(plan)
            let block = MuscuSchemaV3.TrainingBlock(orderIndex: 0, name: "Accumulation")
            block.plan = plan
            context.insert(block)
            let week = MuscuSchemaV3.TrainingWeek(weekNumber: 1)
            week.block = block
            context.insert(week)
            let scheduled = MuscuSchemaV3.ScheduledWorkout(
                plannedDate: Date(timeIntervalSince1970: 1_700_100_000),
                displayName: "Séance A"
            )
            scheduled.week = week
            context.insert(scheduled)

            try context.save()
        }

        let container = try ModelContainer(
            for: Schema(versionedSchema: MuscuCurrentSchema.self),
            migrationPlan: MuscuMigrationPlan.self,
            configurations: ModelConfiguration(url: url)
        )
        let context = ModelContext(container)

        let program = try XCTUnwrap(try context.fetch(FetchDescriptor<Program>()).first)
        XCTAssertEqual(program.name, "Programme v3")
        XCTAssertEqual(program.notes, "Avant v4")
        XCTAssertEqual(program.orderedSessions.first?.orderedExercises.first?.displayName, "Développé couché")

        let completed = try XCTUnwrap(try context.fetch(FetchDescriptor<CompletedSession>()).first)
        XCTAssertEqual(completed.durationSeconds, 3_600)
        // Champs ajoutes en v4 : vides, jamais inventes.
        XCTAssertNil(completed.placeId)
        XCTAssertEqual(completed.importSource, "")

        let scheduled = try XCTUnwrap(try context.fetch(FetchDescriptor<ScheduledWorkout>()).first)
        XCTAssertEqual(scheduled.displayName, "Séance A")
        XCTAssertNil(scheduled.placeId)
        XCTAssertNil(scheduled.originalDate)

        // Les modeles introduits en v4 existent et sont vides.
        XCTAssertTrue(try context.fetch(FetchDescriptor<PlaceProfile>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PlanningSchedule>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SessionTemplate>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ExerciseLibraryEntry>()).isEmpty)

        let place = PlaceProfile(name: "Salle")
        context.insert(place)
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<PlaceProfile>()).count, 1)
    }

    // MARK: - V4 -> V5

    /// Ecrit un store avec le schema V4 FIGE, puis l'ouvre avec le schema
    /// courant : c'est l'etape que vivra un utilisateur deja a jour.
    func testV4StoreMigratesToV5WithoutLoss() throws {
        let url = temporaryDirectory.appendingPathComponent("v4-written.store")

        do {
            let container = try ModelContainer(
                for: Schema(versionedSchema: MuscuSchemaV4.self),
                configurations: ModelConfiguration(url: url)
            )
            let context = ModelContext(container)

            let program = MuscuSchemaV4.Program(name: "Programme v4", isActive: true)
            context.insert(program)

            let plan = MuscuSchemaV4.TrainingPlan(name: "Plan v4")
            context.insert(plan)

            let place = MuscuSchemaV4.PlaceProfile(name: "Salle v4")
            context.insert(place)

            let schedule = MuscuSchemaV4.PlanningSchedule(name: "Semaine type v4")
            context.insert(schedule)

            let completed = MuscuSchemaV4.CompletedSession(
                date: Date(timeIntervalSince1970: 1_700_000_000),
                programName: "Programme v4",
                sessionName: "Séance A",
                durationSeconds: 1_800
            )
            context.insert(completed)

            try context.save()
        }

        let container = try ModelContainer(
            for: Schema(versionedSchema: MuscuCurrentSchema.self),
            migrationPlan: MuscuMigrationPlan.self,
            configurations: ModelConfiguration(url: url)
        )
        let context = ModelContext(container)

        XCTAssertEqual(try context.fetch(FetchDescriptor<Program>()).first?.name, "Programme v4")
        XCTAssertEqual(try context.fetch(FetchDescriptor<PlaceProfile>()).first?.name, "Salle v4")
        XCTAssertEqual(try context.fetch(FetchDescriptor<PlanningSchedule>()).first?.name, "Semaine type v4")
        XCTAssertEqual(try context.fetch(FetchDescriptor<CompletedSession>()).first?.durationSeconds, 1_800)

        let plan = try XCTUnwrap(try context.fetch(FetchDescriptor<TrainingPlan>()).first)
        XCTAssertEqual(plan.name, "Plan v4")
        // Champs ajoutes en v5 : vides, jamais inventes.
        XCTAssertNil(plan.periodizationStyle)
        XCTAssertEqual(plan.deloadEveryWeeks, 0)

        XCTAssertTrue(try context.fetch(FetchDescriptor<ProgressPhoto>()).isEmpty)

        context.insert(ProgressPhoto(assetName: "photo.jpg"))
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<ProgressPhoto>()).count, 1)
    }

    // MARK: - V5 -> V6

    /// Écrit un store avec le schéma V5 FIGÉ, puis l'ouvre avec le schéma
    /// courant. C'est l'étape que vivra un utilisateur déjà à jour.
    func testV5StoreMigratesToV6WithoutLoss() throws {
        let url = temporaryDirectory.appendingPathComponent("v5-written.store")

        do {
            let container = try ModelContainer(
                for: Schema(versionedSchema: MuscuSchemaV5.self),
                configurations: ModelConfiguration(url: url)
            )
            let context = ModelContext(container)

            let program = MuscuSchemaV5.Program(name: "Programme v5", isActive: true)
            context.insert(program)

            let completed = MuscuSchemaV5.CompletedSession(
                date: Date(timeIntervalSince1970: 1_700_000_000),
                programName: "Programme v5",
                sessionName: "Séance A",
                durationSeconds: 2_400
            )
            context.insert(completed)

            // Une adaptation déjà acceptée AVANT l'ajout des champs
            // d'annulation : elle doit rester lisible, simplement non
            // annulable — exactement ce qu'elle était.
            let adaptation = MuscuSchemaV5.AdaptationEntry(
                exerciseId: "bench",
                displayName: "Développé couché",
                summary: "Intervalle 30 s → 35 s"
            )
            adaptation.decisionRaw = "accepted"
            context.insert(adaptation)

            let photo = MuscuSchemaV5.ProgressPhoto(assetName: "photo-v5.jpg")
            context.insert(photo)

            try context.save()
        }

        let container = try ModelContainer(
            for: Schema(versionedSchema: MuscuCurrentSchema.self),
            migrationPlan: MuscuMigrationPlan.self,
            configurations: ModelConfiguration(url: url)
        )
        let context = ModelContext(container)

        XCTAssertEqual(try context.fetch(FetchDescriptor<Program>()).first?.name, "Programme v5")
        XCTAssertEqual(try context.fetch(FetchDescriptor<CompletedSession>()).first?.durationSeconds, 2_400)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ProgressPhoto>()).first?.assetName, "photo-v5.jpg")

        let adaptation = try XCTUnwrap(try context.fetch(FetchDescriptor<AdaptationEntry>()).first)
        XCTAssertEqual(adaptation.summary, "Intervalle 30 s → 35 s")
        // Champs ajoutés en v6 : vides, jamais inventés.
        XCTAssertNil(adaptation.previousIntervalWork)
        XCTAssertNil(adaptation.previousIntervalRest)
        XCTAssertNil(adaptation.previousExerciseId)
        XCTAssertFalse(
            adaptation.canRevert,
            "Une adaptation enregistrée avant v6 reste non annulable : on n'invente pas ses valeurs d'avant"
        )

        // Et une NOUVELLE adaptation, elle, est annulable.
        let fresh = AdaptationEntry(
            decisionRaw: AdaptationDecision.accepted.rawValue,
            exerciseId: "burpees",
            displayName: "Burpees",
            previousIntervalWork: 30
        )
        context.insert(fresh)
        try context.save()
        XCTAssertTrue(fresh.canRevert)
    }

    // MARK: - V6 -> V7

    /// Écrit un store avec le schéma V6 FIGÉ, puis l'ouvre avec le schéma
    /// courant. Les dix attributs ajoutés en v7 doivent être ABSENTS (nil),
    /// jamais un zéro inventé, et les données existantes intactes.
    func testV6StoreMigratesToV7WithoutLoss() throws {
        let url = temporaryDirectory.appendingPathComponent("v6-written.store")
        let sessionId = UUID()
        let customId = UUID()

        do {
            let container = try ModelContainer(
                for: Schema(versionedSchema: MuscuSchemaV6.self),
                configurations: ModelConfiguration(url: url)
            )
            let context = ModelContext(container)

            let completed = MuscuSchemaV6.CompletedSession(
                id: sessionId,
                date: Date(timeIntervalSince1970: 1_700_000_000),
                programName: "Programme v6",
                sessionName: "Séance A",
                durationSeconds: 3_000,
                bodyweightKilograms: 80
            )
            let set = MuscuSchemaV6.CompletedSet(
                exerciseId: "bench",
                displayName: "Développé couché",
                orderIndex: 0,
                setIndex: 0,
                weight: 100,
                reps: 5
            )
            set.session = completed
            completed.sets = [set]
            context.insert(completed)

            context.insert(MuscuSchemaV6.CustomExercise(id: customId, name: "Curl maison"))
            context.insert(MuscuSchemaV6.ExerciseLibraryEntry(exerciseId: "bench", isFavorite: true))
            context.insert(MuscuSchemaV6.BodyMeasurement(value: 81.5, sourceRaw: "healthKit"))
            let adaptation = MuscuSchemaV6.AdaptationEntry(
                exerciseId: "burpees",
                displayName: "Burpees",
                previousIntervalWork: 30
            )
            context.insert(adaptation)

            try context.save()
        }

        let container = try ModelContainer(
            for: Schema(versionedSchema: MuscuCurrentSchema.self),
            migrationPlan: MuscuMigrationPlan.self,
            configurations: ModelConfiguration(url: url)
        )
        let context = ModelContext(container)

        let session = try XCTUnwrap(try context.fetch(FetchDescriptor<CompletedSession>()).first)
        XCTAssertEqual(session.id, sessionId)
        XCTAssertEqual(session.durationSeconds, 3_000)
        XCTAssertEqual(session.bodyweightKilograms, 80)
        XCTAssertNil(session.effortRating)
        XCTAssertNil(session.avgHeartRate)
        XCTAssertNil(session.maxHeartRate)
        XCTAssertNil(session.minHeartRate)
        XCTAssertNil(session.activeEnergyKcal)
        XCTAssertNil(session.editedAt)

        let set = try XCTUnwrap(session.sets.first)
        XCTAssertEqual(set.weight, 100)
        XCTAssertEqual(set.reps, 5)
        XCTAssertNil(set.actualRestSeconds, "Un repos non mesuré reste absent, pas zéro")

        let custom = try XCTUnwrap(try context.fetch(FetchDescriptor<CustomExercise>()).first)
        XCTAssertEqual(custom.id, customId)
        XCTAssertNil(custom.mergedIntoExerciseId)

        let entry = try XCTUnwrap(try context.fetch(FetchDescriptor<ExerciseLibraryEntry>()).first)
        XCTAssertTrue(entry.isFavorite)
        XCTAssertNil(entry.demoURL)

        let measurement = try XCTUnwrap(try context.fetch(FetchDescriptor<BodyMeasurement>()).first)
        XCTAssertEqual(measurement.value, 81.5)
        XCTAssertNil(measurement.healthSampleUUID)

        // Les champs v6 survivent à l'étape suivante.
        let migratedAdaptation = try XCTUnwrap(try context.fetch(FetchDescriptor<AdaptationEntry>()).first)
        XCTAssertEqual(migratedAdaptation.previousIntervalWork, 30)

        // Et les nouveaux champs s'écrivent puis se relisent.
        session.effortRating = 8
        session.avgHeartRate = 132
        session.activeEnergyKcal = 0
        set.actualRestSeconds = 95
        try context.save()
        let reread = try XCTUnwrap(try ModelContext(container).fetch(FetchDescriptor<CompletedSession>()).first)
        XCTAssertEqual(reread.effortRating, 8)
        XCTAssertEqual(reread.avgHeartRate, 132)
        XCTAssertEqual(reread.activeEnergyKcal, 0, "Zéro mesuré reste zéro, distinct d'une absence")
        XCTAssertEqual(reread.sets.first?.actualRestSeconds, 95)
    }

    // MARK: - V7 -> V8

    /// Écrit un store avec le schéma V7 FIGÉ (celui installé sur les
    /// appareils), puis l'ouvre avec le schéma courant. Une pyramide v7 garde
    /// ses paliers et ses bornes de repos et passe en mode adaptatif (aucun
    /// repos par palier inventé).
    func testV7StoreMigratesToV8WithoutLoss() throws {
        let url = temporaryDirectory.appendingPathComponent("v7-written.store")
        let exerciseId = UUID()

        do {
            let container = try ModelContainer(
                for: Schema(versionedSchema: MuscuSchemaV7.self),
                configurations: ModelConfiguration(url: url)
            )
            let context = ModelContext(container)
            let program = MuscuSchemaV7.Program(name: "Programme v7", isActive: true)
            let session = MuscuSchemaV7.ProgramSession(name: "Séance A", orderIndex: 0)
            let pyramid = MuscuSchemaV7.PrescribedExercise(
                id: exerciseId,
                exerciseId: "Pullups",
                displayName: "Tractions",
                orderIndex: 0,
                formatRaw: "pyramid",
                pyramidReps: [1, 2, 3, 4, 5, 6, 5, 4, 3, 2, 1],
                pyramidMinRest: 45,
                pyramidMaxRest: 150
            )
            pyramid.session = session
            session.exercises = [pyramid]
            session.program = program
            program.sessions = [session]
            context.insert(program)
            context.insert(MuscuSchemaV7.ActiveWorkout(programSessionId: UUID(), isFreeSession: true))
            try context.save()
        }

        let container = try ModelContainer(
            for: Schema(versionedSchema: MuscuCurrentSchema.self),
            migrationPlan: MuscuMigrationPlan.self,
            configurations: ModelConfiguration(url: url)
        )
        let context = ModelContext(container)

        let program = try XCTUnwrap(try context.fetch(FetchDescriptor<Program>()).first)
        XCTAssertEqual(program.name, "Programme v7")
        XCTAssertTrue(program.isActive)
        let pyramid = try XCTUnwrap(program.orderedSessions.first?.orderedExercises.first)
        XCTAssertEqual(pyramid.id, exerciseId)
        XCTAssertEqual(pyramid.format, .pyramid)
        XCTAssertEqual(pyramid.pyramidReps, [1, 2, 3, 4, 5, 6, 5, 4, 3, 2, 1])
        XCTAssertEqual(pyramid.pyramidMinRest, 45)
        XCTAssertEqual(pyramid.pyramidMaxRest, 150)
        XCTAssertEqual(pyramid.pyramidRestSeconds, [], "Une pyramide v7 reste en repos adaptatif")

        // Les champs v7 survivent à l'étape suivante.
        let active = try XCTUnwrap(try context.fetch(FetchDescriptor<ActiveWorkout>()).first)
        XCTAssertTrue(active.isFreeSession)

        // Le nouveau champ s'écrit puis se relit.
        pyramid.pyramidRestSeconds = Pyramid.normalizedRests([60, 90], stepCount: pyramid.pyramidReps.count)
        try context.save()
        let reread = try XCTUnwrap(try ModelContext(container).fetch(FetchDescriptor<PrescribedExercise>()).first)
        XCTAssertEqual(reread.pyramidRestSeconds.count, 11)
        XCTAssertEqual(reread.pyramidRestSeconds.prefix(2), [60, 90])
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
