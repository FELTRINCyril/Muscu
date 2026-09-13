import Foundation
import SwiftData
import MuscuEngine

/// Convertit les donnees SwiftData vers les types purs des analyses.
///
/// Point de passage UNIQUE : toute vue qui affiche un indicateur part de ces
/// conversions, pour que deux ecrans ne puissent pas diverger.
@MainActor
enum AnalyticsBridge {
    /// Nombre de seances chargees par defaut pour les tableaux de bord.
    /// Borne volontairement : un historique de plusieurs annees n'a pas a
    /// etre charge en entier pour afficher les douze dernieres semaines.
    static let defaultSessionLimit = 500

    /// Seances converties, de la plus ancienne a la plus recente.
    static func sessions(
        context: ModelContext,
        catalogStore: CatalogStore?,
        limit: Int = defaultSessionLimit,
        since: Date? = nil
    ) -> [AnalyticsSession] {
        var descriptor = FetchDescriptor<CompletedSession>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = max(1, limit)
        if let since {
            descriptor.predicate = #Predicate { $0.date >= since }
        }
        let stored = (try? context.fetch(descriptor)) ?? []
        let fallbackBodyweight = ProfileStore.latestBodyweightKilograms(in: context)
        let musclesById = muscleIndex(for: stored, catalogStore: catalogStore, context: context)

        return stored
            .sorted { $0.date < $1.date }
            .map { session in
                analyticsSession(session, musclesById: musclesById, fallbackBodyweight: fallbackBodyweight)
            }
    }

    static func analyticsSession(
        _ session: CompletedSession,
        musclesById: [String: [String]],
        fallbackBodyweight: Double?
    ) -> AnalyticsSession {
        AnalyticsSession(
            id: session.id,
            date: session.date,
            durationSeconds: session.durationSeconds,
            programSessionId: session.programSessionId,
            sets: session.sets.map { set in
                AnalyticsSet(
                    exerciseId: set.exerciseId,
                    displayName: set.displayName,
                    metrics: set.metricsInput(bodyweightKilograms: session.bodyweightKilograms ?? fallbackBodyweight),
                    primaryMuscles: musclesById[set.exerciseId] ?? [],
                    effort: set.effort,
                    reachedFailure: set.reachedFailure
                )
            }
        )
    }

    /// Muscles principaux par identifiant d'exercice : catalogue d'abord,
    /// exercices personnalises ensuite. Un exercice inconnu n'a pas de
    /// muscle : il compte dans les totaux, dans aucune repartition.
    static func muscleIndex(
        for sessions: [CompletedSession],
        catalogStore: CatalogStore?,
        context: ModelContext
    ) -> [String: [String]] {
        let identifiers = Set(sessions.flatMap { $0.sets.map(\.exerciseId) })
        guard !identifiers.isEmpty else { return [:] }

        var result: [String: [String]] = [:]
        for identifier in identifiers {
            if let exercise = catalogStore?.exercise(id: identifier) {
                result[identifier] = exercise.primaryMuscles
            }
        }

        let missing = identifiers.subtracting(result.keys)
        guard !missing.isEmpty else { return result }
        let customExercises = (try? context.fetch(FetchDescriptor<CustomExercise>())) ?? []
        for custom in customExercises where missing.contains(custom.id.uuidString) {
            result[custom.id.uuidString] = custom.primaryMuscles
        }
        return result
    }

    /// Seances planifiees et realisees sur une periode, pour l'adherence.
    static func adherence(context: ModelContext, from start: Date, to end: Date) -> AdherenceSummary {
        let descriptor = FetchDescriptor<ScheduledWorkout>(
            predicate: #Predicate { $0.plannedDate >= start && $0.plannedDate <= end && $0.deletedAt == nil }
        )
        let planned = (try? context.fetch(descriptor)) ?? []
        let completed = planned.filter { $0.stateRaw == ScheduledWorkoutState.completed.rawValue }
        return TrainingAnalytics.adherence(plannedCount: planned.count, completedCount: completed.count)
    }
}
