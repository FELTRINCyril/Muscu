import Foundation
import Testing
@testable import MuscuEngine

/// Mock : rejoue des reponses pre-enregistrees et memorise les requetes.
final class MockAIHTTPClient: AIHTTPClient, @unchecked Sendable {
    var responses: [Data]
    private(set) var requests: [(url: URL, headers: [String: String], body: Data)] = []

    init(responses: [Data]) {
        self.responses = responses
    }

    func post(url: URL, headers: [String: String], body: Data) async throws -> Data {
        requests.append((url, headers, body))
        guard !responses.isEmpty else { throw AIGeneratorError.emptyResponse }
        return responses.removeFirst()
    }
}

private func anthropicResponse(text: String) -> Data {
    let payload: [String: Any] = ["content": [["type": "text", "text": text]]]
    return try! JSONSerialization.data(withJSONObject: payload)
}

private let validDraftJSON = """
{"name": "Programme test", "notes": "",
 "sessions": [{"name": "Seance A", "warmupEnabled": true,
   "exercises": [{"exerciseId": "Barbell_Squat", "displayName": "Squat à la barre",
     "sets": 4, "repsLower": 6, "repsUpper": 10, "restSeconds": 120, "percentOneRepMax": null}]}]}
"""

private func makeInput() -> GeneratorInput {
    GeneratorInput(
        goal: .hypertrophy, experience: .intermediate, daysPerWeek: 1,
        sessionMinutes: 60, equipment: .fullGym, splitPreference: .auto,
        priorityMuscles: [], avoidAreas: []
    )
}

private func makeSettings() -> AIProviderSettings {
    AIProviderSettings(kind: .anthropic, apiKey: "k", model: "m", baseURL: nil)
}

struct AIProgramGeneratorTests {
    @Test func validResponseProducesDraft() async throws {
        let catalog = try ExerciseCatalog.load()
        let client = MockAIHTTPClient(responses: [anthropicResponse(text: validDraftJSON)])
        let generator = AIProgramGenerator(settings: makeSettings(), client: client, catalog: catalog)
        let draft = try await generator.generate(input: makeInput(), userNotes: "")
        #expect(draft.sessions.count == 1)
        #expect(draft.sessions[0].exercises[0].exerciseId == "Barbell_Squat")
        #expect(client.requests.count == 1)
    }

    @Test func markdownFencedResponseIsCleaned() async throws {
        let catalog = try ExerciseCatalog.load()
        let fenced = "```json\n" + validDraftJSON + "\n```"
        let client = MockAIHTTPClient(responses: [anthropicResponse(text: fenced)])
        let generator = AIProgramGenerator(settings: makeSettings(), client: client, catalog: catalog)
        let draft = try await generator.generate(input: makeInput(), userNotes: "")
        #expect(draft.sessions.count == 1)
    }

    @Test func unknownExerciseIdTriggersOneRetryThenSucceeds() async throws {
        let catalog = try ExerciseCatalog.load()
        let bad = validDraftJSON.replacingOccurrences(of: "Barbell_Squat", with: "Exo_Invente")
        let client = MockAIHTTPClient(responses: [
            anthropicResponse(text: bad),
            anthropicResponse(text: validDraftJSON),
        ])
        let generator = AIProgramGenerator(settings: makeSettings(), client: client, catalog: catalog)
        let draft = try await generator.generate(input: makeInput(), userNotes: "")
        #expect(draft.sessions[0].exercises[0].exerciseId == "Barbell_Squat")
        #expect(client.requests.count == 2, "un retry exactement")
        // Le second prompt contient le feedback d'erreur.
        let secondBody = String(data: client.requests[1].body, encoding: .utf8) ?? ""
        #expect(secondBody.contains("Exo_Invente"))
    }

    @Test func unknownExerciseIdTwiceThrows() async throws {
        let catalog = try ExerciseCatalog.load()
        let bad = validDraftJSON.replacingOccurrences(of: "Barbell_Squat", with: "Exo_Invente")
        let client = MockAIHTTPClient(responses: [
            anthropicResponse(text: bad),
            anthropicResponse(text: bad),
        ])
        let generator = AIProgramGenerator(settings: makeSettings(), client: client, catalog: catalog)
        await #expect(throws: AIGeneratorError.self) {
            _ = try await generator.generate(input: makeInput(), userNotes: "")
        }
        #expect(client.requests.count == 2)
    }

    @Test func nearMissExerciseIdIsFixedByNameMatch() async throws {
        // displayName connu mais exerciseId errone -> correction par recherche du nom.
        let catalog = try ExerciseCatalog.load()
        let nearMiss = validDraftJSON.replacingOccurrences(of: "Barbell_Squat", with: "Barbell_Squats")
        let client = MockAIHTTPClient(responses: [anthropicResponse(text: nearMiss)])
        let generator = AIProgramGenerator(settings: makeSettings(), client: client, catalog: catalog)
        let draft = try await generator.generate(input: makeInput(), userNotes: "")
        #expect(draft.sessions[0].exercises[0].exerciseId == "Barbell_Squat")
        #expect(client.requests.count == 1, "corrige localement, pas de retry")
    }

    @Test func invalidJSONThrows() async throws {
        let catalog = try ExerciseCatalog.load()
        let client = MockAIHTTPClient(responses: [
            anthropicResponse(text: "Voici votre programme : faites du sport."),
            anthropicResponse(text: "toujours pas du JSON"),
        ])
        let generator = AIProgramGenerator(settings: makeSettings(), client: client, catalog: catalog)
        await #expect(throws: AIGeneratorError.self) {
            _ = try await generator.generate(input: makeInput(), userNotes: "")
        }
    }
}
