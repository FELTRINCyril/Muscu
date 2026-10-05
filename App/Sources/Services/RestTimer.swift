import Foundation
import SwiftUI
import UserNotifications
import AudioToolbox
import MuscuEngine

// Chrono de repos fiable, base sur une date de fin absolue (jamais un compteur
// decrementant) : le temps restant survit a une suspension de l'app.
//
// A la fin prevue, le repos est TERMINE : plus de fin ni de duree, l'ecran
// de repos se ferme et l'ecran de saisie de la serie suivante est la. Il n'y
// a pas de « depassement » affiche : le repos reellement pris est enregistre
// avec la serie suivante (`ActualRest`), independamment de ce chrono.
@Observable
@MainActor
final class RestTimer {
    nonisolated static let notificationIdentifier = "com.cyril.muscu.rest-timer"
    private static var didRequestAuthorization = false

    private(set) var endDate: Date?
    private(set) var totalSeconds: Int = 0

    /// Fin du repos, quelle qu'en soit la cause (fin prevue, « Passer »,
    /// « −15 s » jusqu'a zero).
    var onFinished: (() -> Void)?
    /// Toute modification de la fin : nouveau repos, ajustement, fin. Appele
    /// aussi application en arriere-plan (seance Sante active) : c'est ce
    /// qui met a jour la Live Activity a la fin du repos.
    var onStateChange: ((Date?, Int) -> Void)?

    private var expiryTask: Task<Void, Never>?
    /// Bips des trois dernieres secondes (premier plan uniquement : la
    /// notification de fin prend le relais en arriere-plan).
    private var beepTask: Task<Void, Never>?

    var isRunning: Bool {
        endDate != nil
    }

    var remaining: Int {
        guard let endDate else { return 0 }
        return RestCountdown(endDate: endDate, now: .now).remainingSeconds
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

    /// « −15 s » / « +15 s » (`RestAdjustment`) : le temps restant ne passe
    /// jamais sous zero ; s'il l'atteint, le repos se termine comme avec
    /// « Passer ». Toute autre valeur est ignoree.
    func adjust(by seconds: Int, now: Date = .now) {
        guard let currentEnd = endDate, RestAdjustment.isAllowed(seconds) else { return }
        switch RestAdjustment.adjust(endDate: currentEnd, totalSeconds: totalSeconds, by: seconds, now: now) {
        case .finished:
            skip()
        case .running(let newEnd, let newTotal):
            endDate = newEnd
            totalSeconds = newTotal
            onStateChange?(endDate, totalSeconds)
            let remainingSeconds = max(1, Int(newEnd.timeIntervalSince(now).rounded(.up)))
            scheduleNotification(seconds: remainingSeconds)
            scheduleExpiryDetection()
        }
    }

    func skip() {
        let wasRunning = endDate != nil
        clear()
        onStateChange?(nil, 0)
        if wasRunning { onFinished?() }
    }

    /// Arrete le repos en cours, s'il y en a un : la serie suivante est
    /// validee (dans l'application, depuis la Live Activity ou la montre).
    /// Sans repos en cours, rien n'est ecrit.
    func stopIfRunning() {
        guard endDate != nil else { return }
        skip()
    }

    private func clear() {
        cancelNotification()
        expiryTask?.cancel()
        expiryTask = nil
        beepTask?.cancel()
        beepTask = nil
        endDate = nil
        totalSeconds = 0
    }

    func restore(endDate: Date, totalSeconds: Int) {
        // Repos termine pendant que l'app etait fermee : il n'y a plus rien
        // a afficher, la serie suivante attend.
        guard totalSeconds > 0, endDate > .now else {
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
    /// de fin (±15 s, reprise) : un bip deja passe n'est jamais rejoue.
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
        guard endDate != nil else { return }
        FeedbackSettings.playSound(1007)
        FeedbackSettings.notification(.success)
        // Fin prevue atteinte : l'ecran de repos disparait SANS animation,
        // l'ecran de saisie de la serie suivante (deja en place dessous) est
        // aussitot visible. La notification de fin, deja delivree ou sur le
        // point de l'etre, est retiree par `clear`.
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            clear()
        }
        onStateChange?(nil, 0)
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
