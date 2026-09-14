import Foundation
import Security

/// Stockage de la cle personnelle de l'utilisateur dans le Trousseau.
///
/// La cle n'est JAMAIS ecrite dans le depot, dans `UserDefaults`, dans un
/// export ou dans un journal. Elle ne quitte le Trousseau que pour former
/// l'en-tete d'autorisation d'une requete.
enum AIKeychain {
    private static let service = "com.cyril.Muscu.ai"
    private static let account = "provider-api-key"

    @discardableResult
    static func store(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return remove() }

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)

        query[kSecValueData as String] = data
        // La cle ne sort pas de l'appareil et n'est lisible que deverrouille :
        // elle n'a aucune raison d'etre sauvegardee ni synchronisee.
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func remove() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    static var hasKey: Bool { read() != nil }

    /// Masque une cle pour l'afficher : on montre qu'elle est là, jamais sa
    /// valeur.
    static func masked(_ key: String) -> String {
        guard key.count > 6 else { return String(repeating: "•", count: max(key.count, 4)) }
        return String(repeating: "•", count: 8) + key.suffix(4)
    }
}
