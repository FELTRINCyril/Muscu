import UIKit

/// Ecran maintenu allume pendant une seance en cours.
///
/// Le verrouillage automatique est retabli des que la seance n'est plus a
/// l'ecran (fin, abandon, reprise plus tard) ou que l'application passe en
/// arriere-plan : le laisser desactive viderait la batterie bien apres la
/// seance. Sur Mac Catalyst, rien n'est touche — empecher la mise en veille
/// d'un Mac pour une fenetre ouverte serait abusif.
@MainActor
enum ScreenAwake {
    /// Etat demande par le deroule. Le reglage utilisateur est relu a chaque
    /// appel : le desactiver prend effet a la prochaine transition.
    static func update(workoutIsOnScreen: Bool) {
        #if !targetEnvironment(macCatalyst)
        let shouldStayAwake = workoutIsOnScreen && WorkoutSettings.keepsScreenAwake
        if UIApplication.shared.isIdleTimerDisabled != shouldStayAwake {
            UIApplication.shared.isIdleTimerDisabled = shouldStayAwake
        }
        #endif
    }
}
