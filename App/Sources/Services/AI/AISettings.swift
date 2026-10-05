import Foundation
import MuscuEngine

/// Reglages du coach IA.
///
/// Tout est conserve dans `UserDefaults` SAUF la cle, qui vit dans le
/// Trousseau. Aucun de ces reglages n'est une donnee d'entrainement : ils ne
/// rentrent donc pas dans le modele de donnees.
@MainActor
enum AISettings {
    private enum Key {
        static let enabled = "ai.enabled"
        static let consent = "ai.consent"
        static let usage = "ai.usage"
        static let monthlyLimit = "ai.monthlyLimit"
        static let endpoint = "ai.endpoint"
        static let model = "ai.model"
    }

    /// Drapeau de fonctionnalite. **Desactive par defaut** : la roadmap exige
    /// que l'IA reste derriere un drapeau tant que securite, politique de
    /// confidentialite et evaluations ne sont pas validees.
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Key.enabled) }
        set { UserDefaults.standard.set(newValue, forKey: Key.enabled) }
    }

    static var consent: AIConsent {
        get {
            guard let data = UserDefaults.standard.data(forKey: Key.consent),
                  let value = try? JSONDecoder().decode(AIConsent.self, from: data) else { return .none }
            return value
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults.standard.set(data, forKey: Key.consent)
        }
    }

    static var usage: AIUsage {
        get {
            guard let data = UserDefaults.standard.data(forKey: Key.usage),
                  let value = try? JSONDecoder().decode(AIUsage.self, from: data) else {
                return AIUsage(month: AIBudgetGuard.month(for: .now))
            }
            return value
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults.standard.set(data, forKey: Key.usage)
        }
    }

    static var budget: AIBudget {
        get {
            let stored = UserDefaults.standard.object(forKey: Key.monthlyLimit) as? Int
            return AIBudget(monthlyRequestLimit: stored ?? AIBudget.default.monthlyRequestLimit)
        }
        set { UserDefaults.standard.set(newValue.monthlyRequestLimit, forKey: Key.monthlyLimit) }
    }

    /// Point d'acces du fournisseur, saisi par l'utilisateur. Vide = non
    /// configure.
    static var endpoint: String {
        get { UserDefaults.standard.string(forKey: Key.endpoint) ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Key.endpoint) }
    }

    static var model: String {
        get { UserDefaults.standard.string(forKey: Key.model) ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Key.model) }
    }

    /// Le coach est utilisable quand le drapeau est actif ET qu'une
    /// configuration complete existe. Sans cela, l'interface annonce
    /// l'indisponibilite et renvoie vers le generateur local.
    static var isUsable: Bool {
        isEnabled && !endpoint.isEmpty && !model.isEmpty && AIKeychain.hasKey
    }

    /// Raison precise de l'indisponibilite, affichable telle quelle.
    static var unavailabilityReason: String? {
        if !isEnabled {
            return "Le coach IA est désactivé. Le générateur local reste disponible et fonctionne hors ligne."
        }
        if endpoint.isEmpty || model.isEmpty {
            return "Aucun fournisseur configuré : renseignez l’adresse du service et le modèle."
        }
        if !AIKeychain.hasKey {
            return "Aucune clé personnelle enregistrée. Elle est conservée dans le Trousseau de l’appareil, jamais dans l’application."
        }
        return nil
    }

    /// Efface tout ce qui concerne l'IA : reglages, consentement, usage et
    /// cle. Utilise par « Mes données ».
    static func reset() {
        let defaults = UserDefaults.standard
        for key in [Key.enabled, Key.consent, Key.usage, Key.monthlyLimit, Key.endpoint, Key.model] {
            defaults.removeObject(forKey: key)
        }
        AIKeychain.remove()
    }
}
