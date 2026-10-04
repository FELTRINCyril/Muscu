import Foundation
import UserNotifications
import AudioToolbox
import MuscuEngine

// Chrono de repos fiable, base sur une date de fin absolue (jamais un compteur
// decrementant) : le temps restant survit a une suspension de l'app.
//
// Une fois la fin atteinte, le chrono ne s'arrete pas : il passe en
// DEPASSEMENT (« +0:12 ») jusqu'a la serie suivante. `isRunning` redevient
// faux — l'ecran de repos se ferme comme avant — mais `isOvertime` reste vrai
// tant que `skip()` ou un nouveau `start` n'a pas eu lieu.
@Observable
@MainActor
final class RestTimer {
    private static let notificationIdentifier = "com.cyril.muscu.rest-timer"
    private static var didRequestAuthorization = false

    private(set) var endDate: Date?
    private(set) var totalSeconds: Int = 0
    /// Repos termine, depassement en cours d'affichage.
    private(set) var isOvertime = false

    var onFinished: (() -> Void)?
    var onStateChange: ((Date?, Int) -> Void)?

    private var expiryTask: Task<Void, Never>?
    /// Bips des trois dernieres secondes (premier plan uniquement : la
    /// notification de fin prend le relais en arriere-plan).
    private var beepTask: Task<Void, Never>?

    var isRunning: Bool {
        endDate != nil && !isOvertime
    }

    var remaining: Int {
        guard let endDate else { return 0 }
        return RestCountdown(endDate: endDate, now: .now).remainingSeconds
    }

    /// Etat affiche a l'instant `now` : decompte, puis depassement.
    func countdown(at now: Date = .now) -> RestCountdown? {
        guard let endDate else { return nil }
        return RestCountdown(endDate: endDate, now: now)
    }

    var progress: Double {
        guard let endDate, totalSeconds > 0 else { return 0 }
        let elapsed = Double(totalSeconds) - endDate.timeIntervalSinceNow
        return min(1, max(0, elapsed / Double(totalSeconds)))
    }

    func start(seconds: Int) {
        requestAuthorizationIfNeeded()

        isOvertime = false
        totalSeconds = seconds
        endDate = Date.now.addingTimeInterval(Double(seconds))
        onStateChange?(endDate, totalSeconds)
        scheduleNotification(seconds: seconds)
        scheduleExpiryDetection()
    }

    func addThirtySeconds() {
        guard let currentEnd = endDate, !isOvertime else { return }
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
        beepTask?.cancel()
        beepTask = nil
        endDate = nil
        totalSeconds = 0
        isOvertime = false
        onStateChange?(nil, 0)
    }

    /// Ferme un depassement en cours (serie suivante saisie, seance
    /// terminee). Sans effet pendant un repos qui n'est pas termine.
    func endOvertime() {
        guard isOvertime else { return }
        skip()
    }

    func restore(endDate: Date, totalSeconds: Int) {
        guard totalSeconds > 0 else {
            skip()
            return
        }
        guard endDate > .now else {
            // Repos termine pendant que l'app etait fermee : on reprend le
            // depassement s'il reste plausible, sinon on l'oublie.
            let overtime = RestCountdown(endDate: endDate, now: .now).overtimeSeconds
            guard overtime <= RestCountdown.maximumOvertimeSeconds else {
                skip()
                return
            }
            self.endDate = endDate
            self.totalSeconds = totalSeconds
            isOvertime = true
            return
        }
        isOvertime = false
        self.endDate = endDate
        self.totalSeconds = totalSeconds
        let remainingSeconds = max(1, Int(endDate.timeIntervalSinceNow.rounded(.up)))
        scheduleNotification(seconds: remainingSeconds)
        scheduleExpiryDetection()
    }

    private func scheduleExpiryDetection() {
        expiryTask?.cancel()
        scheduleBeeps()
        guard let endDate else { return }
        let delay = max(0, endDate.timeIntervalSinceNow)
        expiryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.handleExpiry()
        }
    }

    /// Trois bips courts aux trois dernieres secondes, avec une vibration
    /// legere, quand les sons sont actives. Recalcules a chaque changement
    /// de fin (+30 s, reprise) : un bip deja passe n'est jamais rejoue.
    private func scheduleBeeps() {
        beepTask?.cancel()
        beepTask = nil
        guard let endDate, FeedbackSettings.isSoundEnabled else { return }
        let times = RestBeeps.times(endDate: endDate, now: .now)
        guard !times.isEmpty else { return }
        beepTask = Task { [weak self] in
            for time in times {
                let delay = time.timeIntervalSinceNow
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
                guard !Task.isCancelled, let self, self.isRunning else { return }
                FeedbackSettings.playSound(Self.beepSoundID)
                FeedbackSettings.impact(.light)
            }
        }
    }

    /// Son systeme court (« Tink »), distinct du son de fin.
    private static let beepSoundID: SystemSoundID = 1103

    private func handleExpiry() {
        guard endDate != nil, !isOvertime else { return }
        cancelNotification()
        // La date de fin est conservee : c'est elle qui mesure le
        // depassement. L'etat persiste ne change donc pas.
        isOvertime = true

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
