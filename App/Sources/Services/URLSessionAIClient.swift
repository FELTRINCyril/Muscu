import Foundation
import MuscuEngine

// Implementation URLSession du client HTTP injecte dans AIProgramGenerator.
// Timeout volontairement long (60 s) : la generation d'un programme complet
// peut prendre plusieurs dizaines de secondes selon le provider.
struct URLSessionAIClient: AIHTTPClient {
    func post(url: URL, headers: [String: String], body: Data) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 60
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw AIGeneratorError.httpError(http.statusCode, String(bodyText.prefix(300)))
        }
        return data
    }
}
