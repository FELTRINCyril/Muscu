import Foundation
import SwiftData
import MuscuEngine

/// Pont entre une seance de l'historique et le deroule « Refaire » du
/// moteur (`SessionReplay`), plus la repartition du temps d'une seance.
@MainActor
enum SessionReplayBuilder {
    /// Deroule de seance libre reconstruit depuis une seance passee. Le
    /// repos de chaque exercice est le repos par defaut de son materiel ; le
    /// type de charge, celui du catalogue quand il est connu (une serie
    /// lestee ce jour-la ne fait pas d'un exercice au poids du corps un
    /// exercice leste).
    static func plan(
        for session: CompletedSession,
        mode: SessionReplay.Mode,
        catalogStore: CatalogStore,
        context: ModelContext
    ) -> WorkoutPlan {
        let customExercises = (try? context.fetch(FetchDescriptor<CustomExercise>())) ?? []
        let sources = session.sets.map { set in
            ReplaySourceSet(
                exerciseId: set.exerciseId,
                displayName: set.displayName,
                orderIndex: set.orderIndex,
                subSetIndex: set.subSetIndex,
                isPrescribedWorkingSet: set.role == .working,
                weightKilograms: set.weight,
                reps: set.reps,
                durationSeconds: set.durationSeconds,
                distanceMeters: set.distanceMeters,
                loadKind: set.loadType.loadKind,
                side: set.sideConvention
            )
        }
        var plan = SessionReplay.plan(from: sources, mode: mode) { exerciseId in
            let equipment = WorkoutPlanBuilder.equipment(
                forExerciseId: exerciseId,
                catalogStore: catalogStore,
                customExercises: customExercises
            )
            return WorkoutSettings.restDefaults.seconds(forEquipment: equipment)
        }
        for nodeIndex in plan.nodes.indices {
            for memberIndex in plan.nodes[nodeIndex].exercises.indices {
                let exerciseId = plan.nodes[nodeIndex].exercises[memberIndex].exerciseId
                if let catalogExercise = catalogStore.exercise(id: exerciseId) {
                    plan.nodes[nodeIndex].exercises[memberIndex].loadKind = ExerciseClassification.loadKind(for: catalogExercise)
                } else if let custom = customExercises.first(where: { $0.id.uuidString == exerciseId }) {
                    plan.nodes[nodeIndex].exercises[memberIndex].loadKind = custom.defaultLoadKind
                }
            }
        }
        return plan
    }

    /// Temps actif / temps de repos d'une seance terminee, `nil` quand le
    /// repos n'a pas ete mesure pour chaque serie.
    static func timeBreakdown(for session: CompletedSession) -> SessionTimeBreakdown? {
        timeBreakdown(totalSeconds: session.durationSeconds, sets: session.sets)
    }

    static func timeBreakdown(totalSeconds: Int, sets: [CompletedSet]) -> SessionTimeBreakdown? {
        SessionTimeBreakdown.make(
            totalSeconds: totalSeconds,
            sets: sets.map { .init(sequenceIndex: $0.sequenceIndex, restSeconds: $0.actualRestSeconds) }
        )
    }
}
