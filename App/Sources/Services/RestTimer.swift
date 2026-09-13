import Foundation
import UserNotifications

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
    var onStateChange: ((Date?, Int) -> Void)?

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
        onStateChange?(endDate, totalSeconds)
        scheduleNotification(seconds: seconds)
        scheduleExpiryDetection()
    }

    func addThirtySeconds() {
        guard let currentEnd = endDate else { return }
        endDate = currentEnd.addingTimeInterval(30)
        totalSeconds += 30
        onStateChange?(endDate, totalSeconds)
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
        onStateChange?(nil, 0)
    }

    func restore(endDate: Date, totalSeconds: Int) {
        guard endDate > .now, totalSeconds > 0 else {
            skip()
            return
        }
        self.endDate = endDate
        self.totalSeconds = totalSeconds
        let remainingSeconds = max(1, Int(endDate.timeIntervalSinceNow.rounded(.up)))
        scheduleNotification(seconds: remainingSeconds)
        scheduleExpiryDetection()
    }

    private func scheduleExpiryDetection() {
        expiryTask?.cancel()
        guard let endDate else { return }
        let delay = max(0, endDate.timeIntervalSinceNow)
        expiryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.handleExpiry()
        }
    }

    private func handleExpiry() {
        guard endDate != nil else { return }
        cancelNotification()
        endDate = nil
        totalSeconds = 0
        onStateChange?(nil, 0)

        FeedbackSettings.playSound(1007)
        FeedbackSettings.notification(.success)

        onFinished?()
    }

    private func requestAuthorizationIfNeeded() {
        guard !Self.didRequestAuthorization else { return }
        Self.didRequestAuthorization = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                Task { @MainActor in
                    PersistenceSupport.report(error, action: "Autorisation des notifications de repos")
                }
            } else if !granted {
                Task { @MainActor in
                    NotificationCenter.default.post(name: .restNotificationsDenied, object: nil)
                }
            }
        }
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
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                Task { @MainActor in
                    PersistenceSupport.report(error, action: "Planification de la notification de repos")
                }
            }
        }
    }

    private func cancelNotification() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.notificationIdentifier])
    }
}

extension Notification.Name {
    static let restNotificationsDenied = Notification.Name("Muscu.restNotificationsDenied")
}
