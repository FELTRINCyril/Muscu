import Foundation
import Security
import MuscuEngine

// Configuration de la generation IA : provider selectionne, cle API par
// provider (Keychain), modele par provider et URL de base (UserDefaults).
enum AIProviderConfig {
    private static let providerKey = "aiProviderKind"
    private static let baseURLKey = "aiProviderBaseURL"

    static var selectedProvider: AIProviderKind {
        get {
            guard let raw = UserDefaults.standard.string(forKey: providerKey),
                  let kind = AIProviderKind(rawValue: raw) else { return .anthropic }
            return kind
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: providerKey) }
    }

    // URL de base, utilisee uniquement par openAICompatible (ex: https://api.exemple.com/v1).
    static var baseURL: String {
        get { UserDefaults.standard.string(forKey: baseURLKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: baseURLKey) }
    }

    static func model(for kind: AIProviderKind) -> String {
        UserDefaults.standard.string(forKey: "aiProviderModel.\(kind.rawValue)")
            ?? kind.defaultModel ?? ""
    }

    static func setModel(_ model: String, for kind: AIProviderKind) {
        UserDefaults.standard.set(model, forKey: "aiProviderModel.\(kind.rawValue)")
    }

    static func apiKey(for kind: AIProviderKind) -> String {
        KeychainHelper.read(account: "aiProviderApiKey.\(kind.rawValue)") ?? ""
    }

    static func setApiKey(_ key: String, for kind: AIProviderKind) {
        if key.isEmpty {
            KeychainHelper.delete(account: "aiProviderApiKey.\(kind.rawValue)")
        } else {
            KeychainHelper.save(account: "aiProviderApiKey.\(kind.rawValue)", value: key)
        }
    }

    /// Configure = cle + modele non vides pour le provider choisi,
    /// et URL de base valide si le provider l'exige.
    static var isConfigured: Bool {
        let kind = selectedProvider
        guard !apiKey(for: kind).isEmpty, !model(for: kind).isEmpty else { return false }
        if kind.requiresBaseURL {
            guard let url = URL(string: baseURL), url.scheme == "https" else { return false }
        }
        return true
    }

    /// Settings agreges pour le generateur IA (Task 8).
    static func currentSettings() -> AIProviderSettings? {
        guard isConfigured else { return nil }
        let kind = selectedProvider
        return AIProviderSettings(
            kind: kind,
            apiKey: apiKey(for: kind),
            model: model(for: kind),
            baseURL: kind.requiresBaseURL ? baseURL : nil
        )
    }
}

// Wrapper minimal autour de kSecClassGenericPassword pour stocker une
// valeur sensible unique par compte, sous un service dedie a l'app.
enum KeychainHelper {
    private static let service = "com.cyril.muscu.ai"

    static func save(account: String, value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        // On supprime l'entree existante avant de la reecrire : plus simple
        // et plus robuste qu'un SecItemUpdate face aux erreurs de type.
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
