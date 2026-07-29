import Foundation

/// Contrat asynchrone (pendant reseau du ProgramGenerator synchrone local).
public protocol AsyncProgramGenerator: Sendable {
    func generate(input: GeneratorInput, userNotes: String) async throws -> DraftProgram
}

/// Generation de programme par LLM : prompt -> appel HTTP -> extraction texte ->
/// nettoyage -> decodage DraftProgram -> validation des ids -> 1 retry avec
/// feedback en cas d'ids inconnus ou de JSON invalide.
public struct AIProgramGenerator: AsyncProgramGenerator {
    private let settings: AIProviderSettings
    private let client: AIHTTPClient
    private let catalog: ExerciseCatalog

    public init(settings: AIProviderSettings, client: AIHTTPClient, catalog: ExerciseCatalog) {
        self.settings = settings
        self.client = client
        self.catalog = catalog
    }

    public func generate(input: GeneratorInput, userNotes: String) async throws -> DraftProgram {
        let basePrompt = AIPromptBuilder.prompt(input: input, userNotes: userNotes, catalog: catalog)

        var lastFailure: String?
        for attempt in 0..<2 {
            try Task.checkCancellation()
            var prompt = basePrompt
            if attempt > 0, let lastFailure {
                prompt += "\n\nTa reponse precedente etait invalide : \(lastFailure)\nCorrige et renvoie UNIQUEMENT le JSON."
            }
            let request = try AIProviderRequest.build(settings: settings, prompt: prompt)
            let data = try await client.post(url: request.url, headers: request.headers, body: request.body)
            let text = try AIProviderRequest.extractText(from: data, kind: settings.kind)

            switch Self.parseAndValidate(text: text, catalog: catalog) {
            case .success(let draft):
                return draft
            case .failure(let reason):
                lastFailure = reason
            }
        }
        // Deux tentatives infructueuses : erreur typee selon la derniere cause.
        if let lastFailure, lastFailure.contains("exerciseId inconnus") {
            throw AIGeneratorError.unknownExercises([lastFailure])
        }
        throw AIGeneratorError.invalidJSON(lastFailure ?? "reponse invalide")
    }

    // MARK: - Parsing et validation

    private enum ParseResult {
        case success(DraftProgram)
        case failure(String)
    }

    private static func parseAndValidate(text: String, catalog: ExerciseCatalog) -> ParseResult {
        let cleaned = cleanJSON(text)
        guard let data = cleaned.data(using: .utf8),
              var draft = try? JSONDecoder().decode(DraftProgram.self, from: data) else {
            return .failure("le JSON ne correspond pas au schema demande")
        }

        let knownIds = Set(catalog.all.map(\.id))
        var unknown: [String] = []
        for sessionIndex in draft.sessions.indices {
            for exerciseIndex in draft.sessions[sessionIndex].exercises.indices {
                let exercise = draft.sessions[sessionIndex].exercises[exerciseIndex]
                if knownIds.contains(exercise.exerciseId) { continue }
                // Tentative de correction locale : l'id est-il une simple coquille
                // (pluriel, faute de frappe) d'un id connu ?
                if let match = nearestId(to: exercise.exerciseId, in: catalog) {
                    draft.sessions[sessionIndex].exercises[exerciseIndex].exerciseId = match.id
                    draft.sessions[sessionIndex].exercises[exerciseIndex].displayName = match.nameFr
                } else {
                    unknown.append(exercise.exerciseId)
                }
            }
        }
        guard unknown.isEmpty else {
            return .failure("exerciseId inconnus : \(unknown.joined(separator: ", "))")
        }
        guard !draft.sessions.isEmpty else {
            return .failure("aucune session dans le programme")
        }
        return .success(draft)
    }

    /// Correction locale d'un exerciseId invente par le LLM : on ne corrige que les
    /// "quasi-fautes de frappe" (pluriel, faute d'orthographe) d'un id existant,
    /// mesurees par distance de Levenshtein sur l'id lui-meme.
    ///
    /// Note : ExerciseCatalog.search(displayName) n'est PAS utilisable ici comme seul
    /// critere. Ce catalogue contient des noms qui se recouvrent ("Squat a la barre"
    /// est aussi une sous-chaine de "Hack squat a la barre" et de "Squat a la barre
    /// sur banc"), et ExerciseCatalog.search ne trie pas par pertinence : elle renvoie
    /// les correspondances dans l'ordre du fichier catalogue. Utiliser displayName
    /// pour corriger n'importe quel id inconnu aurait pour effet pervers de "corriger"
    /// silencieusement de faux exerciseId totalement invente (ex "Exo_Invente") des
    /// lors que le displayName fourni par le LLM correspond par ailleurs a un exercice
    /// existant - ce qui doit au contraire declencher un retry (voir
    /// unknownExerciseIdTriggersOneRetryThenSucceeds). La distance sur l'id lui-meme
    /// evite ce faux positif : "Barbell_Squats" est a distance 1 de "Barbell_Squat"
    /// (donc corrige localement), alors que "Exo_Invente" est a distance >= 7 de tout
    /// id du catalogue (donc traite comme inconnu, avec retry).
    private static let nearMissThreshold = 2

    private static func nearestId(to wrongId: String, in catalog: ExerciseCatalog) -> CatalogExercise? {
        let needle = wrongId.lowercased()
        var best: (exercise: CatalogExercise, distance: Int)?
        for exercise in catalog.all {
            let distance = levenshteinDistance(needle, exercise.id.lowercased())
            if best == nil || distance < best!.distance {
                best = (exercise, distance)
            }
        }
        guard let best, best.distance <= nearMissThreshold else { return nil }
        return best.exercise
    }

    private static func levenshteinDistance(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs)
        let b = Array(rhs)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }

        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = Swift.min(
                    previous[j] + 1,
                    current[j - 1] + 1,
                    previous[j - 1] + cost
                )
            }
            previous = current
        }
        return previous[b.count]
    }

    /// Retire les clotures markdown eventuelles et isole l'objet JSON
    /// (du premier "{" au dernier "}").
    private static func cleanJSON(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let first = cleaned.firstIndex(of: "{"), let last = cleaned.lastIndex(of: "}") else {
            return cleaned
        }
        return String(cleaned[first...last])
    }
}
