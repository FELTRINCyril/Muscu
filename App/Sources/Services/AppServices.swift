import Foundation

/// Services systeme utilises par l'interface : notifications et calendrier.
///
/// Ils sont remplacables pour que les tests UI ne declenchent JAMAIS de
/// veritable demande d'autorisation : une alerte systeme bloquerait la suite
/// et rendrait les tests dependants de l'etat du simulateur. En production,
/// ce sont les implementations reelles.
@MainActor
enum AppServices {
    static private(set) var notificationScheduler: NotificationScheduling = UserNotificationScheduler()
    static private(set) var calendarStore: CalendarStoring = EventKitCalendarStore()
    static private(set) var healthStore: HealthStoring = HealthKitStore()

    /// Bascule vers des doubles en memoire. Appelee uniquement depuis le
    /// harnais de tests UI, lui-meme compile en DEBUG seulement.
    static func useInMemoryServices() {
        notificationScheduler = InMemoryNotificationScheduler(status: .authorized)
        calendarStore = InMemoryCalendarStore(status: .authorized)
        // Sante reste NON DETERMINEE dans les tests UI : le parcours a
        // verifier est justement celui ou rien n'est encore autorise.
        healthStore = InMemoryHealthStore(status: .notDetermined)
    }
}
