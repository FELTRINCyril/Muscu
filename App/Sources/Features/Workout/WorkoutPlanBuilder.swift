import Foundation
import SwiftData
import MuscuEngine

/// Traduit une seance de programme (SwiftData) vers le deroule pur que la
/// machine a etats du moteur sait executer.
///
/// La conversion est une COPIE autonome : modifier le programme pendant une
/// seance en cours ne doit jamais reecrire ce qui est en train d'etre execute
/// (cf. le snapshot persiste sur `ActiveWorkout`).
@MainActor
enum WorkoutPlanBuilder {
    /// Construit le plan d'une seance : les exercices rattaches a un groupe
    /// forment un noeud de groupe, les autres des noeuds simples. L'ordre des
    /// noeuds suit l'ordre d'affichage de la seance.
    ///
    /// Un exercice seul sans repos prescrit recoit le repos par defaut de son
    /// materiel (barre ou autres, cf. Reglages). Les membres d'un groupe n'en
    /// recoivent pas : leur recuperation est portee par le groupe lui-meme.
    static func plan(
        for session: ProgramSession,
        catalogStore: CatalogStore? = nil,
        customExercises: [CustomExercise] = [],
        restDefaults: RestDefaults = WorkoutSettings.restDefaults
    ) -> WorkoutPlan {
        let exercises = session.orderedExercises
        var nodes: [WorkoutNode] = []
        var handledGroupIds: Set<UUID> = []

        for exercise in exercises {
            guard let group = exercise.group else {
                let single = plan(for: exercise, catalogStore: catalogStore, customExercises: customExercises)
                let equipment = Self.equipment(
                    forExerciseId: exercise.exerciseId,
                    catalogStore: catalogStore,
                    customExercises: customExercises
                )
                nodes.append(.single(restDefaults.filling(single, equipment: equipment)))
                continue
            }
            // Un groupe n'apparait qu'une fois, a la position de son premier
            // exercice dans la seance.
            guard !handledGroupIds.contains(group.id) else { continue }
            handledGroupIds.insert(group.id)

            let members = group.orderedExercises
            guard !members.isEmpty else { continue }
            nodes.append(
                WorkoutNode(
                    id: group.id,
                    kind: WorkoutGroupKind(rawValue: group.kindRaw) ?? .superset,
                    exercises: members.map { plan(for: $0, catalogStore: catalogStore, customExercises: customExercises) },
                    rounds: group.rounds,
                    restBetweenExercisesSeconds: group.restBetweenExercisesSeconds,
                    restBetweenRoundsSeconds: group.restBetweenRoundsSeconds,
                    transitionSeconds: group.transitionSeconds
                )
            )
        }
        return WorkoutPlan(nodes: nodes)
    }

    static func plan(
        for exercise: PrescribedExercise,
        catalogStore: CatalogStore? = nil,
        customExercises: [CustomExercise] = []
    ) -> WorkoutExercisePlan {
        // Seul le format classique porte une mesure en temps ou en distance.
        let measure = exercise.format == .classic ? exercise.measure : .weightReps
        return WorkoutExercisePlan(
            id: exercise.id,
            exerciseId: exercise.exerciseId,
            displayName: exercise.displayName,
            format: WorkoutFormat(rawValue: exercise.formatRaw) ?? .classic,
            loadKind: resolvedLoadKind(for: exercise, catalogStore: catalogStore, customExercises: customExercises),
            side: exercise.sideConvention,
            setCount: exercise.sets,
            repsLower: exercise.repsLower,
            repsUpper: exercise.repsUpper,
            restSeconds: exercise.restSeconds,
            tempo: exercise.tempo,
            targetEffort: exercise.targetEffort,
            targetWeight: exercise.targetWeight,
            percentOneRepMax: exercise.percentOneRepMax,
            percentMaxReps: exercise.percentMaxReps,
            notes: exercise.notes,
            pyramidReps: exercise.pyramidReps,
            pyramidMinRest: exercise.pyramidMinRest,
            pyramidMaxRest: exercise.pyramidMaxRest,
            dropset: dropsetPlan(for: exercise),
            restPause: restPausePlan(for: exercise),
            myoReps: myoRepsPlan(for: exercise),
            intervalWorkSeconds: exercise.intervalWork,
            intervalRestSeconds: exercise.intervalRest,
            intervalRounds: exercise.intervalRounds,
            countdownSeconds: exercise.intervalCountdownSeconds,
            amrapSeconds: exercise.amrapSeconds,
            capSeconds: exercise.forTimeCapSeconds,
            measure: measure == .weightReps ? nil : measure,
            targetDurationSeconds: measure.measuresDuration ? exercise.targetDurationSeconds : nil,
            targetDistanceMeters: measure.measuresDistance ? exercise.targetDistanceMeters : nil
        )
    }

