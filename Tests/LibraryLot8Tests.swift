import XCTest
import SwiftData
import MuscuEngine
@testable import Muscu

/// Lot 8 : fusion de doublons, exercices habituels, lien de démonstration,
/// poids de corps datés et sauvegardes automatiques.
@MainActor
final class ExerciseMergeServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let now = Date(timeIntervalSince1970: 1_780_000_000)

    override func setUp() async throws {
        container = try TestStore.makeContainer()
        ExerciseMergeService.dismissedPairs = []
    }

    override func tearDown() async throws {
        ExerciseMergeService.dismissedPairs = []
        container = nil
    }

    private func completedSession(daysAgo: Double, sets: [(String, Double, Int)]) -> CompletedSession {
        let completedSets = sets.enumerated().map { index, entry in
            CompletedSet(exerciseId: entry.0, displayName: entry.0, orderIndex: 0, setIndex: index, weight: entry.1, reps: entry.2)
        }
        let session = CompletedSession(
            date: now.addingTimeInterval(-daysAgo * 86_400),
            programName: "P",
            sessionName: "A",
            durationSeconds: 1_800,
            sets: completedSets
        )
        context.insert(session)
        return session
    }

    /// Doublon personnalise « Developpe couche » utilise partout, a fusionner
    /// dans l'exercice du catalogue « bench ».
    private func makeDuplicateEverywhere() throws -> (duplicate: CustomExercise, session: CompletedSession) {
        let duplicate = CustomExercise(name: "Developpe couche", equipment: "barbell")
        context.insert(duplicate)
        let id = duplicate.id.uuidString

        let session = completedSession(daysAgo: 3, sets: [(id, 100, 5), (id, 100, 5), ("bench", 90, 5)])

        let program = Program(name: "Programme", isActive: true)
        context.insert(program)
        let programSession = ProgramSession(name: "A", orderIndex: 0)
        programSession.program = program
        program.sessions.append(programSession)
        context.insert(programSession)
        let prescription = PrescribedExercise(exerciseId: id, displayName: duplicate.name, orderIndex: 0, sets: 3, repsLower: 5, repsUpper: 8, restSeconds: 120)
        prescription.session = programSession
        programSession.exercises.append(prescription)
        context.insert(prescription)
        try context.save()
        TemplateService.makeTemplate(from: programSession, in: context)

        let goal = TrainingGoal(title: "120 kg")
        goal.target = .exerciseOneRepMax(exerciseId: id, kilograms: 120)
        context.insert(goal)

        let collection = ExerciseCollection(name: "Poussée")
        collection.exerciseIds = [id, "bench", "row"]
        context.insert(collection)

        let entry = ExerciseLibraryEntry(exerciseId: id, isFavorite: true, demoURL: "https://example.com/dup")
        entry.tags = ["force"]
        context.insert(entry)
        context.insert(ExerciseLibraryEntry(exerciseId: "bench", isFavorite: false))

        // Records : le doublon a la meilleure charge, le catalogue le
        // meilleur 1RM estime.
        context.insert(PersonalBest(exerciseId: id, displayName: duplicate.name, kindRaw: PersonalBestKind.maxWeight.rawValue, value: 100, sourceSessionId: session.id))
        context.insert(PersonalBest(exerciseId: "bench", displayName: "Développé couché", kindRaw: PersonalBestKind.maxWeight.rawValue, value: 95))
        context.insert(PersonalBest(exerciseId: id, displayName: duplicate.name, kindRaw: PersonalBestKind.estimatedOneRepMax.rawValue, value: 110))
        context.insert(PersonalBest(exerciseId: "bench", displayName: "Développé couché", kindRaw: PersonalBestKind.estimatedOneRepMax.rawValue, value: 120))
        context.insert(ExerciseRecord(exerciseId: id, displayName: duplicate.name, oneRepMax: 118, maxReps: nil))
        context.insert(ExerciseRecord(exerciseId: "bench", displayName: "Développé couché", oneRepMax: 115, maxReps: 12))
        try context.save()
        return (duplicate, session)
    }

    func testMergeMovesEveryReferenceAndKeepsBestRecords() throws {
        let (duplicate, session) = try makeDuplicateEverywhere()
        let id = duplicate.id.uuidString

        let report = try ExerciseMergeService.merge(duplicateId: id, into: "bench", survivorName: "Développé couché", in: context, now: now)

        XCTAssertEqual(report.sets, 2)
        XCTAssertEqual(report.sessions, 1)
        XCTAssertEqual(report.prescriptions, 1)
        XCTAssertEqual(report.templates, 1)
        XCTAssertEqual(report.goals, 1)

        // Historique : plus aucune serie sur le doublon.
        XCTAssertTrue(session.sets.allSatisfy { $0.exerciseId == "bench" })
        XCTAssertEqual(session.updatedAt, now)

        // Programme, modele, objectif, collection.
        let prescription = try XCTUnwrap(try context.fetch(FetchDescriptor<PrescribedExercise>()).first)
        XCTAssertEqual(prescription.exerciseId, "bench")
        XCTAssertEqual(prescription.displayName, "Développé couché")
        let template = try XCTUnwrap(try context.fetch(FetchDescriptor<SessionTemplate>()).first)
        XCTAssertEqual(TemplateService.payload(of: template)?.sessions.first?.exercises.first?.exerciseId, "bench")
        let goal = try XCTUnwrap(try context.fetch(FetchDescriptor<TrainingGoal>()).first)
        XCTAssertEqual(goal.target, .exerciseOneRepMax(exerciseId: "bench", kilograms: 120))
        XCTAssertEqual(try context.fetch(FetchDescriptor<ExerciseCollection>()).first?.exerciseIds, ["bench", "row"])

        // Annotations : favori, tags et lien rejoignent l'exercice conserve.
        let entries = try context.fetch(FetchDescriptor<ExerciseLibraryEntry>())
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.exerciseId, "bench")
        XCTAssertEqual(entries.first?.isFavorite, true)
        XCTAssertEqual(entries.first?.tags, ["force"])
        XCTAssertEqual(entries.first?.demoURL, "https://example.com/dup")

        // Records : le meilleur des deux, jamais de regression.
        let bests = try context.fetch(FetchDescriptor<PersonalBest>()).filter { $0.deletedAt == nil }
        XCTAssertTrue(bests.allSatisfy { $0.exerciseId == "bench" })
        XCTAssertEqual(bests.first { $0.kind == .maxWeight }?.value, 100)
        XCTAssertEqual(bests.first { $0.kind == .maxWeight }?.sourceSessionId, session.id)
        XCTAssertEqual(bests.first { $0.kind == .estimatedOneRepMax }?.value, 120)
        XCTAssertEqual(report.recordsGained, 2, "Charge max du doublon + 1RM saisi du doublon")
        let records = try context.fetch(FetchDescriptor<ExerciseRecord>())
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.oneRepMax, 118)
        XCTAssertEqual(records.first?.maxReps, 12)

        // Le doublon est redirige, pas supprime.
        XCTAssertEqual(duplicate.mergedIntoExerciseId, "bench")
        XCTAssertNil(duplicate.deletedAt)
        XCTAssertTrue(ExerciseMergeService.activeCustomExercises(in: context).isEmpty)
    }

    func testMergeIsRefusedDuringAWorkoutAndForCycles() throws {
        let first = CustomExercise(name: "A")
        let second = CustomExercise(name: "B", mergedIntoExerciseId: first.id.uuidString)
        context.insert(first)
        context.insert(second)
        context.insert(ActiveWorkout(programSessionId: UUID()))
        try context.save()

        XCTAssertThrowsError(try ExerciseMergeService.merge(duplicateId: first.id.uuidString, into: "bench", survivorName: "Bench", in: context)) { error in
            XCTAssertEqual(error as? ExerciseMergeService.MergeError, .workoutInProgress)
        }

        for workout in try context.fetch(FetchDescriptor<ActiveWorkout>()) { context.delete(workout) }
        try context.save()

        // B est deja redirige vers A : rediriger A vers B bouclerait.
        XCTAssertThrowsError(try ExerciseMergeService.merge(duplicateId: first.id.uuidString, into: second.id.uuidString, survivorName: "B", in: context)) { error in
            XCTAssertEqual(error as? ExerciseMergeService.MergeError, .wouldCreateCycle)
        }
        XCTAssertThrowsError(try ExerciseMergeService.merge(duplicateId: second.id.uuidString, into: "bench", survivorName: "Bench", in: context)) { error in
            XCTAssertEqual(error as? ExerciseMergeService.MergeError, .duplicateNotFound, "Un exercice déjà fusionné ne se refusionne pas")
        }
        XCTAssertNil(first.mergedIntoExerciseId)
    }

    func testPendingRedirectsAreAppliedAndIdempotent() throws {
        // Fusion faite sur un autre appareil : la redirection arrive, les
        // series locales designent encore le doublon.
        let duplicate = CustomExercise(name: "Squat perso", mergedIntoExerciseId: "squat")
        context.insert(duplicate)
        let session = completedSession(daysAgo: 1, sets: [(duplicate.id.uuidString, 120, 3)])
        try context.save()

        XCTAssertTrue(ExerciseMergeService.applyPendingRedirects(in: context, now: now))
        XCTAssertEqual(session.sets.first?.exerciseId, "squat")
        XCTAssertFalse(ExerciseMergeService.applyPendingRedirects(in: context, now: now), "Rien à refaire")
    }

    func testImportedArchiveFollowsRedirects() throws {
        // Archive d'un appareil qui n'avait pas encore recu la fusion.
        let sourceContainer = try TestStore.makeContainer()
        let source = sourceContainer.mainContext
        let duplicate = CustomExercise(name: "Rowing perso")
        source.insert(duplicate)
        source.insert(CompletedSession(programName: "P", sessionName: "A", sets: [
            CompletedSet(exerciseId: duplicate.id.uuidString, displayName: "Rowing perso", orderIndex: 0, setIndex: 0, weight: 60, reps: 10),
        ]))
        try source.save()
        let archive = try ExportImport.exportAll(context: source)

        // Cet appareil-ci a fusionne l'exercice.
        let local = CustomExercise(id: duplicate.id, name: "Rowing perso", mergedIntoExerciseId: "row")
        context.insert(local)
        try context.save()

        _ = try ExportImport.importAll(data: archive, context: context, mode: .merge)
        let sets = try context.fetch(FetchDescriptor<CompletedSet>())
        XCTAssertEqual(sets.map(\.exerciseId), ["row"])
    }

    func testPairsComeFromCatalogAndHistoryAndCanBeDismissed() throws {
        let duplicate = CustomExercise(name: "Développé couché", equipment: "barbell")
        context.insert(duplicate)
        _ = completedSession(daysAgo: 2, sets: [(duplicate.id.uuidString, 80, 8)])
        context.insert(CustomExercise(name: "Ancien", mergedIntoExerciseId: "bench"))
        try context.save()

        let catalog = [
            CatalogExercise(id: "bench", name: "Barbell Bench Press", nameFr: "Développé couché", equipment: "barbell", primaryMuscles: ["chest"]),
            CatalogExercise(id: "squat", name: "Squat", nameFr: "Squat", equipment: "barbell", primaryMuscles: ["quadriceps"]),
        ]
        let pairs = ExerciseMergeService.pairs(in: context, catalog: catalog)
        XCTAssertEqual(pairs.count, 1, "Un exercice déjà fusionné n'est plus proposé")
        let pair = try XCTUnwrap(pairs.first)
        XCTAssertEqual(pair.survivor.id, "bench")
        XCTAssertEqual(pair.duplicate.sessionCount, 1)
        XCTAssertEqual(pair.duplicate.setCount, 1)

        ExerciseMergeService.dismiss(pair)
        XCTAssertTrue(ExerciseMergeService.pairs(in: context, catalog: catalog).isEmpty)
    }
}

