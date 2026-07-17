import Foundation
import Security

// Configuration (non utilisee pour l'instant) d'un futur provider de
// generation de programmes par IA. Aucun appel reseau ici : uniquement le
// stockage des reglages. La cle API est sensible -> Keychain, le reste
// (URL, modele) -> UserDefaults.
enum AIProviderConfig {
    private static let baseURLKey = "aiProviderBaseURL"
    private static let modelKey = "aiProviderModel"
    private static let apiKeyAccount = "aiProviderApiKey"

    static var baseURL: String {
        get { UserDefaults.standard.string(forKey: baseURLKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: baseURLKey) }
    }

    static var model: String {
        get { UserDefaults.standard.string(forKey: modelKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: modelKey) }
    }

    static var apiKey: String {
        get { KeychainHelper.read(account: apiKeyAccount) ?? "" }
        set {
            if newValue.isEmpty {
                KeychainHelper.delete(account: apiKeyAccount)
            } else {
                KeychainHelper.save(account: apiKeyAccount, value: newValue)
            }
        }
    }

    // Configure des lors qu'une cle API non vide est enregistree.
    static var isConfigured: Bool {
        !apiKey.isEmpty
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
