import Foundation
import Testing
@testable import MuscuEngine

private func parisCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    return calendar
}

@Suite("Lecture CSV")
struct CSVParserTests {
    @Test("Champs cités, virgules et guillemets doublés")
    func quotedFields() throws {
        let text = "a,b\n\"un, deux\",\"il a dit \"\"non\"\"\"\n"
        let rows = try CSVParser().parse(text)
        #expect(rows == [["a", "b"], ["un, deux", "il a dit \"non\""]])
    }

    @Test("Retour à la ligne à l'intérieur d'un champ cité")
    func newlineInsideQuotes() throws {
        let text = "a,b\n\"ligne1\nligne2\",x\n"
        let rows = try CSVParser().parse(text)
        #expect(rows.count == 2)
        #expect(rows[1][0] == "ligne1\nligne2")
    }

    @Test("Fins de ligne CRLF et BOM")
    func crlfAndBom() throws {
        let text = "\u{FEFF}a,b\r\n1,2\r\n"
        let rows = try CSVParser().parse(text)
        #expect(rows == [["a", "b"], ["1", "2"]])
    }

    @Test("Un guillemet non refermé est refusé, pas deviné")
    func unterminatedQuoteIsRejected() {
        #expect(throws: CSVParseError.self) {
            _ = try CSVParser().parse("a,b\n\"jamais referme,2\n")
        }
    }

    @Test("Un fichier vide est refusé")
    func emptyIsRejected() {
        #expect(throws: CSVParseError.self) { _ = try CSVParser().parse("") }
    }

    @Test("Un fichier trop volumineux est refusé sans être chargé en entier")
    func rowLimitIsEnforced() {
        let text = (0..<50).map { "\($0),x" }.joined(separator: "\n")
        #expect(throws: CSVParseError.self) {
            _ = try CSVParser(rowLimit: 10).parse(text)
        }
    }

    @Test("Le séparateur est détecté")
    func delimiterDetection() throws {
        #expect(CSVParser.detectDelimiter(in: "a;b;c\n1;2;3") == ";")
        #expect(CSVParser.detectDelimiter(in: "a\tb\n1\t2") == "\t")
        #expect(CSVParser.detectDelimiter(in: "a,b\n1,2") == ",")
        // Un point-virgule à l'intérieur d'un champ cité ne compte pas.
        #expect(CSVParser.detectDelimiter(in: "\"a;b\",c\n1,2") == ",")
    }

    @Test("Les lignes vides de fin ne créent pas de données fantômes")
    func trailingBlankLinesAreDropped() throws {
        let rows = try CSVParser().parse("a,b\n1,2\n\n\n")
        #expect(rows.count == 2)
    }
}

@Suite("Correspondance des colonnes")
struct ColumnMappingTests {
    @Test("Le format Strong est reconnu par ses entêtes")
    func strongIsDetected() {
        let header = ["Date", "Workout Name", "Duration", "Exercise Name", "Set Order", "Weight", "Reps", "Notes"]
        #expect(CSVImportPreset.detect(header: header) == .strong)
    }

    @Test("Le format Hevy est reconnu par ses entêtes")
    func hevyIsDetected() {
        let header = ["title", "start_time", "exercise_title", "set_index", "weight_kg", "reps"]
        #expect(CSVImportPreset.detect(header: header) == .hevy)
    }

    @Test("Un fichier inconnu reste générique")
    func unknownStaysGeneric() {
        #expect(CSVImportPreset.detect(header: ["quoi", "quand"]) == .generic)
    }

    @Test("Les colonnes sont pré-associées, y compris en français")
    func suggestedMappingWorksInFrench() {
        let header = ["Date", "Exercice", "Charge", "Répétitions", "Commentaire"]
        let mapping = ColumnMapping.suggested(header: header, preset: .generic)

        #expect(mapping.column(for: .date) == 0)
        #expect(mapping.column(for: .exerciseName) == 1)
        #expect(mapping.column(for: .weight) == 2)
        #expect(mapping.column(for: .reps) == 3)
        #expect(mapping.isUsable)
    }

    @Test("Une correspondance incomplète nomme ce qui manque")
    func missingRequiredFieldsAreNamed() {
        let mapping = ColumnMapping.suggested(header: ["Charge", "Répétitions"], preset: .generic)
        #expect(!mapping.isUsable)
        #expect(mapping.missingRequiredFields.contains(.date))
        #expect(mapping.missingRequiredFields.contains(.exerciseName))
    }
}

@Suite("Analyse d'import CSV")
struct CSVImportPlannerTests {
    private let calendar = parisCalendar()
    private var timeZone: TimeZone { calendar.timeZone }

