import Foundation
import MuscuEngine

/// Fournisseur distant en mode « clé personnelle » (BYOK).
///
/// Trois règles tenues ici :
/// 1. la clé vient du Trousseau et ne sert qu'à former l'en-tête
///    d'autorisation : elle n'est ni journalisée, ni renvoyée ;
/// 2. la réponse doit être un JSON conforme au schéma — aucun programme
///    n'est reconstruit en analysant du texte libre ;
/// 3. délai maximal et annulation sont portés par la requête elle-même.
final class RemoteAICoachService: AICoachService, @unchecked Sendable {
    private let endpoint: URL
    private let modelName: String
    private let apiKey: String
    private let session: URLSession

    let identifier: String
    var isConfigured: Bool { !apiKey.isEmpty }

    init?(endpoint: String, model: String, apiKey: String?, session: URLSession = .shared) {
        guard let url = URL(string: endpoint), url.scheme?.hasPrefix("http") == true,
              !model.isEmpty, let apiKey, !apiKey.isEmpty else { return nil }
        self.endpoint = url
        self.modelName = model
        self.apiKey = apiKey
        self.session = session
        self.identifier = model
    }

    func send(_ request: AICoachRequest, timeoutSeconds: Int) async throws -> AICoachResponse {
        let payload = try Self.encodePayload(request, model: modelName)

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = TimeInterval(timeoutSeconds)
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = payload

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let error as URLError where error.code == .cancelled {
            throw AICoachError.cancelled
        } catch let error as URLError where error.code == .timedOut {
            throw AICoachError.timedOut(seconds: timeoutSeconds)
        } catch {
            // Le message du transport peut contenir l'URL, jamais la clé :
            // elle n'est que dans un en-tête.
            throw AICoachError.transport(error.localizedDescription)
        }

        try Task.checkCancellation()

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AICoachError.transport(Self.message(forStatus: http.statusCode))
        }

        return try Self.decodeResponse(data, expecting: request.capability, model: modelName)
    }

    // MARK: - Encodage

    /// Charge utile compatible avec les API de complétion de type « chat ».
    ///
    /// La consigne système rappelle que le contenu délimité est une donnée ;
    /// la requête métier part en JSON, sans reformulation en langage naturel.
    static func encodePayload(_ request: AICoachRequest, model: String) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let requestJSON = String(data: try encoder.encode(request), encoding: .utf8) ?? "{}"

        let system = """
        Tu es un assistant de programmation sportive. Réponds UNIQUEMENT par un objet JSON conforme au schéma \
        AICoachResponse (schemaVersion, capability, modelIdentifier, explanation, program, adaptations, substitutions). \
        N’utilise que les identifiants d’exercices fournis dans allowedExerciseIds. \
        Ne donne aucun diagnostic médical et ne propose jamais de test maximal ni de progression supérieure à 10 %.
        \(PromptSanitizer.untrustedContentInstruction)
        """

        let body: [String: Any] = [
            "model": model,
            "temperature": 0,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": requestJSON],
            ],
        ]
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }

    // MARK: - Décodage

    static func decodeResponse(
        _ data: Data,
        expecting capability: AICoachCapability,
        model: String
    ) throws -> AICoachResponse {
        guard !data.isEmpty else { throw AICoachError.malformedResponse("réponse vide") }

        // Enveloppe du fournisseur : on en extrait le contenu, puis on décode
        // NOTRE schéma. Un contenu absent est une erreur, pas un texte à
        // interpréter.
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AICoachError.malformedResponse("JSON illisible")
        }
        guard let choices = root["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AICoachError.malformedResponse("aucun contenu dans la réponse")
        }
        guard let contentData = content.data(using: .utf8) else {
            throw AICoachError.malformedResponse("contenu non décodable")
        }

        let decoded: AICoachResponse
        do {
            decoded = try JSONDecoder().decode(AICoachResponse.self, from: contentData)
        } catch {
            throw AICoachError.malformedResponse("le contenu ne suit pas le schéma attendu")
        }

        var normalized = decoded
        // Le modèle ne décide pas de sa propre identité dans notre journal.
        normalized.modelIdentifier = model
        normalized.explanation = PromptSanitizer.clean(decoded.explanation)

        if let error = AIResponseValidator.check(normalized, expecting: capability) { throw error }
        return normalized
    }

    static func message(forStatus status: Int) -> String {
        switch status {
        case 401, 403: return "clé refusée par le service (code \(status))"
        case 404: return "adresse de service introuvable (code 404)"
        case 429: return "trop de demandes, réessayez plus tard (code 429)"
        case 500...599: return "le service est indisponible (code \(status))"
        default: return "code de réponse inattendu (\(status))"
        }
    }
}
