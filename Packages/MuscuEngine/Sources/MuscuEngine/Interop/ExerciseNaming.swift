import Foundation

/// Conventions de nommage des exports d'autres applications.
///
/// Strong, Hevy et d'autres ecrivent le materiel entre parentheses en fin de
/// nom : « Deadlift (Barbell) ». Le nom seul ne trouvait pas toujours son
/// exercice au catalogue, ou trouvait la mauvaise variante (« Soulevé de
/// terre » aux haltères pour un soulevé a la barre). Inspire de
/// `exerciseNaming.ts` d'Ischys (MIT).
///
/// Volontairement prudent : un suffixe inconnu ne produit aucun materiel
/// plutot qu'une supposition — un mauvais materiel fausserait le repos par
/// defaut, le calculateur de disques et la correspondance elle-meme.
public enum ExerciseNaming {
    /// Mots de materiel reconnus, vers le vocabulaire du catalogue.
    static let equipmentBySuffix: [String: String] = [
        "barbell": "barbell",
        "barre": "barbell",
        "dumbbell": "dumbbell",
        "dumbbells": "dumbbell",
        "haltere": "dumbbell",
        "halteres": "dumbbell",
        "machine": "machine",
        "smith machine": "machine",
        "cable": "cable",
        "poulie": "cable",
        "bodyweight": "body only",
        "body weight": "body only",
        "poids du corps": "body only",
        "kettlebell": "kettlebells",
        "kettlebells": "kettlebells",
        "band": "bands",
        "bands": "bands",
        "resistance band": "bands",
        "elastique": "bands",
        "ez bar": "e-z curl bar",
        "ez curl bar": "e-z curl bar",
        "barre ez": "e-z curl bar",
        // La normalisation remplace le tiret par une espace.
        "e z bar": "e-z curl bar",
        "e z curl bar": "e-z curl bar",
    ]

    /// Nom sans le materiel et materiel du catalogue, quand le nom se
    /// termine par un materiel reconnu entre parentheses. `nil` sinon.
    public static func equipmentSuffix(in name: String) -> (baseName: String, equipment: String)? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix(")"),
              let open = trimmed.lastIndex(of: "(") else { return nil }
        let inner = trimmed[trimmed.index(after: open)..<trimmed.index(before: trimmed.endIndex)]
        guard !inner.contains("("), !inner.contains(")") else { return nil }
        let key = TextMatching.normalize(String(inner))
        guard let equipment = equipmentBySuffix[key] else { return nil }
        let base = trimmed[..<open].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return nil }
        return (base, equipment)
    }
}