    private func plan(_ text: String, existing: Set<String> = []) throws -> CSVImportPlan {
        let rows = try CSVParser(delimiter: CSVParser.detectDelimiter(in: text)).parse(text)
        let preset = CSVImportPreset.detect(header: rows[0])
        let mapping = ColumnMapping.suggested(header: rows[0], preset: preset)
        return CSVImportPlanner.plan(
            rows: rows,
            mapping: mapping,
            existingSignatures: existing,
            calendar: calendar,
            timeZone: timeZone
        )
    }

    @Test("Un export Strong est regroupé en séances")
    func strongExportIsGrouped() throws {
        let text = """
        Date,Workout Name,Exercise Name,Set Order,Weight,Reps,Notes
        2026-01-05 18:00:00,Séance A,Développé couché,1,60,10,
        2026-01-05 18:00:00,Séance A,Développé couché,2,62.5,8,dur
        2026-01-07 18:00:00,Séance B,Squat,1,100,5,
        """

        let result = try plan(text)
        #expect(result.sessions.count == 2)
        #expect(result.sessions[0].sets.count == 2)
        #expect(result.sessions[0].sets[1].weightKilograms == 62.5)
        #expect(result.sessions[0].sets[1].notes == "dur")
        #expect(result.report.created == 2)
        #expect(result.quarantined.isEmpty)
    }

    @Test("Un export Hevy convertit les kilomètres en mètres")
    func hevyDistanceIsConverted() throws {
        let text = """
        title,start_time,exercise_title,set_index,weight_kg,reps,distance_km,duration_seconds
        Cardio,22 Jan 2026, 17:41,Rameur,1,,,2.5,600
        """
        // La date Hevy contient une virgule : le champ est cité dans un vrai
        // export. On reproduit le cas cité pour rester fidèle.
        let quoted = """
        title,start_time,exercise_title,set_index,weight_kg,reps,distance_km,duration_seconds
        Cardio,"22 Jan 2026, 17:41",Rameur,1,,,2.5,600
        """
        _ = text

        let result = try plan(quoted)
        #expect(result.sessions.count == 1)
        let set = try #require(result.sessions.first?.sets.first)
        #expect(set.distanceMeters == 2500)
        #expect(set.durationSeconds == 600)
    }

    @Test("Les livres sont converties en kilogrammes")
    func poundsAreConverted() throws {
        let text = """
        Date,Exercise Name,Weight,Unit,Reps
        2026-01-05 18:00:00,Bench,100,lbs,5
        """
        let result = try plan(text)
        let set = try #require(result.sessions.first?.sets.first)
        #expect(abs((set.weightKilograms ?? 0) - 45.359) < 0.01)
    }

    @Test("Une date illisible met la ligne en quarantaine, pas à la poubelle")
    func unreadableDateIsQuarantined() throws {
        let text = """
        Date,Exercise Name,Weight,Reps
        pas une date,Bench,60,10
        2026-01-05 18:00:00,Bench,60,10
        """
        let result = try plan(text)
        #expect(result.sessions.count == 1)
        #expect(result.quarantined.count == 1)
        #expect(result.quarantined[0].rowNumber == 2)
        #expect(result.quarantined[0].raw.contains("pas une date"))
        if case .unreadableDate = result.quarantined[0].reason {} else {
            Issue.record("Raison de quarantaine inattendue")
        }
    }

    @Test("Une valeur non numérique est mise en quarantaine avec sa colonne")
    func unreadableNumberIsQuarantined() throws {
        let text = """
        Date,Exercise Name,Weight,Reps
        2026-01-05 18:00:00,Bench,beaucoup,10
        """
        let result = try plan(text)
        #expect(result.sessions.isEmpty)
        if case .unreadableNumber(let field, let value) = result.quarantined[0].reason {
            #expect(field == .weight)
            #expect(value == "beaucoup")
        } else {
            Issue.record("Raison de quarantaine inattendue")
        }
    }

    @Test("Une ligne sans mesure est mise en quarantaine")
    func rowWithoutMeasureIsQuarantined() throws {
        let text = """
        Date,Exercise Name,Weight,Reps
        2026-01-05 18:00:00,Bench,60,
        """
        let result = try plan(text)
        #expect(result.quarantined.count == 1)
        #expect(result.quarantined[0].reason == .noMeasure)
    }

    @Test("Un type de série inconnu est mis en quarantaine plutôt qu'interprété")
    func unknownSetKindIsQuarantined() throws {
        let text = """
        Date,Exercise Name,Set Type,Weight,Reps
        2026-01-05 18:00:00,Bench,téléportation,60,10
        """
        let result = try plan(text)
        #expect(result.sessions.isEmpty)
        if case .unknownValue(let field, _) = result.quarantined[0].reason {
            #expect(field == .setKind)
        } else {
            Issue.record("Raison de quarantaine inattendue")
        }
    }

