import Foundation
import SwiftData
import MuscuEngine

/// Retrouve la mise à l'échelle qui s'applique à une séance donnée.
///
/// Une semaine de plan porte un multiplicateur de volume et d'intensité —
/// une décharge vaut 50 % de volume et 90 % d'intensité. Ils étaient
/// calculés, stockés et affichés, mais jamais appliqués : une semaine de
/// décharge planifiée n'allégeait rien. Ce service fait le lien manquant
/// entre la semaine de plan et le déroulé réellement exécuté.
@MainActor
enum WeekScalingResolver {
    /// Mise à l'échelle applicable à `session` à la date `date`.
    ///
    /// Renvoie `.neutral` dès qu'il y a le moindre doute : hors plan, séance
    /// non planifiée, semaine introuvable. Alléger une séance par erreur
    /// serait pire que ne pas l'alléger du tout.
    static func scaling(
        for session: ProgramSession,
        on date: Date = .now,
        context: ModelContext
    ) -> WeekScaling {
        guard let week = week(for: session, on: date, context: context) else { return .neutral }
        guard week.volumeMultiplier != 1 || week.intensityMultiplier != 1 else { return .neutral }

        return WeekScaling(
            volumeMultiplier: week.volumeMultiplier,
            intensityMultiplier: week.intensityMultiplier,
            loadIncrementKilograms: loadIncrement(context: context)
        )
    }

    /// Semaine de plan de la séance planifiée correspondante. On retient la
    /// séance planifiée NON terminée la plus proche de `date` : c'est celle
    /// que l'utilisateur est en train de lancer.
    private static func week(
        for session: ProgramSession,
        on date: Date,
        context: ModelContext
    ) -> TrainingWeek? {
        let sessionId = session.id
        let descriptor = FetchDescriptor<ScheduledWorkout>(
            predicate: #Predicate { $0.programSessionId == sessionId && $0.deletedAt == nil }
        )
        guard let workouts = try? context.fetch(descriptor) else { return nil }

        let candidates = workouts.filter { $0.state == .planned || $0.state == .postponed }
        let closest = candidates.min {
            abs($0.plannedDate.timeIntervalSince(date)) < abs($1.plannedDate.timeIntervalSince(date))
        }
        return closest?.week
    }

    /// Plus PETIT palier réellement disponible pour cet athlète : c'est lui
    /// qui permet d'alléger finement. Sans profil, on n'arrondit pas.
    private static func loadIncrement(context: ModelContext) -> Double {
        guard let profile = try? context.fetch(FetchDescriptor<AthleteProfile>()).first else { return 0 }
        return profile.availableIncrementsKilograms.filter { $0 > 0 }.min() ?? 0
    }
}
