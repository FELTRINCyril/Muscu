import Foundation
import MuscuEngine

/// Fournisseur de coach IA, quel qu'il soit.
///
/// L'application ne connait que ce protocole : un fournisseur distant, un
/// service mock deterministe et un futur backend gere sont interchangeables,
/// et aucun ecran ne depend de l'un d'eux.
protocol AICoachService: Sendable {
    /// Identifiant du modele ou du service, conserve dans le journal.
    var identifier: String { get }
    /// Faux tant que rien n'est configure : l'interface doit alors proposer
    /// le generateur local au lieu de laisser croire que l'IA fonctionne.
    var isConfigured: Bool { get }

    func send(_ request: AICoachRequest, timeoutSeconds: Int) async throws -> AICoachResponse
}

/// Service mock DETERMINISTE : previews, tests et rien d'autre.
///
/// Il n'est jamais propose comme un vrai coach — le faire reviendrait a
/// presenter un gabarit local comme une reponse de modele.
final class MockAICoachService: AICoachService, @unchecked Sendable {
    let identifier = "mock-deterministe"
    var isConfigured: Bool { true }

    /// Erreur a lever au prochain appel, pour tester les chemins d'echec.
    var nextError: AICoachError?
    /// Reponse imposee, quand un test veut un contenu precis.
    var nextResponse: AICoachResponse?
    private(set) var receivedRequests: [AICoachRequest] = []

    init(nextError: AICoachError? = nil, nextResponse: AICoachResponse? = nil) {
        self.nextError = nextError
        self.nextResponse = nextResponse
    }

    func send(_ request: AICoachRequest, timeoutSeconds: Int) async throws -> AICoachResponse {
        receivedRequests.append(request)
        if let nextError { throw nextError }
        if let nextResponse { return nextResponse }
        return Self.deterministicResponse(for: request)
    }

    /// Reponse reproductible : meme requete, meme sortie. Construite a partir
    /// des exercices AUTORISES, jamais d'identifiants inventes.
    static func deterministicResponse(for request: AICoachRequest) -> AICoachResponse {
        guard request.capability.producesDraft else {
            return AICoachResponse(
                capability: request.capability,
                modelIdentifier: "mock-deterministe",
                explanation: "Réponse de test déterministe."
            )
        }

        let days = min(max(request.context.daysPerWeek ?? 3, 1), 6)
        let ids = request.context.allowedExerciseIds.sorted()
        guard !ids.isEmpty else {
            return AICoachResponse(
                capability: request.capability,
                modelIdentifier: "mock-deterministe",
                explanation: "Aucun exercice disponible.",
                program: AIProgramDraft(name: "Programme mock", sessions: [])
            )
        }

        let perSession = max(1, min(4, ids.count / days == 0 ? 1 : ids.count / days))
        var sessions: [AISessionDraft] = []
        for day in 0..<days {
            let slice = (0..<perSession).compactMap { index -> AIExerciseDraft? in
                let position = (day * perSession + index) % ids.count
                return AIExerciseDraft(
                    exerciseId: ids[position],
                    sets: 3,
                    repsLower: 8,
                    repsUpper: 10,
                    restSeconds: 90
                )
            }
            sessions.append(AISessionDraft(name: "Séance \(day + 1)", exercises: slice))
        }

        return AICoachResponse(
            capability: request.capability,
            modelIdentifier: "mock-deterministe",
            explanation: "Programme de test sur \(days) jour(s).",
            program: AIProgramDraft(name: "Programme mock", notes: "", sessions: sessions)
        )
    }
}
