import Foundation

/// Fournisseurs LLM supportes pour la generation de programme.
/// openAICompatible = n'importe quel endpoint au format OpenAI (Cursor, etc.).
public enum AIProviderKind: String, Codable, CaseIterable, Sendable {
    case anthropic
    case openai
    case gemini
    case openAICompatible

    public var displayName: String {
        switch self {
        case .anthropic: return "Claude (Anthropic)"
        case .openai: return "ChatGPT (OpenAI)"
        case .gemini: return "Gemini (Google)"
        case .openAICompatible: return "Compatible OpenAI (Cursor...)"
        }
    }

    /// Modele par defaut propose dans les reglages (nil = a saisir obligatoirement).
    public var defaultModel: String? {
        switch self {
        case .anthropic: return "claude-opus-5"
        case .openai: return nil
        case .gemini: return nil
        case .openAICompatible: return nil
        }
    }

    public var requiresBaseURL: Bool {
        self == .openAICompatible
    }
}

/// Parametres complets d'un appel LLM (agreges par l'app, consommes par le moteur).
public struct AIProviderSettings: Sendable {
    public let kind: AIProviderKind
    public let apiKey: String
    public let model: String
    public let baseURL: String?  // requis pour openAICompatible uniquement

    public init(kind: AIProviderKind, apiKey: String, model: String, baseURL: String?) {
        self.kind = kind
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
    }
}
