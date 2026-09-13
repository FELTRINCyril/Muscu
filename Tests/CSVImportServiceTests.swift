import XCTest
import SwiftData
import MuscuEngine
@testable import Muscu

@MainActor
final class CSVImportServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private var catalog: ExerciseCatalog!

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    private var timeZone: TimeZone { calendar.timeZone }

    override func setUpWithError() throws {
        container = try TestStore.makeContainer()
        catalog = try ExerciseCatalog.load()
    }

    override func tearDownWithError() throws {
        container = nil
        catalog = nil
    }

    private func plan(_ text: String) throws -> CSVImportPlan {
        let rows = try CSVImportService.makeParser(for: text).parse(text)
        let preset = CSVImportPreset.detect(header: rows[0])
        let mapping = ColumnMapping.suggested(header: rows[0], preset: preset)
        return CSVImportPlanner.plan(
            rows: rows,
            mapping: mapping,
            existingSignatures: CSVImportService.existingSignatures(in: context, calendar: calendar, timeZone: timeZone),
            calendar: calendar,
            timeZone: timeZone
        )
    }

    private let strongExport = """
    Date,Workout Name,Exercise Name,Set Order,Weight,Reps,Notes
    2026-01-05 18:00:00,Séance A,Développé couché à la barre - prise moyenne,1,60,10,
    2026-01-05 18:00:00,Séance A,Développé couché à la barre - prise moyenne,2,62.5,8,dur
    2026-01-07 18:00:00,Séance B,Squat,1,100,5,
    """

    func testImportCreatesSessionsAndSets() throws {
        let outcome = CSVImportService.apply(
            try plan(strongExport),
            policy: .skipDuplicates,
            sourceName: "Strong",
            catalog: catalog,
            in: context
        )

        XCTAssertTrue(outcome.didWrite)
        XCTAssertEqual(outcome.report.created, 2)
        let sessions = try context.fetch(FetchDescriptor<CompletedSession>(sortBy: [SortDescriptor(\.date)]))
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions[0].sets.count, 2)
        XCTAssertEqual(sessions[0].importSource, "Strong")
        XCTAssertFalse(sessions[0].importSignature.isEmpty)
        let heaviest = sessions[0].orderedSets.max { $0.weight < $1.weight }
        XCTAssertEqual(heaviest?.weight, 62.5)
    }

    func testKnownExerciseIsLinkedToTheCatalog() throws {
        CSVImportService.apply(
            try plan(strongExport),
            policy: .skipDuplicates,
            sourceName: "Strong",
            catalog: catalog,
            in: context
        )

        let sets = try context.fetch(FetchDescriptor<CompletedSet>())
        let bench = try XCTUnwrap(sets.first { $0.displayName.contains("Développé couché") })
        XCTAssertFalse(bench.exerciseId.isEmpty, "Un exercice reconnu doit pointer vers le catalogue")
        XCTAssertNotNil(catalog.exercise(id: bench.exerciseId))
    }

    func testUnknownExerciseKeepsItsOriginalNameAndIsReported() throws {
        let text = """
        Date,Exercise Name,Weight,Reps
        2026-01-05 18:00:00,Mouvement inventé par moi,60,10
        """
        let outcome = CSVImportService.apply(
            try plan(text),
            policy: .skipDuplicates,
            sourceName: "CSV",
            catalog: catalog,
            in: context
        )

        XCTAssertEqual(outcome.unmatchedExerciseNames, ["Mouvement inventé par moi"])
        let set = try XCTUnwrap(try context.fetch(FetchDescriptor<CompletedSet>()).first)
        XCTAssertEqual(set.displayName, "Mouvement inventé par moi")
        XCTAssertTrue(set.exerciseId.isEmpty)
    }

    func testReimportingTheSameFileCreatesNothing() throws {
        CSVImportService.apply(try plan(strongExport), policy: .skipDuplicates, sourceName: "Strong", catalog: catalog, in: context)
        let secondOutcome = CSVImportService.apply(
            try plan(strongExport),
            policy: .skipDuplicates,
            sourceName: "Strong",
            catalog: catalog,
            in: context
        )

        XCTAssertEqual(secondOutcome.report.created, 0)
        XCTAssertEqual(secondOutcome.report.ignored, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CompletedSession>()).count, 2)
    }

    func testDuplicateCanBeImportedOnPurpose() throws {
        CSVImportService.apply(try plan(strongExport), policy: .skipDuplicates, sourceName: "Strong", catalog: catalog, in: context)
        let outcome = CSVImportService.apply(
            try plan(strongExport),
            policy: .importAnyway,
            sourceName: "Strong",
            catalog: catalog,
            in: context
        )

        XCTAssertEqual(outcome.report.created, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CompletedSession>()).count, 4)
    }

    func testExistingManualSessionIsRecognisedAsDuplicate() throws {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let manual = CompletedSession(
            date: formatter.date(from: "2026-01-05 18:00")!,
            programName: "Mon programme",
            sessionName: "Séance A"
        )
        context.insert(manual)
        try context.save()

        let result = try plan(strongExport)
        XCTAssertEqual(result.report.duplicates, 1)
    }

    func testQuarantinedRowsArePersistedWithTheirRawLine() throws {
        let text = """
        Date,Exercise Name,Weight,Reps
        pas une date,Squat,100,5
        2026-01-05 18:00:00,Squat,100,5
        """
        let outcome = CSVImportService.apply(
            try plan(text),
            policy: .skipDuplicates,
            sourceName: "CSV",
            catalog: catalog,
            in: context
        )

        XCTAssertEqual(outcome.report.quarantined, 1)
        let quarantine = CSVImportService.quarantine(in: context)
        XCTAssertEqual(quarantine.count, 1)
        XCTAssertTrue(quarantine[0].rawRow.contains("pas une date"))
        XCTAssertTrue(quarantine[0].reason.contains("Date illisible"))
        XCTAssertEqual(try context.fetch(FetchDescriptor<CompletedSession>()).count, 1)
    }

    func testClearingQuarantineKeepsImportedSessions() throws {
        let text = """
        Date,Exercise Name,Weight,Reps
        pas une date,Squat,100,5
        2026-01-05 18:00:00,Squat,100,5
        """
        CSVImportService.apply(try plan(text), policy: .skipDuplicates, sourceName: "CSV", catalog: catalog, in: context)
        CSVImportService.clearQuarantine(in: context)

        XCTAssertTrue(CSVImportService.quarantine(in: context).isEmpty)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CompletedSession>()).count, 1)
    }

    func testMalformedFileIsRejectedWithoutTouchingTheStore() throws {
        let existing = CompletedSession(programName: "P", sessionName: "Séance")
        context.insert(existing)
        try context.save()

        XCTAssertThrowsError(try plan("Date,Exercise Name\n\"jamais referme,2\n"))
        XCTAssertEqual(try context.fetch(FetchDescriptor<CompletedSession>()).count, 1)
    }

    func testOversizedFileIsRefusedBeforeAnyWrite() throws {
        let header = "Date,Exercise Name,Weight,Reps\n"
        let body = (0..<50).map { "2026-01-0\($0 % 9 + 1) 18:00:00,Squat,100,5" }.joined(separator: "\n")
        let parser = CSVParser(delimiter: ",", rowLimit: 10)

        XCTAssertThrowsError(try parser.parse(header + body))
        XCTAssertTrue(try context.fetch(FetchDescriptor<CompletedSession>()).isEmpty)
    }

    func testPartialFileImportsWhatIsReadableAndQuarantinesTheRest() throws {
        let text = """
        Date,Workout Name,Exercise Name,Weight,Reps
        2026-01-05 18:00:00,Séance A,Squat,100,5
        2026-01-06 18:00:00,Séance B,Squat,beaucoup,5
        2026-01-07 18:00:00,Séance C,Squat,110,5
        """
        let outcome = CSVImportService.apply(
            try plan(text),
            policy: .skipDuplicates,
            sourceName: "CSV",
            catalog: catalog,
            in: context
        )

        XCTAssertEqual(outcome.report.created, 2)
        XCTAssertEqual(outcome.report.quarantined, 1)
        XCTAssertEqual(outcome.report.merged, 0, "Une séance terminée n’est jamais fusionnée")
    }

    func testImportedSessionCarriesNoProgramLink() throws {
        CSVImportService.apply(try plan(strongExport), policy: .skipDuplicates, sourceName: "Strong", catalog: catalog, in: context)
        let sessions = try context.fetch(FetchDescriptor<CompletedSession>())
        XCTAssertTrue(sessions.allSatisfy { $0.programId == nil && $0.programSessionId == nil })
    }
}
