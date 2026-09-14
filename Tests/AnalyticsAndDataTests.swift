import XCTest
import SwiftData
import MuscuEngine
@testable import Muscu

@MainActor
final class AnalyticsAndDataTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let reference = Date(timeIntervalSince1970: 1_750_000_000)

    override func setUpWithError() throws {
        container = try TestStore.makeContainer()
    }

    override func tearDownWithError() throws {
        container = nil
    }

    // MARK: - Fabriques

    @discardableResult
    private func addSession(
        daysAgo: Int,
        exerciseId: String = "bench",
        weight: Double = 60,
        reps: Int = 10,
        setCount: Int = 3,
        loadType: ExerciseLoadType = .external,
        bodyweight: Double? = 80,
        duration: Int = 3_600
    ) -> CompletedSession {
        let sets = (0..<setCount).map { index in
            CompletedSet(
                exerciseId: exerciseId,
                displayName: exerciseId,
                orderIndex: 0,
                setIndex: index,
                weight: weight,
                reps: reps,
                loadTypeRaw: loadType.rawValue,
                roleRaw: SetRole.working.rawValue,
                sequenceIndex: index
            )
        }
        let session = CompletedSession(
            date: reference.addingTimeInterval(TimeInterval(-daysAgo * 86_400)),
            programName: "Programme",
            sessionName: "Séance",
            durationSeconds: duration,
            bodyweightKilograms: bodyweight,
            sets: sets
        )
        context.insert(session)
        return session
    }

    // MARK: - Calcul partagé

    /// Critère de la roadmap : deux vues affichant le même indicateur doivent
    /// utiliser le même calcul. On vérifie que le pont d'analyse produit bien
    /// la valeur de `SetMetrics`, sans formule locale.
    func testBridgeTonnageMatchesSharedComputation() throws {
        addSession(daysAgo: 2)
        try context.save()

        let sessions = AnalyticsBridge.sessions(context: context, catalogStore: nil)
        let weeks = TrainingAnalytics.weeklySummaries(sessions: sessions)
        let expected = try XCTUnwrap(
            context.fetch(FetchDescriptor<CompletedSession>()).first
        ).metricsInputs()

        XCTAssertEqual(
            TrainingAnalytics.merged(weeks).tonnage.value,
            SetMetrics.totalTonnage(expected).total
        )
    }

    /// Une traction assistée ne doit alimenter ni la courbe de charge ni le
    /// tonnage sans poids de corps connu.
    func testAssistedWorkNeverProducesALoadSeries() throws {
        addSession(daysAgo: 1, exerciseId: "pullup", weight: 30, reps: 8, loadType: .assisted, bodyweight: 80)
        try context.save()

        let sessions = AnalyticsBridge.sessions(context: context, catalogStore: nil)
        XCTAssertTrue(TrainingAnalytics.series(metric: .maxLoad, exerciseId: "pullup", sessions: sessions).isEmpty)
        XCTAssertFalse(TrainingAnalytics.series(metric: .maxReps, exerciseId: "pullup", sessions: sessions).isEmpty)
    }

    /// Sans poids de corps connu, le tonnage d'un exercice au poids du corps
    /// est signalé comme incomplet, jamais compté comme zéro.
    func testUnknownBodyweightIsReportedAsMissing() throws {
        addSession(daysAgo: 1, exerciseId: "pushup", weight: 0, reps: 20, loadType: .bodyweight, bodyweight: nil)
        try context.save()

        let sessions = AnalyticsBridge.sessions(context: context, catalogStore: nil)
        let week = TrainingAnalytics.merged(TrainingAnalytics.weeklySummaries(sessions: sessions))
        XCTAssertEqual(week.tonnage.unknownSets, 3)
        XCTAssertFalse(week.tonnage.isComplete)
    }

    /// Le poids de corps figé sur la séance prime sur la valeur du profil :
    /// un calcul d'il y a deux ans ne doit pas changer parce que l'athlète a
    /// changé de poids depuis.
    func testSessionBodyweightWinsOverProfile() throws {
        let profile = ProfileStore.ensureProfile(in: context)
        profile.bodyweightKilograms = 95
        addSession(daysAgo: 1, exerciseId: "pullup", weight: 0, reps: 10, setCount: 1, loadType: .bodyweight, bodyweight: 80)
        try context.save()

        let sessions = AnalyticsBridge.sessions(context: context, catalogStore: nil)
        let week = TrainingAnalytics.merged(TrainingAnalytics.weeklySummaries(sessions: sessions))
        XCTAssertEqual(week.tonnage.value, 800)
    }

    // MARK: - Objectifs

    func testGoalProgressUsesSharedAnalytics() throws {
        addSession(daysAgo: 1)
        addSession(daysAgo: 2)
        try context.save()

        let sessions = AnalyticsBridge.sessions(context: context, catalogStore: nil)
        let weeks = TrainingAnalytics.weeklySummaries(sessions: sessions)
        let current = Double(weeks.last?.sessionCount ?? 0)
        let progress = GoalEvaluator.progress(
            target: .sessionsPerWeek(count: 4),
            observation: GoalObservation(current: current)
        )
        XCTAssertEqual(progress.ratio, 0.5)
    }

    func testGoalTargetRoundTripsThroughTheModel() throws {
        let goal = TrainingGoal(title: "Test")
        goal.target = .weeklySetsForMuscle(muscle: "lats", sets: 14)
        context.insert(goal)
        try context.save()

        let stored = try XCTUnwrap(context.fetch(FetchDescriptor<TrainingGoal>()).first)
        XCTAssertEqual(stored.target, .weeklySetsForMuscle(muscle: "lats", sets: 14))
    }

    func testGoalsSurviveExportAndImport() throws {
        let goal = TrainingGoal(title: "4 séances", startValue: 85)
        goal.target = .sessionsPerWeek(count: 4)
        context.insert(goal)
        try context.save()

        let data = try ExportImport.exportAll(context: context)
        let destination = try TestStore.makeContainer()
        try ExportImport.importAll(data: data, context: destination.mainContext)

        let restored = try XCTUnwrap(destination.mainContext.fetch(FetchDescriptor<TrainingGoal>()).first)
        XCTAssertEqual(restored.target, .sessionsPerWeek(count: 4))
        XCTAssertEqual(restored.startValue, 85)
    }

    // MARK: - Export CSV

    func testSetsCSVContainsOneRowPerSetPlusHeader() throws {
        addSession(daysAgo: 1, setCount: 3)
        try context.save()

        let csv = try CSVExport.csv(for: .sets, context: context)
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: true)
        XCTAssertEqual(lines.count, 4)
        XCTAssertTrue(lines[0].contains("charge_kg"))
    }

    func testMeasurementsCSVUsesCanonicalUnits() throws {
        context.insert(BodyMeasurement(kindRaw: BodyMeasurementKind.waist.rawValue, value: 82.5))
        try context.save()

        let csv = try CSVExport.csv(for: .measurements, context: context)
        XCTAssertTrue(csv.contains("82.500"))
        XCTAssertTrue(csv.contains(",cm,"))
    }

    /// Un commentaire commençant par « = » ne doit jamais devenir une formule
    /// exécutée à l'ouverture du fichier dans un tableur.
    func testFormulaInjectionIsNeutralised() {
        XCTAssertEqual(CSVExport.escape("=1+1"), "\"'=1+1\"")
        XCTAssertEqual(CSVExport.escape("@SUM(A1)"), "\"'@SUM(A1)\"")
        XCTAssertEqual(CSVExport.escape("-12.5"), "-12.5", "Un nombre négatif reste un nombre")
        XCTAssertEqual(CSVExport.escape("simple"), "simple")
    }

    func testQuotesAndSeparatorsAreEscaped() {
        XCTAssertEqual(CSVExport.escape("a,b"), "\"a,b\"")
        XCTAssertEqual(CSVExport.escape("dit \"oui\""), "\"dit \"\"oui\"\"\"")
        XCTAssertEqual(CSVExport.render([["a", "b"], ["c,d", "e"]]), "a,b\n\"c,d\",e\n")
    }

    func testCheckInsCSVKeepsMissingValuesEmptyNotZero() throws {
        context.insert(ReadinessEntry(energy: 4, painIntensity: nil))
        try context.save()

        let csv = try CSVExport.csv(for: .checkIns, context: context)
        let lines = csv.split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        // energie=4, sommeil/courbatures/stress/douleur vides.
        XCTAssertTrue(lines[1].contains(",4,,,,,"))
    }

    // MARK: - Suppression

    /// La « suppression totale » doit couvrir tout le schéma : un modèle
    /// oublié rendrait la promesse mensongère.
    func testDeletionCategoriesCoverEveryModel() {
        let schema = Set(MuscuCurrentSchema.models.map { String(describing: $0) })
        let missing = schema.subtracting(DataDeletion.coveredModelNames)
        XCTAssertTrue(
            missing.isEmpty,
            "Ces modèles ne sont couverts par aucune catégorie de suppression : \(missing.sorted().joined(separator: ", "))"
        )
    }

    func testDeletingACategoryLeavesTheOthersIntact() throws {
        addSession(daysAgo: 1)
        context.insert(BodyMeasurement(kindRaw: BodyMeasurementKind.bodyweight.rawValue, value: 80))
        context.insert(CustomExercise(name: "Perso"))
        try context.save()

        let report = try DataDeletion.delete(.measurements, context: context)

        XCTAssertEqual(report.countsByModel["mesures"], 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BodyMeasurement>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CompletedSession>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CustomExercise>()), 1)
    }

    func testDeletingHistoryAlsoRemovesTheRunningSession() throws {
        addSession(daysAgo: 1)
        context.insert(ActiveWorkout(programSessionId: UUID()))
        try context.save()

        try DataDeletion.delete(.history, context: context)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CompletedSession>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CompletedSet>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ActiveWorkout>()), 0)
    }

    func testDeleteEverythingEmptiesTheStoreAndReportsIt() throws {
        addSession(daysAgo: 1)
        context.insert(BodyMeasurement(kindRaw: BodyMeasurementKind.bodyweight.rawValue, value: 80))
        context.insert(ReadinessEntry(energy: 3))
        context.insert(CustomExercise(name: "Perso"))
        ProfileStore.ensureProfile(in: context)
        try context.save()

        let report = try DataDeletion.deleteEverything(context: context)

        XCTAssertGreaterThan(report.total, 0)
        XCTAssertFalse(report.summary.isEmpty)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CompletedSession>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BodyMeasurement>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ReadinessEntry>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AthleteProfile>()), 0)
    }

    func testDeletionOnAnEmptyStoreIsHarmless() throws {
        let report = try DataDeletion.deleteEverything(context: context)
        XCTAssertEqual(report.total, 0)
        // Le compte rendu est localisé : comparer au littéral français ferait
        // dépendre ce test de la langue de la machine. Ce qui compte ici est
        // qu'un store vide produise la phrase « rien à supprimer » et non une
        // énumération vide.
        XCTAssertEqual(report.summary, String(localized: "Aucune donnée à supprimer."))
        XCTAssertFalse(report.summary.contains("0"))
    }

    // MARK: - Performance sur gros historique

    /// Deux ans d'entraînement à quatre séances par semaine : les tableaux de
    /// bord doivent rester utilisables.
    func testDashboardsStayFastOnALargeHistory() throws {
        let sessionCount = 400
        for index in 0..<sessionCount {
            addSession(daysAgo: index, weight: Double(50 + index % 40), setCount: 4)
        }
        try context.save()

        let start = Date()
        let sessions = AnalyticsBridge.sessions(context: context, catalogStore: nil)
        let weeks = TrainingAnalytics.weeklySummaries(sessions: sessions)
        _ = TrainingAnalytics.filled(weeks: weeks)
        _ = TrainingAnalytics.setsByMuscle(sessions: sessions)
        _ = TrainingAnalytics.series(metric: .estimatedOneRepMax, exerciseId: "bench", sessions: sessions)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(sessions.count, min(sessionCount, AnalyticsBridge.defaultSessionLimit))
        XCTAssertLessThan(elapsed, 2.0, "Les tableaux de bord ont mis \(elapsed) s sur \(sessionCount) séances")
    }

    /// La lecture est bornée : un historique de plusieurs années ne doit pas
    /// être chargé en entier pour afficher un tableau de bord.
    func testSessionLoadingIsBounded() throws {
        for index in 0..<(AnalyticsBridge.defaultSessionLimit + 50) {
            addSession(daysAgo: index, setCount: 1)
        }
        try context.save()

        let sessions = AnalyticsBridge.sessions(context: context, catalogStore: nil, limit: 100)
        XCTAssertEqual(sessions.count, 100)
        // Les séances retenues sont les plus RÉCENTES, triées du plus ancien
        // au plus récent pour l'affichage.
        XCTAssertTrue(sessions.first!.date < sessions.last!.date)
    }
}
