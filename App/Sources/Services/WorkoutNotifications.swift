import Foundation
import SwiftData
import UserNotifications
import MuscuEngine

/// Etat d'autorisation vu par l'application. Reduit a ce dont on a besoin :
/// le reste des subtilites d'iOS n'a pas d'effet sur nos decisions.
enum NotificationAuthorization: Sendable, Equatable {
    case notDetermined
    case authorized
    case denied
}

/// Ce qu'un planificateur de rappels doit savoir faire.
///
/// L'abstraction existe pour que TOUTE la logique de rappel soit testable
/// sans notification systeme : les tests utilisent `InMemoryNotificationScheduler`,
/// l'application `UserNotificationScheduler`.
protocol NotificationScheduling: AnyObject, Sendable {
    func authorizationStatus() async -> NotificationAuthorization
    /// Demande l'autorisation. N'est appelee QUE sur une action explicite de
    /// l'utilisateur : activer les rappels.
    func requestAuthorization() async -> NotificationAuthorization
    func pendingIdentifiers() async -> [String: Date]
    func schedule(_ notifications: [PlannedNotification]) async
    func cancel(identifiers: [String]) async
}

/// Categorie et actions des rappels de seance. Les actions sont SURES :
/// aucune n'ecrit de performance, aucune ne supprime de donnee.
enum WorkoutNotificationActions {
    static let categoryIdentifier = "muscu.workout.reminder"
    static let start = "muscu.action.start"
    static let postpone = "muscu.action.postpone"
    static let skip = "muscu.action.skip"
    static let workoutIdKey = "workoutId"

    static var category: UNNotificationCategory {
        UNNotificationCategory(
            identifier: categoryIdentifier,
            actions: [
                UNNotificationAction(identifier: start, title: String(localized: "Démarrer"), options: [.foreground]),
                UNNotificationAction(identifier: postpone, title: String(localized: "Reporter à demain"), options: []),
                UNNotificationAction(identifier: skip, title: String(localized: "Ignorer"), options: []),
            ],
            intentIdentifiers: [],
            options: []
        )
    }
}

/// Implementation reelle, adossee a `UNUserNotificationCenter`.
final class UserNotificationScheduler: NotificationScheduling, @unchecked Sendable {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        center.setNotificationCategories([WorkoutNotificationActions.category])
    }

    func authorizationStatus() async -> NotificationAuthorization {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .authorized
        case .denied: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    func requestAuthorization() async -> NotificationAuthorization {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            return granted ? .authorized : .denied
        } catch {
            return .denied
        }
    }

    func pendingIdentifiers() async -> [String: Date] {
        let requests = await center.pendingNotificationRequests()
        var result: [String: Date] = [:]
        for request in requests {
            guard request.identifier.hasPrefix("muscu.reminder."),
                  let trigger = request.trigger as? UNCalendarNotificationTrigger,
                  let date = trigger.nextTriggerDate() else { continue }
            result[request.identifier] = date
        }
        return result
    }

    func schedule(_ notifications: [PlannedNotification]) async {
        for notification in notifications {
            let content = UNMutableNotificationContent()
            content.title = notification.title
            content.body = notification.body
            content.sound = notification.isSoundEnabled ? .default : nil
            content.categoryIdentifier = WorkoutNotificationActions.categoryIdentifier
            if let workoutId = notification.workoutId {
                content.userInfo = [WorkoutNotificationActions.workoutIdKey: workoutId.uuidString]
            }

            // Declencheur CALENDAIRE et non par intervalle : un rappel doit
            // tomber a l'heure locale prevue, meme si l'appareil change de
            // fuseau entre la programmation et le declenchement.
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: notification.fireDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: notification.identifier,
                content: content,
                trigger: trigger
            )
            try? await center.add(request)
        }
    }

    func cancel(identifiers: [String]) async {
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

/// Planificateur en memoire, pour les tests : il enregistre exactement ce
/// qu'on lui demande, sans jamais toucher au systeme.
final class InMemoryNotificationScheduler: NotificationScheduling, @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [String: Date] = [:]
    private var status: NotificationAuthorization
    private(set) var authorizationRequestCount = 0
    private(set) var scheduledHistory: [String] = []
    private(set) var cancelledHistory: [String] = []
    /// Reponse donnee a la prochaine demande d'autorisation.
    var authorizationAnswer: NotificationAuthorization = .authorized

    init(status: NotificationAuthorization = .notDetermined) {
        self.status = status
    }

    func authorizationStatus() async -> NotificationAuthorization {
        lock.withLock { status }
    }

    func requestAuthorization() async -> NotificationAuthorization {
        lock.withLock {
            authorizationRequestCount += 1
            status = authorizationAnswer
            return status
        }
    }

    func pendingIdentifiers() async -> [String: Date] {
        lock.withLock { pending }
    }

    func schedule(_ notifications: [PlannedNotification]) async {
        lock.withLock {
            for notification in notifications {
                pending[notification.identifier] = notification.fireDate
                scheduledHistory.append(notification.identifier)
            }
        }
    }

    func cancel(identifiers: [String]) async {
        lock.withLock {
            for identifier in identifiers {
                pending.removeValue(forKey: identifier)
                cancelledHistory.append(identifier)
            }
        }
    }
}
