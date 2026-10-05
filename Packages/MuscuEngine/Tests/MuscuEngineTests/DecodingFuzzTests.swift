import Foundation
import Testing
@testable import MuscuEngine

/// Générateur pseudo-aléatoire DÉTERMINISTE.
///
/// Un test de robustesse qui échoue une fois sur mille sans pouvoir être
/// rejoué ne sert à rien : la graine est fixe, donc un échec est reproductible
/// à l'identique.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

private func randomBytes(count: Int, generator: inout SeededGenerator) -> Data {
    Data((0..<count).map { _ in UInt8.random(in: 0...255, using: &generator) })
}

private func randomText(count: Int, generator: inout SeededGenerator) -> String {
    // Alphabet choisi pour maximiser les pièges d'un lecteur CSV : guillemets,
    // séparateurs, fins de ligne, accents et caractères de contrôle.
    let alphabet = Array("abcéè0123,;\t\n\r\"'{}[]:\\ \u{0000}\u{200B}é")
    return String((0..<count).map { _ in alphabet.randomElement(using: &generator)! })
}

@Suite("Robustesse du décodage")
struct DecodingFuzzTests {
    /// Le lecteur CSV doit toujours rendre la main : soit des lignes, soit une
    /// erreur typée. Jamais une exception non gérée, jamais une boucle infinie.
    @Test("Le lecteur CSV survit à des octets arbitraires")
    func csvParserSurvivesRandomBytes() {
        var generator = SeededGenerator(seed: 42)

        for _ in 0..<400 {
            let text = randomText(count: Int.random(in: 0...500, using: &generator), generator: &generator)
            let delimiter = CSVParser.detectDelimiter(in: text)
            let parser = CSVParser(delimiter: delimiter, rowLimit: 1_000)

            do {
                let rows = try parser.parse(text)
                // Une ligne ne peut pas être vide : le lecteur les écarte.
                #expect(rows.allSatisfy { !$0.isEmpty })
            } catch is CSVParseError {
                // Refus explicite : c'est le comportement attendu.
            } catch {
                Issue.record("Erreur inattendue : \(error)")
            }
        }
    }

    @Test("La planification d'import survit à des colonnes arbitraires")
    func importPlannerSurvivesRandomRows() {
        var generator = SeededGenerator(seed: 1_337)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!

        for _ in 0..<200 {
            let columnCount = Int.random(in: 1...6, using: &generator)
            let rowCount = Int.random(in: 1...8, using: &generator)
            let rows = (0..<rowCount).map { _ in
                (0..<columnCount).map { _ in randomText(count: Int.random(in: 0...20, using: &generator), generator: &generator) }
            }

            let mapping = ColumnMapping(assignments: [0: .date, 1: .exerciseName, 2: .reps])
            let plan = CSVImportPlanner.plan(
                rows: rows,
                mapping: mapping,
                calendar: calendar,
                timeZone: calendar.timeZone
            )

            // Toute ligne non retenue est soit une séance, soit une mise en
            // quarantaine : rien ne disparaît en silence.
            let accounted = plan.sessions.reduce(0) { $0 + $1.sets.count } + plan.quarantined.count
            #expect(accounted <= max(0, rowCount - 1))
        }
    }

    @Test("Une réponse d'IA arbitraire ne devient jamais un programme")
    func aiResponseNeverDecodesFromGarbage() {
        var generator = SeededGenerator(seed: 7)
        let decoder = JSONDecoder()

        for _ in 0..<300 {
            let data = randomBytes(count: Int.random(in: 0...200, using: &generator), generator: &generator)
            let decoded = try? decoder.decode(AICoachResponse.self, from: data)
            #expect(decoded == nil)
        }
    }

    /// Un JSON STRUCTURELLEMENT valide mais hostile ne doit pas produire de
    /// brouillon acceptable.
    @Test("Un JSON valide mais hostile est rejeté ou réparé, jamais accepté tel quel")
    func hostileButValidJSONIsHandled() {
        var generator = SeededGenerator(seed: 99)
        let allowed: Set<String> = ["bench", "squat"]

        for _ in 0..<200 {
            let draft = AIProgramDraft(
                name: randomText(count: Int.random(in: 0...30, using: &generator), generator: &generator),
                notes: randomText(count: Int.random(in: 0...50, using: &generator), generator: &generator),
                sessions: (0..<Int.random(in: 0...4, using: &generator)).map { _ in
                    AISessionDraft(
                        name: randomText(count: Int.random(in: 0...20, using: &generator), generator: &generator),
                        exercises: (0..<Int.random(in: 0...5, using: &generator)).map { _ in
                            AIExerciseDraft(
                                exerciseId: Bool.random(using: &generator)
                                    ? "bench"
                                    : randomText(count: 8, generator: &generator),
                                sets: Int.random(in: -1_000...1_000, using: &generator),
                                repsLower: Int.random(in: -1_000...1_000, using: &generator),
                                repsUpper: Int.random(in: -1_000...1_000, using: &generator),
                                restSeconds: Int.random(in: -1_000...100_000, using: &generator)
                            )
                        }
                    )
                }
            )

            let outcome = AIResponseValidator.validate(draft, allowedExerciseIds: allowed)

            guard let accepted = outcome.draft else {
                #expect(!outcome.violations.isEmpty, "Un rejet doit toujours être motivé")
                continue
            }

            // Tout ce qui est accepté est dans les bornes de l'éditeur ET
            // n'utilise que des exercices connus.
            for session in accepted.sessions {
                for exercise in session.exercises {
                    #expect(allowed.contains(exercise.exerciseId))
                    #expect((1...10).contains(exercise.sets))
                    #expect((1...100).contains(exercise.repsLower))
                    #expect((1...100).contains(exercise.repsUpper))
                    #expect(exercise.repsLower <= exercise.repsUpper)
                    #expect((0...600).contains(exercise.restSeconds))
                }
            }
        }
    }

    @Test("Le nettoyage de texte ne boucle ni ne plante sur des octets arbitraires")
    func sanitizerSurvivesAnything() {
        var generator = SeededGenerator(seed: 2_024)

        for _ in 0..<400 {
            let text = randomText(count: Int.random(in: 0...400, using: &generator), generator: &generator)
            let cleaned = PromptSanitizer.clean(text)

            #expect(!cleaned.contains(PromptSanitizer.fenceOpen))
            #expect(!cleaned.contains(PromptSanitizer.fenceClose))
            #expect(!cleaned.contains("\u{0000}"))

            let fenced = PromptSanitizer.fence(text)
            if !fenced.isEmpty {
                let closings = fenced.components(separatedBy: PromptSanitizer.fenceClose).count - 1
                #expect(closings == 1, "Le contenu ne doit jamais pouvoir fermer son propre bloc")
            }
        }
    }
}
