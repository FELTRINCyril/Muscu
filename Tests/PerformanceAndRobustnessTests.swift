import XCTest
import SwiftData
import MuscuEngine
@testable import Muscu

/// Performance avec un historique de plusieurs années.
///
/// Les seuils sont volontairement LARGES : ils attrapent une régression d'un
/// ordre de grandeur (un chargement complet du store, un calcul quadratique),
/// pas une variation de quelques pourcents qui rendrait la suite instable.
@MainActor
final class LargeHistoryPerformanceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let reference = Date(timeIntervalSince1970: 1_772_000_000)

    /// Trois séances par semaine pendant trois ans.
    private let sessionCount = 468
    private let setsPerSession = 15

    /// `setUp() async throws` et non `setUpWithError()` : la variante
    /// synchrone n'est pas isolée sur l'acteur principal, et ne peut donc pas
    /// appeler le remplissage qui, lui, manipule le contexte SwiftData.
    override func setUp() async throws {
        container = try TestStore.makeContainer()
        try seedLargeHistory()
    }

    override func tearDown() async throws {
        container = nil
    }

    private func seedLargeHistory() throws {
        let exercises = ["bench", "squat", "deadlift", "row", "ohp"]
        for index in 0..<sessionCount {
            let session = CompletedSession(
                date: reference.addingTimeInterval(-Double(index) * 2.33 * 86_400),
                programName: "Programme",
                sessionName: "Séance \(index % 3)",
                durationSeconds: 3_600
            )
            context.insert(session)

            for setIndex in 0..<setsPerSession {
                let set = CompletedSet(
                    exerciseId: exercises[setIndex % exercises.count],
                    displayName: exercises[setIndex % exercises.count],
                    orderIndex: setIndex / 3,
                    setIndex: setIndex % 3,
                    weight: Double(60 + index % 40),
                    reps: 8,
                    loadTypeRaw: ExerciseLoadType.external.rawValue,
                    roleRaw: SetRole.working.rawValue,
                    sequenceIndex: setIndex
                )
                set.session = session
                session.sets.append(set)
                context.insert(set)
            }
        }
        try context.save()
    }

    func testTheHistoryIsReallyLarge() throws {
        XCTAssertEqual(try context.fetch(FetchDescriptor<CompletedSession>()).count, sessionCount)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CompletedSet>()).count, sessionCount * setsPerSession)
    }

    /// Les tableaux de bord ne doivent PAS charger tout le store : le pont
    /// d'analyses borne sa lecture.
    func testDashboardReadingIsBounded() throws {
        let start = Date()
        let sessions = AnalyticsBridge.sessions(context: context, catalogStore: nil)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThanOrEqual(
            sessions.count,
            AnalyticsBridge.defaultSessionLimit,
            "Le tableau de bord doit borner sa lecture, pas tout charger"
        )
        XCTAssertLessThan(elapsed, 2.0, "Lecture du tableau de bord trop lente : \(elapsed) s")
    }

    /// `measure` de XCTest envoie son bloc hors de l'acteur principal, ce que
    /// la concurrence stricte refuse ici. On chronomètre donc explicitement,
    /// avec des seuils larges : on veut attraper une régression d'un ordre de
    /// grandeur, pas une variation de quelques pourcents.
    private func duration(of work: () -> Void) -> TimeInterval {
        let start = Date()
        work()
        return Date().timeIntervalSince(start)
    }

    func testWeeklyAggregationStaysFast() throws {
        let sessions = AnalyticsBridge.sessions(context: context, catalogStore: nil)
        let elapsed = duration { _ = TrainingAnalytics.weeklySummaries(sessions: sessions) }
        XCTAssertLessThan(elapsed, 2.0, "Agrégation hebdomadaire trop lente : \(elapsed) s")
    }

    func testWidgetSnapshotStaysFast() throws {
        let elapsed = duration { _ = WidgetSnapshotService.makeSnapshot(in: context, now: reference) }
        XCTAssertLessThan(elapsed, 3.0, "Instantané des widgets trop lent : \(elapsed) s")
    }

    func testProgressionProposalStaysFast() throws {
        let program = Program(name: "Programme", isActive: true)
        context.insert(program)
        let session = ProgramSession(name: "Séance", orderIndex: 0)
        session.program = program
        program.sessions.append(session)
        context.insert(session)
        for (index, exerciseId) in ["bench", "squat", "row"].enumerated() {
            let exercise = PrescribedExercise(
                exerciseId: exerciseId,
                displayName: exerciseId,
                orderIndex: index,
                sets: 3,
                repsLower: 6,
                repsUpper: 8,
                targetWeight: 80
            )
            exercise.session = session
            session.exercises.append(exercise)
            context.insert(exercise)
        }
        try context.save()

        let elapsed = duration { _ = ProgressionReview.proposals(for: session, context: context) }
        XCTAssertLessThan(elapsed, 5.0, "Propositions de progression trop lentes : \(elapsed) s")
    }

    func testPlateauDetectionStaysFastOnAllExercises() throws {
        let elapsed = duration { _ = PlateauReview.findings(in: context, now: reference) }
        XCTAssertLessThan(elapsed, 5.0, "Détection de plateau trop lente : \(elapsed) s")
    }

    /// L'export complet d'un gros historique doit rester réalisable.
    func testFullExportCompletesAndStaysWithinTheImportLimit() throws {
        let start = Date()
        let data = try ExportImport.exportAll(context: context)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 20.0, "Export trop lent : \(elapsed) s")
        XCTAssertLessThan(
            data.count,
            ExportImport.maximumImportBytes,
            "Une archive que l'application ne saurait pas réimporter serait un piège"
        )
    }

    func testCSVExportCompletes() throws {
        let start = Date()
        let csv = try CSVExport.csv(for: .sets, context: context)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertGreaterThan(csv.count, 1_000)
        XCTAssertLessThan(elapsed, 20.0, "Export CSV trop lent : \(elapsed) s")
    }
}

