import Foundation

/// Deduction du type de charge a partir des donnees du catalogue. Regroupee
/// ici pour que l'app, le generateur et les analyses partagent exactement la
/// meme interpretation, au lieu de la redecrire dans chaque vue.
///
/// La deduction est une VALEUR PAR DEFAUT : une prescription qui declare son
/// type de charge explicitement l'emporte toujours.
public enum ExerciseClassification {
    /// Materiels pour lesquels la charge deplacee est le poids de corps.
    static let bodyweightEquipment: Set<String> = ["body only"]

    /// Materiels utilises pour ALLEGER un mouvement (traction assistee).
    /// Les elastiques servent aussi de resistance ajoutee : cette deduction
    /// reste une valeur par defaut prudente, redefinissable exercice par
    /// exercice, et ne produit jamais de record de charge.
    static let assistedEquipment: Set<String> = ["bands"]

    public static func loadKind(equipment: String?) -> LoadKind {
        guard let equipment, !equipment.isEmpty else { return .unknown }
        if bodyweightEquipment.contains(equipment) { return .bodyweight }
        if assistedEquipment.contains(equipment) { return .assisted }
        return .external
    }

    public static func loadKind(for exercise: CatalogExercise) -> LoadKind {
        loadKind(equipment: exercise.equipment)
    }

    /// Un exercice au poids du corps peut devenir `weighted` des qu'un lest
    /// est saisi : la progression porte alors sur le lest seul.
    public static func resolvedLoadKind(base: LoadKind, enteredWeight: Double) -> LoadKind {
        guard base == .bodyweight, enteredWeight > 0 else { return base }
        return .weighted
    }
}
