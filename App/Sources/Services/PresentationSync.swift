import UIKit

// Declencher une NOUVELLE presentation SwiftUI (fullScreenCover/sheet) dans le
// meme cycle de run loop que la fermeture d'une AUTRE presentation (alert,
// confirmationDialog) sur la meme fenetre peut etre silencieusement ignoree
// par UIKit : la presentation precedente est encore en cours de transition
// (son animation de fermeture n'est pas terminee), et l'OS refuse/perd la
// nouvelle demande. Un simple delai fixe (DispatchQueue.main.asyncAfter) est
// insuffisant de facon intermittente (constate empiriquement, cf.
// .superpowers/sdd/progress.md) : la duree reelle de l'animation de
// fermeture varie. On interroge donc directement l'etat UIKit reel
// (`UIViewController.presentedViewController`, mis a jour uniquement une
// fois la transition de fermeture effectivement terminee) et on ne
// declenche `action` qu'une fois plus aucune presentation active.
@MainActor
enum PresentationSync {
    private static func hasActivePresentation() -> Bool {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
            let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController
        else {
            return false
        }
        return root.presentedViewController != nil
    }

    static func afterCurrentPresentationDismissed(
        pollInterval: TimeInterval = 0.03,
        _ action: @escaping () -> Void
    ) {
        guard hasActivePresentation() else {
            action()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + pollInterval) {
            afterCurrentPresentationDismissed(pollInterval: pollInterval, action)
        }
    }
}