/// Robustesse : des données abîmées ou extrêmes ne doivent ni faire planter
/// l'application, ni lui faire écrire n'importe quoi.
@MainActor
final class ImportRobustnessTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUpWithError() throws {
        container = try TestStore.makeContainer()
    }

    override func tearDownWithError() throws {
        container = nil
    }

    /// Octets arbitraires : l'import doit refuser proprement, à chaque fois.
    func testRandomBytesAreAlwaysRefusedWithoutWriting() throws {
        var generator = SystemRandomNumberGenerator()

        for index in 0..<200 {
            let length = Int.random(in: 0...400, using: &generator)
            let data = Data((0..<length).map { _ in UInt8.random(in: 0...255, using: &generator) })

            XCTAssertThrowsError(
                try ExportImport.importAll(data: data, context: context),
                "Itération \(index) : des octets arbitraires ne doivent jamais être acceptés"
            )
        }

        XCTAssertTrue(try context.fetch(FetchDescriptor<Program>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CompletedSession>()).isEmpty)
    }

    func testTruncatedArchivesAreRefused() throws {
        let program = Program(name: "Programme", isActive: true)
        context.insert(program)
        try context.save()
        let complete = try ExportImport.exportAll(context: context)

        let destination = try TestStore.makeContainer()
        for fraction in [0.1, 0.25, 0.5, 0.75, 0.9] {
            let truncated = complete.prefix(Int(Double(complete.count) * fraction))
            XCTAssertThrowsError(
                try ExportImport.importAll(data: Data(truncated), context: destination.mainContext),
                "Une archive tronquée à \(Int(fraction * 100)) % doit être refusée"
            )
        }
        XCTAssertTrue(try destination.mainContext.fetch(FetchDescriptor<Program>()).isEmpty)
    }

    func testAnArchiveLargerThanTheLimitIsRefusedBeforeDecoding() throws {
        let oversized = Data(repeating: 0x7B, count: ExportImport.maximumImportBytes + 1)
        let start = Date()

        XCTAssertThrowsError(try ExportImport.importAll(data: oversized, context: context))

        // Le refus repose sur la TAILLE, pas sur un décodage : il doit être
        // immédiat, sinon un fichier énorme bloquerait l'application.
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.0)
    }

    func testAValidArchiveStillImportsAfterAllThoseRefusals() throws {
        let program = Program(name: "Programme", isActive: true)
        context.insert(program)
        try context.save()
        let archive = try ExportImport.exportAll(context: context)

        let destination = try TestStore.makeContainer()
        _ = try? ExportImport.importAll(data: Data([0x00, 0x01]), context: destination.mainContext)
        let summary = try ExportImport.importAll(data: archive, context: destination.mainContext)

        XCTAssertEqual(summary.programsCount, 1)
    }
}