    @Test("Les séries d'échauffement sont reconnues")
    func warmupSetsAreRecognised() throws {
        let text = """
        Date,Exercise Name,Set Type,Weight,Reps
        2026-01-05 18:00:00,Bench,warmup,20,10
        2026-01-05 18:00:00,Bench,normal,60,10
        """
        let result = try plan(text)
        let sets = try #require(result.sessions.first?.sets)
        #expect(sets.map(\.isWarmup) == [true, false])
    }

    @Test("Réimporter le même fichier ne recrée pas les séances")
    func duplicatesAreDetected() throws {
        let text = """
        Date,Workout Name,Exercise Name,Weight,Reps
        2026-01-05 18:00:00,Séance A,Bench,60,10
        """
        let first = try plan(text)
        #expect(first.report.created == 1)
        #expect(first.report.duplicates == 0)

        let signatures = Set(first.sessions.map(\.signature))
        let second = try plan(text, existing: signatures)
        #expect(second.report.created == 0)
        #expect(second.report.duplicates == 1)
        #expect(second.duplicateSignatures == signatures)
    }

    @Test("Les secondes ne cassent pas la déduplication")
    func signatureIgnoresSeconds() {
        let reference = Date(timeIntervalSince1970: 1_767_636_000)
        let shifted = reference.addingTimeInterval(42)
        let left = CSVImportPlanner.signature(date: reference, name: "Séance A", calendar: calendar, timeZone: timeZone)
        let right = CSVImportPlanner.signature(date: shifted, name: "séance a", calendar: calendar, timeZone: timeZone)
        #expect(left == right)
    }

    @Test("Une correspondance inutilisable ne produit aucune écriture")
    func unusableMappingProducesNothing() {
        let result = CSVImportPlanner.plan(
            rows: [["a", "b"], ["1", "2"]],
            mapping: ColumnMapping(),
            calendar: calendar,
            timeZone: timeZone
        )
        #expect(result.sessions.isEmpty)
        #expect(result.report.errors.count == 1)
    }

    @Test("Un fichier sans ligne de données le dit clairement")
    func headerOnlyIsReported() {
        let mapping = ColumnMapping(assignments: [0: .date, 1: .exerciseName])
        let result = CSVImportPlanner.plan(
            rows: [["Date", "Exercice"]],
            mapping: mapping,
            calendar: calendar,
            timeZone: timeZone
        )
        #expect(result.sessions.isEmpty)
        #expect(result.report.errors.first?.contains("aucune ligne") == true)
    }

    @Test("Le rapport résume chaque catégorie")
    func reportSummaryIsComplete() throws {
        let text = """
        Date,Workout Name,Exercise Name,Weight,Reps
        2026-01-05 18:00:00,Séance A,Bench,60,10
        pas une date,Séance A,Bench,60,10
        """
        let result = try plan(text)
        #expect(result.report.created == 1)
        #expect(result.report.quarantined == 1)
        #expect(result.report.summary.contains("1 créée(s)"))
        #expect(result.report.summary.contains("1 en quarantaine"))
    }
}

@Suite("Détection de séparateur sur fichier Windows")
struct CSVDelimiterOnWindowsTests {
    @Test("Le séparateur est détecté sur la première ligne seulement")
    func firstLineOnly() {
        // Sans découpage correct des fins de ligne CRLF, les virgules de la
        // deuxième ligne feraient basculer la détection.
        #expect(CSVParser.detectDelimiter(in: "a;b\r\n1,2,3,4\r\n") == ";")
    }
}

@Suite("Lecture des dates d'import")
struct CSVDateParsingTests {
    private let timeZone = TimeZone(identifier: "Europe/Paris")!

    @Test("Une date avec heure garde son heure")
    func dateWithTimeKeepsTheTime() throws {
        let date = try #require(DateParsing.date(from: "2026-01-05 18:30:00", timeZone: timeZone))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        #expect(calendar.component(.hour, from: date) == 18)
        #expect(calendar.component(.minute, from: date) == 30)
    }

    @Test("Une date seule vaut minuit")
    func bareDateIsMidnight() throws {
        let date = try #require(DateParsing.date(from: "2026-01-05", timeZone: timeZone))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        #expect(calendar.component(.hour, from: date) == 0)
    }

    @Test("Un texte qui n'est pas une date est refusé")
    func nonDateIsRejected() {
        #expect(DateParsing.date(from: "pas une date", timeZone: timeZone) == nil)
        #expect(DateParsing.date(from: "", timeZone: timeZone) == nil)
    }
}