@MainActor
final class LibraryLot8Tests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUp() async throws {
        container = try TestStore.makeContainer()
    }

    override func tearDown() async throws {
        container = nil
    }

    func testHabitualExercisesFavourRecentFrequentOnes() throws {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        func session(_ daysAgo: Double, _ ids: [String]) {
            context.insert(CompletedSession(
                date: now.addingTimeInterval(-daysAgo * 86_400),
                programName: "P",
                sessionName: "A",
                sets: ids.enumerated().map { index, id in
                    CompletedSet(exerciseId: id, displayName: id, orderIndex: index, setIndex: 0, weight: 50, reps: 8)
                }
            ))
        }
        session(1, ["squat", "bench"])
        session(4, ["squat"])
        session(300, ["deadlift"])
        session(2, ["merged"])
        try context.save()

        let ids = HabitualExercises.identifiers(in: context, among: ["squat", "bench", "deadlift"], now: now)
        XCTAssertEqual(ids, ["squat", "bench", "deadlift"])
        XCTAssertFalse(ids.contains("merged"), "Seuls les exercices proposables figurent")
    }

    func testDemoLinkAcceptsOnlyWebLinks() throws {
        XCTAssertFalse(LibraryStore.setDemoURL("javascript:alert(1)", for: "bench", in: context))
        XCTAssertTrue(try context.fetch(FetchDescriptor<ExerciseLibraryEntry>()).isEmpty, "Un lien refusé ne crée rien")

        XCTAssertTrue(LibraryStore.setDemoURL("  https://example.com/bench  ", for: "bench", in: context))
        XCTAssertEqual(try context.fetch(FetchDescriptor<ExerciseLibraryEntry>()).first?.demoURL, "https://example.com/bench")

        XCTAssertTrue(LibraryStore.setDemoURL(nil, for: "bench", in: context))
        XCTAssertTrue(try context.fetch(FetchDescriptor<ExerciseLibraryEntry>()).isEmpty, "Une annotation vide disparaît")
    }

    func testBodyweightPointsAreDatedMeasurementsAndSessionValues() throws {
        let first = Date(timeIntervalSince1970: 1_780_000_000)
        context.insert(BodyMeasurement(measuredAt: first, value: 80))
        context.insert(BodyMeasurement(kindRaw: BodyMeasurementKind.waist.rawValue, measuredAt: first, value: 85))
        let session = CompletedSession(date: first.addingTimeInterval(86_400), programName: "P", sessionName: "A")
        session.bodyweightKilograms = 81
        context.insert(session)
        try context.save()

        let points = AnalyticsBridge.bodyweightPoints(context: context)
        XCTAssertEqual(points.map(\.value), [80, 81])
    }
}

