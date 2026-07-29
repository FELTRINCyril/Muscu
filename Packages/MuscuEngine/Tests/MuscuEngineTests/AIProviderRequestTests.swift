import Foundation
import Testing
@testable import MuscuEngine

struct AIProviderRequestTests {
    private func settings(_ kind: AIProviderKind, baseURL: String? = nil) -> AIProviderSettings {
        AIProviderSettings(kind: kind, apiKey: "test-key", model: "test-model", baseURL: baseURL)
    }

    @Test func anthropicRequestShape() throws {
        let request = try AIProviderRequest.build(settings: settings(.anthropic), prompt: "PROMPT")
        #expect(request.url.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(request.headers["x-api-key"] == "test-key")
        #expect(request.headers["anthropic-version"] == "2023-06-01")
        let json = try JSONSerialization.jsonObject(with: request.body) as! [String: Any]
        #expect(json["model"] as? String == "test-model")
        #expect(json["max_tokens"] as? Int == 16000)
    }

    @Test func openAIRequestShape() throws {
        let request = try AIProviderRequest.build(settings: settings(.openai), prompt: "PROMPT")
        #expect(request.url.absoluteString == "https://api.openai.com/v1/chat/completions")
        #expect(request.headers["Authorization"] == "Bearer test-key")
    }

    @Test func openAICompatibleUsesBaseURL() throws {
        let request = try AIProviderRequest.build(
            settings: settings(.openAICompatible, baseURL: "https://llm.exemple.com/v1/"),
            prompt: "PROMPT"
        )
        #expect(request.url.absoluteString == "https://llm.exemple.com/v1/chat/completions")
    }

    @Test func openAICompatibleWithoutBaseURLThrows() {
        #expect(throws: AIGeneratorError.self) {
            _ = try AIProviderRequest.build(settings: settings(.openAICompatible), prompt: "P")
        }
    }

    @Test func geminiRequestShape() throws {
        let request = try AIProviderRequest.build(settings: settings(.gemini), prompt: "PROMPT")
        #expect(request.url.absoluteString
            == "https://generativelanguage.googleapis.com/v1beta/models/test-model:generateContent")
        #expect(request.headers["x-goog-api-key"] == "test-key")
    }

    @Test func extractTextAnthropic() throws {
        let data = #"{"content":[{"type":"text","text":"HELLO"}],"stop_reason":"end_turn"}"#.data(using: .utf8)!
        #expect(try AIProviderRequest.extractText(from: data, kind: .anthropic) == "HELLO")
    }

    @Test func extractTextOpenAI() throws {
        let data = #"{"choices":[{"message":{"role":"assistant","content":"HELLO"}}]}"#.data(using: .utf8)!
        #expect(try AIProviderRequest.extractText(from: data, kind: .openai) == "HELLO")
        #expect(try AIProviderRequest.extractText(from: data, kind: .openAICompatible) == "HELLO")
    }

    @Test func extractTextGemini() throws {
        let data = #"{"candidates":[{"content":{"parts":[{"text":"HELLO"}]}}]}"#.data(using: .utf8)!
        #expect(try AIProviderRequest.extractText(from: data, kind: .gemini) == "HELLO")
    }

    @Test func extractTextThrowsOnGarbage() {
        let data = #"{"error":"nope"}"#.data(using: .utf8)!
        #expect(throws: AIGeneratorError.self) {
            _ = try AIProviderRequest.extractText(from: data, kind: .anthropic)
        }
    }
}
