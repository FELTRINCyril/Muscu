import Foundation

/// Lien de demonstration personnel attache a un exercice (video, article).
///
/// Seuls les liens web absolus sont acceptes : un lien `javascript:`, `file:`
/// ou un schema d'application ouvert depuis une archive importee ferait
/// autre chose que montrer un mouvement.
public enum DemoLink {
    /// Longueur maximale conservee, alignee sur la validation d'import.
    public static let maximumLength = 2_000

    /// Lien normalise (espaces retires) s'il est acceptable, sinon nil.
    public static func normalized(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return isAcceptable(trimmed) ? trimmed : nil
    }

    /// Vrai pour une URL `http` ou `https` absolue, avec un hote, sans
    /// espace et de longueur raisonnable.
    public static func isAcceptable(_ text: String) -> Bool {
        guard !text.isEmpty,
              text.count <= maximumLength,
              !text.contains(where: \.isWhitespace),
              let components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty else {
            return false
        }
        return true
    }
}
