import Foundation
import UserNotifications
import AudioToolbox
import UIKit

// Chrono de repos fiable, base sur une date de fin absolue (jamais un compteur
// decrementant) : le temps restant survit a une suspension de l'app.
@Observable
@MainActor
final class RestTimer {
    private static let notificationIdentifier = "com.cyril.muscu.rest-timer"
    private static var didRequestAuthorization = false

    private(set) var endDate: Date?
    private(set) var totalSeconds: Int = 0

    var onFinished: (() -> Void)?

    private var expiryTask: Task<Void, Never>?

    var isRunning: Bool {
        endDate != nil
    }

    var remaining: Int {
        guard let endDate else { return 0 }
        return max(0, Int((endDate.timeIntervalSinceNow).rounded(.up)))
    }

    var progress: Double {
        guard let endDate, totalSeconds > 0 else { return 0 }
        let elapsed = Double(totalSeconds) - endDate.timeIntervalSinceNow
        return min(1, max(0, elapsed / Double(totalSeconds)))
    }

    func start(seconds: Int) {
        requestAuthorizationIfNeeded()

        totalSeconds = seconds
        endDate = Date.now.addingTimeInterval(Double(seconds))
        scheduleNotification(seconds: seconds)
        scheduleExpiryDetection()
    }

    func addThirtySeconds() {
        guard let currentEnd = endDate else { return }
        endDate = currentEnd.addingTimeInterval(30)
        totalSeconds += 30
        guard let endDate else { return }
        let remainingSeconds = max(1, Int(endDate.timeIntervalSinceNow.rounded(.up)))
        scheduleNotification(seconds: remainingSeconds)
        scheduleExpiryDetection()
    }

    func skip() {
        cancelNotification()
        expiryTask?.cancel()
        expiryTask = nil
        endDate = nil
        totalSeconds = 0
    }

    private func scheduleExpiryDetection() {
        expiryTask?.cancel()
        guard let endDate else { return }
        let delay = max(0, endDate.timeIntervalSinceNow)
        expiryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.handleExpiry()
        }
    }

    private func handleExpiry() {
        guard endDate != nil else { return }
        cancelNotification()
        endDate = nil
        totalSeconds = 0

        if UserDefaults.standard.object(forKey: "soundEnabled") == nil
            || UserDefaults.standard.bool(forKey: "soundEnabled") {
            AudioServicesPlaySystemSound(1007)
        }
        if UserDefaults.standard.object(forKey: "hapticsEnabled") == nil
            || UserDefaults.standard.bool(forKey: "hapticsEnabled") {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }

        onFinished?()
    }

    private func requestAuthorizationIfNeeded() {
        guard !Self.didRequestAuthorization else { return }
        Self.didRequestAuthorization = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func scheduleNotification(seconds: Int) {
        cancelNotification()

        let content = UNMutableNotificationContent()
        content.title = "Repos terminé"
        content.body = "À toi de jouer !"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, Double(seconds)),
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: Self.notificationIdentifier,
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func cancelNotification() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.notificationIdentifier])
    }
}
