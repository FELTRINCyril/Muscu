import Foundation
import AudioToolbox
import UIKit

// Lecture centralisee des reglages "Sons" / "Vibrations" (UserDefaults),
// partagee par tous les deroules (repos classique, intervalles, AMRAP).
// Absent de UserDefaults == active par defaut (cf. RestTimer, source du
// pattern object(forKey:) == nil || bool(forKey:)).
enum FeedbackSettings {
    static var isSoundEnabled: Bool {
        UserDefaults.standard.object(forKey: "soundEnabled") == nil
            || UserDefaults.standard.bool(forKey: "soundEnabled")
    }

    static var isHapticsEnabled: Bool {
        UserDefaults.standard.object(forKey: "hapticsEnabled") == nil
            || UserDefaults.standard.bool(forKey: "hapticsEnabled")
    }

    static func playSound(_ soundID: SystemSoundID) {
        guard isSoundEnabled else { return }
        AudioServicesPlaySystemSound(soundID)
    }

    @MainActor
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard isHapticsEnabled else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    @MainActor
    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard isHapticsEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}
