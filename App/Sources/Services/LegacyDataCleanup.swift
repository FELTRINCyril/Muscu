import Foundation
import Security

/// Retire les réglages de l'ancien écran IA expérimental, supprimé avant
/// diffusion parce qu'aucune génération ne les utilisait. Cela évite de
/// conserver indéfiniment une clé API devenue inaccessible à l'utilisateur.
enum LegacyDataCleanup {
    static func run() {
        UserDefaults.standard.removeObject(forKey: "aiProviderBaseURL")
        UserDefaults.standard.removeObject(forKey: "aiProviderModel")

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.cyril.muscu.ai",
            kSecAttrAccount as String: "aiProviderApiKey",
        ]
        SecItemDelete(query as CFDictionary)
    }
}
