import Foundation

/// Construction des requetes HTTP et extraction du texte de reponse,
/// par provider. Formats verifies contre la documentation officielle
/// de chaque API (voir plan, Task 8 Step 1).
public enum AIProviderRequest {
    public static func build(
        settings: AIProviderSettings,
        prompt: String
    ) throws -> (url: URL, headers: [String: String], body: Data) {
        switch settings.kind {
        case .anthropic:
            let url = URL(string: "https://api.anthropic.com/v1/messages")!
            let headers = [
                "content-type": "application/json",
                "x-api-key": settings.apiKey,
                "anthropic-version": "2023-06-01",
            ]
            let payload: [String: Any] = [
                "model": settings.model,
                "max_tokens": 16000,
                "messages": [["role": "user", "content": prompt]],
            ]
            return (url, headers, try JSONSerialization.data(withJSONObject: payload))

        case .openai, .openAICompatible:
            let base: String
            if settings.kind == .openai {
                base = "https://api.openai.com/v1"
            } else {
                guard let raw = settings.baseURL, !raw.isEmpty else {
                    throw AIGeneratorError.invalidConfiguration
                }
                base = raw.hasSuffix("/") ? String(raw.dropLast()) : raw
            }
            guard let url = URL(string: base + "/chat/completions") else {
                throw AIGeneratorError.invalidConfiguration
            }
            let headers = [
                "Content-Type": "application/json",
                "Authorization": "Bearer \(settings.apiKey)",
            ]
            let payload: [String: Any] = [
                "model": settings.model,
                "messages": [["role": "user", "content": prompt]],
                "response_format": ["type": "json_object"],
            ]
            return (url, headers, try JSONSerialization.data(withJSONObject: payload))

        case .gemini:
            guard let url = URL(string:
                "https://generativelanguage.googleapis.com/v1beta/models/\(settings.model):generateContent"
            ) else {
                throw AIGeneratorError.invalidConfiguration
            }
            let headers = [
                "Content-Type": "application/json",
                "x-goog-api-key": settings.apiKey,
            ]
            let payload: [String: Any] = [
                "contents": [["parts": [["text": prompt]]]],
                "generationConfig": ["responseMimeType": "application/json"],
            ]
            return (url, headers, try JSONSerialization.data(withJSONObject: payload))
        }
    }

    public static func extractText(from data: Data, kind: AIProviderKind) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIGeneratorError.emptyResponse
        }
        let text: String?
        switch kind {
        case .anthropic:
            let content = json["content"] as? [[String: Any]]
            text = content?.first(where: { $0["type"] as? String == "text" })?["text"] as? String
        case .openai, .openAICompatible:
            let choices = json["choices"] as? [[String: Any]]
            let message = choices?.first?["message"] as? [String: Any]
            text = message?["content"] as? String
        case .gemini:
            let candidates = json["candidates"] as? [[String: Any]]
            let content = candidates?.first?["content"] as? [String: Any]
            let parts = content?["parts"] as? [[String: Any]]
            text = parts?.first?["text"] as? String
        }
        guard let text, !text.isEmpty else { throw AIGeneratorError.emptyResponse }
        return text
    }
}