@MainActor
final class AutoBackupServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private var savedEnabled: Any?
    private var savedLast: Any?
    private var savedReliable = true

    override func setUp() async throws {
        container = try TestStore.makeContainer()
        savedEnabled = UserDefaults.standard.object(forKey: AutoBackupService.enabledKey)
        savedLast = UserDefaults.standard.object(forKey: AutoBackupService.lastBackupKey)
        UserDefaults.standard.removeObject(forKey: AutoBackupService.lastBackupKey)
        try? FileManager.default.removeItem(at: AutoBackupService.directory)
        // L'application hote des tests peut tourner sur le conteneur de
        // secours (store du simulateur illisible) : ces tests travaillent sur
        // leur propre conteneur en memoire, fiable par construction.
        savedReliable = AutoBackupService.isStoreReliable
        AutoBackupService.isStoreReliable = true
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: AutoBackupService.directory)
        UserDefaults.standard.set(savedEnabled, forKey: AutoBackupService.enabledKey)
        UserDefaults.standard.set(savedLast, forKey: AutoBackupService.lastBackupKey)
        AutoBackupService.isStoreReliable = savedReliable
        container = nil
    }

    func testNothingIsWrittenWhileDisabled() {
        AutoBackupService.isEnabled = false
        XCTAssertNil(AutoBackupService.runIfDue(context: context))
        XCTAssertTrue(AutoBackupService.backups().isEmpty)
    }

    func testNothingIsWrittenFromTheTemporaryFallbackStore() {
        AutoBackupService.isEnabled = true
        AutoBackupService.isStoreReliable = false
        XCTAssertNil(AutoBackupService.runIfDue(context: context))
        XCTAssertThrowsError(try AutoBackupService.backUpNow(context: context))
        XCTAssertTrue(AutoBackupService.backups().isEmpty, "Une base de secours vide ne doit jamais remplacer les bonnes sauvegardes")
    }

    func testAtMostOneBackupPerDayAndRotation() throws {
        AutoBackupService.isEnabled = true
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        let day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 9))!

        XCTAssertNotNil(AutoBackupService.runIfDue(context: context, now: day, calendar: calendar))
        XCTAssertNil(AutoBackupService.runIfDue(context: context, now: day.addingTimeInterval(3_600), calendar: calendar), "Une seule par jour")
        XCTAssertEqual(AutoBackupService.backups().count, 1)

        for offset in 1...9 {
            XCTAssertNotNil(AutoBackupService.runIfDue(context: context, now: day.addingTimeInterval(Double(offset) * 86_400), calendar: calendar))
        }
        XCTAssertEqual(AutoBackupService.backups().count, AutoBackupPolicy.defaultRetainedCount)
    }

    func testBackupIsTheFullExportAndRestoresInReplaceMode() throws {
        context.insert(CompletedSession(programName: "P", sessionName: "Avant", sets: [
            CompletedSet(exerciseId: "bench", displayName: "Développé", orderIndex: 0, setIndex: 0, weight: 80, reps: 5),
        ]))
        try context.save()
        let url = try AutoBackupService.backUpNow(context: context)
        XCTAssertNoThrow(try ExportImport.preview(data: try Data(contentsOf: url)))

        context.insert(CompletedSession(programName: "P", sessionName: "Après"))
        try context.save()

        let backup = try XCTUnwrap(AutoBackupService.backups().first)
        let result = try AutoBackupService.restore(backup, context: context)
        XCTAssertNotNil(result.safetyBackup, "L'import Remplacer crée sa sauvegarde de sécurité")
        let names = try context.fetch(FetchDescriptor<CompletedSession>()).map(\.sessionName)
        XCTAssertEqual(names, ["Avant"])
    }
}
