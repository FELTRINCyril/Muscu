import Foundation
import SwiftUI
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

    /// Copie de l'unite du profil, lisible hors du fil principal et hors
    /// d'une vue (presentations, resumes, intents). La source de verite
    /// reste `AthleteProfile.massUnit` : `RootTabView` recopie ici chaque
    /// changement.
    static let preferredUnitKey = "preferredMassUnit"

    static var preferredUnit: MassUnit {
        UserDefaults.standard.string(forKey: preferredUnitKey).flatMap(MassUnit.init(rawValue:)) ?? .kilograms
    }

    static func storePreferredUnit(_ unit: MassUnit) {
        guard UserDefaults.standard.string(forKey: preferredUnitKey) != unit.rawValue else { return }
        UserDefaults.standard.set(unit.rawValue, forKey: preferredUnitKey)
    }

    /// Charge avec son unite, convertie dans l'unite demandee (par defaut,
    /// celle du profil).
    static func string(kilograms: Double, unit: MassUnit = preferredUnit) -> String {
        number(kilograms: kilograms, unit: unit) + " " + unit.symbol
    }

    /// Charge convertie, SANS unite : pour un champ dont le suffixe affiche
    /// deja l'unite.
    static func number(kilograms: Double, unit: MassUnit = preferredUnit) -> String {
        number(unit.fromKilograms(kilograms))
    }

    /// Nombre seul, sans conversion ni unite : utilise quand la valeur est
    /// deja dans l'unite affichee.
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

extension EnvironmentValues {
    /// Unite d'affichage des charges, injectee par `RootTabView` depuis le
    /// profil. Une vue qui la lit se redessine quand l'utilisateur change
    /// d'unite, sans attendre une autre modification.
    @Entry var massUnit: MassUnit = .kilograms
}
