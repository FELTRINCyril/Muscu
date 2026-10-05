import Foundation

/// Peut-on terminer la seance en cours depuis Siri ou un raccourci ?
///
/// La fin passe par le meme chemin que le bouton « Terminer » de
/// l'application ; cette regle decide seulement s'il y a quelque chose a
/// terminer, et ce que la confirmation doit dire.
public enum SessionEndCheck: Equatable, Sendable {
    /// Aucune seance en cours : rien a terminer, rien a abandonner.
    case noSession
    /// Seance en cours sans aucune serie de travail : la « terminer »
    /// ecrirait une seance vide dans l'historique. On propose d'abandonner.
    case nothingLogged
    /// Terminable. `remainingSlots` series prevues ne seront pas faites
    /// (zero quand le deroule est epuise ou pour une seance libre).
    case canFinish(workingSets: Int, remainingSlots: Int)

    public static func evaluate(
        hasActiveSession: Bool,
        workingSetsLogged: Int,
        progress: (completed: Int, total: Int),
        isFreeSession: Bool
    ) -> SessionEndCheck {
        guard hasActiveSession else { return .noSession }
        guard workingSetsLogged > 0 else { return .nothingLogged }
        let remaining = isFreeSession ? 0 : max(0, progress.total - progress.completed)
        return .canFinish(workingSets: workingSetsLogged, remainingSlots: remaining)
    }
}
