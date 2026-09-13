import Foundation
import MuscuEngine

/// Mise en forme des charges. La valeur stockee est TOUJOURS en kilogrammes
/// (cf. `MuscuEngine.MassUnit`) : ce formateur ne fait que l'affichage.
///
/// Volontairement non isole sur le MainActor : l'historique, les graphiques
/// et les exports formatent des charges hors du fil principal.
enum WeightFormatter {
    /// Locale d'affichage des nombres. L'interface est aujourd'hui en
    /// francais uniquement ; la localisation complete est traitee en phase 9.
    static let displayLocale = Locale(identifier: "fr_FR")

    static func string(kilograms: Double, unit: MassUnit = .kilograms) -> String {
        let value = unit.fromKilograms(kilograms)
        return number(value) + " " + unit.symbol
    }

    /// Nombre seul, sans unite : utilise quand l'unite est deja affichee
    /// ailleurs (libelle de colonne, suffixe de champ).
    static func number(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        let formatter = NumberFormatter()
        formatter.locale = displayLocale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
    }
}
