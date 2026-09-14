import Foundation
import ActivityKit
import MuscuEngine

/// Pilote la Live Activity d'une séance en cours.
///
/// Trois règles : elle ne démarre qu'avec l'autorisation du système, elle
/// n'est jamais laissée derrière soi à la fin d'une séance, et son contenu
/// se limite à ce que l'application affiche déjà.
///
/// L'acteur principal ne retient que l'IDENTIFIANT de l'activité, jamais
/// l'objet : `Activity` est manipulé par ActivityKit hors de cet acteur, et
/// le faire traverser la frontière serait une course de données.
@MainActor
enum WorkoutActivityController {
    /// Durée au-delà de laquelle une activité oubliée s'éteint d'elle-même.
    /// Une Live Activity qui resterait affichée toute la nuit après une
    /// séance abandonnée serait un défaut visible sur l'écran verrouillé.
    static let staleAfterHours = 4

    private static var currentIdentifier: String?

    static var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    static var isRunning: Bool { currentIdentifier != nil }

    @discardableResult
    static func start(sessionName: String, state: WorkoutActivityState, now: Date = .now) -> Bool {
        guard isSupported else { return false }
        // Une seule activité à la fois : en démarrer une seconde laisserait
        // la première sur l'écran verrouillé sans moyen de la fermer.
        guard currentIdentifier == nil else {
            Task { await update(state) }
            return true
        }

        let attributes = WorkoutActivityAttributes(sessionName: sessionName, startedAt: now)
        let content = ActivityContent(state: state, staleDate: staleDate(from: now))

        do {
            let activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
            currentIdentifier = activity.id
            return true
        } catch {
            // Refus, quota atteint, activités désactivées : la séance
            // continue exactement comme avant.
            currentIdentifier = nil
            return false
        }
    }

    static func update(_ state: WorkoutActivityState, now: Date = .now) async {
        guard let identifier = currentIdentifier else { return }
        await Self.updateActivity(identifier: identifier, state: state, staleDate: staleDate(from: now))
    }

    /// Termine l'activité. Appelée à la fin ET à l'abandon d'une séance :
    /// les deux sorties doivent la faire disparaître.
    static func end(finalState: WorkoutActivityState? = nil) async {
        guard let identifier = currentIdentifier else { return }
        currentIdentifier = nil
        await Self.endActivity(identifier: identifier, state: finalState)
    }

    /// Ferme toute activité restée ouverte, par exemple après un arrêt brutal
    /// de l'application pendant une séance.
    static func endOrphans() async {
        currentIdentifier = nil
        await Self.endAllActivities()
    }

    private static func staleDate(from now: Date) -> Date? {
        Calendar.current.date(byAdding: .hour, value: staleAfterHours, to: now)
    }

    // MARK: - Accès hors de l'acteur principal

    private nonisolated static func updateActivity(
        identifier: String,
        state: WorkoutActivityState,
        staleDate: Date?
    ) async {
        guard let activity = Activity<WorkoutActivityAttributes>.activities.first(where: { $0.id == identifier }) else {
            return
        }
        await activity.update(ActivityContent(state: state, staleDate: staleDate))
    }

    private nonisolated static func endActivity(identifier: String, state: WorkoutActivityState?) async {
        guard let activity = Activity<WorkoutActivityAttributes>.activities.first(where: { $0.id == identifier }) else {
            return
        }
        await activity.end(state.map { ActivityContent(state: $0, staleDate: nil) }, dismissalPolicy: .immediate)
    }

    private nonisolated static func endAllActivities() async {
        for activity in Activity<WorkoutActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
