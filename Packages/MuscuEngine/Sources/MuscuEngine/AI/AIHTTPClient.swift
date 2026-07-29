import Foundation

/// Client HTTP injectable : URLSession cote app, mock dans les tests.
/// MuscuEngine ne fait jamais d'appel reseau direct.
public protocol AIHTTPClient: Sendable {
    func post(url: URL, headers: [String: String], body: Data) async throws -> Data
}

/// Erreurs de la generation IA, exploitables par l'UI.
public enum AIGeneratorError: Error, Sendable {
    case invalidConfiguration
    case httpError(Int, String)
    case emptyResponse
    case invalidJSON(String)
    case unknownExercises([String])
}
