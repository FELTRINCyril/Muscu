import Foundation

/// Comparaison de texte tolerante, partagee par la recherche du catalogue et
/// la correspondance des colonnes d'import : les deux doivent accepter
/// « developpe couche » pour « Développé couché ».
public enum TextMatching {
    /// Normalisation : sans accent, sans casse, ponctuation reduite a des
    /// espaces, espaces compactes. Le resultat sert de cle de comparaison, il
    /// n'est jamais affiche.
    public static func normalize(_ text: String) -> String {
        let folded = text.folding(
            options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
            locale: Locale(identifier: "fr_FR")
        )
        let scalars = folded.map { character -> Character in
            character.isLetter || character.isNumber ? character : " "
        }
        return String(scalars)
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
    }

    public static func tokens(_ text: String) -> [String] {
        normalize(text).split(separator: " ").map(String.init)
    }

    /// Distance de Damerau-Levenshtein (insertion, suppression, substitution,
    /// TRANSPOSITION). La transposition compte pour 1 : « devloppe » et
    /// « develppe » sont des fautes de frappe de meme gravite.
    public static func editDistance(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        if left.isEmpty { return right.count }
        if right.isEmpty { return left.count }

        var previousPrevious = [Int](repeating: 0, count: right.count + 1)
        var previous = Array(0...right.count)
        var current = [Int](repeating: 0, count: right.count + 1)

        for i in 1...left.count {
            current[0] = i
            for j in 1...right.count {
                let cost = left[i - 1] == right[j - 1] ? 0 : 1
                current[j] = min(
                    previous[j] + 1,
                    current[j - 1] + 1,
                    previous[j - 1] + cost
                )
                if i > 1, j > 1, left[i - 1] == right[j - 2], left[i - 2] == right[j - 1] {
                    current[j] = min(current[j], previousPrevious[j - 2] + 1)
                }
            }
            previousPrevious = previous
            previous = current
            current = [Int](repeating: 0, count: right.count + 1)
        }

        return previous[right.count]
    }

    /// Nombre de fautes tolerees pour un mot de cette longueur. Un mot court
    /// n'a droit a aucune tolerance : « bras » et « gras » sont deux mots.
    public static func tolerance(forLength length: Int) -> Int {
        switch length {
        case ..<5: return 0
        case 5...7: return 1
        default: return 2
        }
    }

    /// Vrai si `token` correspond a `reference` : egalite, prefixe, ou
    /// distance d'edition dans la tolerance.
    public static func matches(token: String, reference: String) -> Bool {
        if reference == token { return true }
        if token.count >= 3, reference.hasPrefix(token) { return true }
        let allowed = tolerance(forLength: max(token.count, reference.count))
        guard allowed > 0 else { return false }
        return editDistance(token, reference) <= allowed
    }
}