    /// Materiel d'un exercice : catalogue, sinon exercice personnalise.
    /// `nil` quand il n'est pas connu.
    static func equipment(
        forExerciseId exerciseId: String,
        catalogStore: CatalogStore?,
        customExercises: [CustomExercise]
    ) -> String? {
        if let catalogExercise = catalogStore?.exercise(id: exerciseId) {
            return catalogExercise.equipment
        }
        let custom = customExercises.first { $0.id.uuidString == exerciseId }
        return custom.flatMap { $0.equipment.isEmpty ? nil : $0.equipment }
    }

    /// Repos par defaut d'un exercice nouvellement prescrit, selon son
    /// materiel et les reglages.
    static func defaultRestSeconds(
        forExerciseId exerciseId: String,
        catalogStore: CatalogStore?,
        context: ModelContext
    ) -> Int {
        let customExercises = (try? context.fetch(FetchDescriptor<CustomExercise>())) ?? []
        let equipment = equipment(forExerciseId: exerciseId, catalogStore: catalogStore, customExercises: customExercises)
        return WorkoutSettings.restDefaults.seconds(forEquipment: equipment)
    }

    /// Type de charge effectif : declaration explicite de la prescription,
    /// sinon exercice personnalise, sinon deduction depuis le catalogue.
    static func resolvedLoadKind(
        for exercise: PrescribedExercise,
        catalogStore: CatalogStore?,
        customExercises: [CustomExercise]
    ) -> LoadKind {
        if let declared = exercise.prescribedLoadKind { return declared }
        if let catalogExercise = catalogStore?.exercise(id: exercise.exerciseId) {
            return ExerciseClassification.loadKind(for: catalogExercise)
        }
        if let custom = customExercises.first(where: { $0.id.uuidString == exercise.exerciseId }) {
            return custom.defaultLoadKind
        }
        // Exercice inconnu : on ne devine une charge externe que si la
        // prescription en implique une.
        return exercise.targetWeight == nil && exercise.percentOneRepMax == nil ? .unknown : .external
    }

    private static func dropsetPlan(for exercise: PrescribedExercise) -> DropsetPlan? {
        guard !exercise.dropsetDrops.isEmpty else { return nil }
        let plan = DropsetPlan(
            drops: exercise.dropsetDrops,
            usesPercent: exercise.dropsetUsesPercent,
            restSeconds: exercise.dropsetRestSeconds
        )
        return plan.isValid ? plan : nil
    }

    private static func restPausePlan(for exercise: PrescribedExercise) -> RestPausePlan? {
        guard exercise.restPauseMaxMiniSets > 0 else { return nil }
        let plan = RestPausePlan(
            microRestSeconds: exercise.restPauseMicroRestSeconds,
            maximumMiniSets: exercise.restPauseMaxMiniSets,
            minimumReps: exercise.restPauseMinimumReps
        )
        return plan.isValid ? plan : nil
    }

    private static func myoRepsPlan(for exercise: PrescribedExercise) -> MyoRepsPlan? {
        guard exercise.myoRepsMaxMiniSets > 0 else { return nil }
        let plan = MyoRepsPlan(
            activationRepsLower: exercise.myoRepsActivationLower,
            activationRepsUpper: exercise.myoRepsActivationUpper,
            targetRepsInReserve: exercise.myoRepsTargetRepsInReserve,
            miniSetReps: exercise.myoRepsMiniSetReps,
            maximumMiniSets: exercise.myoRepsMaxMiniSets,
            restSeconds: exercise.myoRepsRestSeconds
        )
        return plan.isValid ? plan : nil
    }
}
