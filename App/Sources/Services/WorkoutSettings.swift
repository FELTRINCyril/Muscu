import Foundation
import MuscuEngine

/// Reglages de seance lus hors des vues (deroule, analyses, records).
///
/// Meme convention que `FeedbackSettings` : une cle ABSENTE vaut la valeur
/// par defaut, pour qu'une installation existante garde exactement son
/// comportement tant que l'utilisateur ne touche a rien.
enum WorkoutSettings {
    // MARK: - Ecran allume

    static let keepsScreenAwakeKey = "keepScreenAwakeDuringWorkout"

    /// Ecran maintenu allume pendant une seance en cours. Active par defaut :
    /// un ecran qui se verrouille entre deux series oblige a deverrouiller
    /// le telephone a chaque saisie.
    static var keepsScreenAwake: Bool {
        UserDefaults.standard.object(forKey: keepsScreenAwakeKey) == nil
            || UserDefaults.standard.bool(forKey: keepsScreenAwakeKey)
    }

    // MARK: - Repos par defaut

    /// Cle historique : repos par defaut unique, devenu celui des halteres,
    /// machines et poulies. La conserver evite de perdre le reglage deja
    /// choisi par l'utilisateur.
    static let otherRestKey = "defaultRestSeconds"
    static let barbellRestKey = "defaultRestSecondsBarbell"

    /// Repos par defaut. Le repos « barre » reprend, tant qu'il n'est pas
    /// regle, la valeur historique unique : rien ne change sans action.
    static var restDefaults: RestDefaults {
        let defaults = UserDefaults.standard
        let other = defaults.object(forKey: otherRestKey) != nil
            ? defaults.integer(forKey: otherRestKey)
            : RestDefaults.legacySeconds
        let barbell = defaults.object(forKey: barbellRestKey) != nil
            ? defaults.integer(forKey: barbellRestKey)
            : other
        return RestDefaults(barbellSeconds: barbell, otherSeconds: other)
    }

    // MARK: - 1RM estime

    static let oneRepMaxMaximumRepsKey = "oneRepMaxMaximumReps"

    /// Plafond de repetitions au-dela duquel une serie n'estime plus de 1RM.
    static var maximumRepsForOneRepMax: Int {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: oneRepMaxMaximumRepsKey) != nil else {
            return OneRepMaxEstimation.defaultMaximumReps
        }
        return OneRepMaxEstimation.clamped(defaults.integer(forKey: oneRepMaxMaximumRepsKey))
    }
}
