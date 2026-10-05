import Foundation
import SwiftData
import UserNotifications

/// Traite les actions choisies depuis un rappel.
///
/// Les trois actions sont SURES : demarrer ouvre l'application, reporter
/// deplace la seance d'un jour, ignorer change son etat. Aucune n'ecrit de
/// performance et aucune ne supprime quoi que ce soit.
final class NotificationResponder: NSObject, UNUserNotificationCenterDelegate {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
        super.init()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Fin de repos, application ouverte : le chrono a deja joue son son
        // et l'ecran de saisie est revenu. Une banniere par-dessus ne dirait
        // rien de plus.
        if notification.request.identifier == RestTimer.notificationIdentifier { return [] }
        return [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        // On extrait des valeurs simples AVANT de passer sur l'acteur
        // principal : `UNNotificationResponse` n'est pas transferable entre
        // acteurs, contrairement a une chaine et a un UUID.
        let action = response.actionIdentifier
        let workoutId = (response.notification.request.content.userInfo[WorkoutNotificationActions.workoutIdKey] as? String)
            .flatMap(UUID.init(uuidString:))
        let container = self.container

        await MainActor.run {
            Self.handle(action: action, workoutId: workoutId, container: container)
        }
    }

    /// Interne plutot que prive : les trois actions sont testees directement,
    /// sans passer par une vraie notification systeme.
    @MainActor
    static func handle(action: String, workoutId: UUID?, container: ModelContainer) {
        switch action {
        case WorkoutNotificationActions.start, UNNotificationDefaultActionIdentifier:
            IntentRouter.shared.request(.home)
        case WorkoutNotificationActions.postpone:
            applyAction(workoutId: workoutId, container: container) { workout, context in
                let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: workout.plannedDate) ?? workout.plannedDate
                PlanningService.move(workout, to: tomorrow, in: context)
            }
        case WorkoutNotificationActions.skip:
            applyAction(workoutId: workoutId, container: container) { workout, context in
                PlanningService.update(workout, to: .skipped, in: context)
            }
        case UNNotificationDismissActionIdentifier:
            // Ecarter la banniere n'est pas une suppression : on ne
            // desactive rien, sinon un geste anodin couperait les rappels
            // sans le dire.
            break
        default:
            break
        }
    }

    @MainActor
    private static func applyAction(
        workoutId: UUID?,
        container: ModelContainer,
        action: (ScheduledWorkout, ModelContext) -> Void
    ) {
        guard let workoutId else { return }
        let context = container.mainContext
        guard let workout = PlanningService.scheduledWorkouts(in: context).first(where: { $0.id == workoutId }) else { return }
        action(workout, context)
    }
}
