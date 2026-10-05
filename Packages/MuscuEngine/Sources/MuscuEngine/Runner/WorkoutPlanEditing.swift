import Foundation

/// Modifications du deroule pendant la seance : ajouter un exercice,
/// reordonner ceux qui restent. Pures et testables, comme la machine a
/// etats : la vue ne decide jamais de ce qui peut bouger.
///
/// Regle centrale : un exercice **commence** (au moins une serie enregistree,
/// echauffement compris) ne bouge jamais, et rien de ce qui precede la
/// position courante ne bouge non plus. Seuls les noeuds a partir de la
/// position courante, sans aucune serie enregistree, sont reordonnables.
public enum WorkoutPlanEditing {
    /// Ajoute un exercice seul en fin de seance. Si la seance etait
    /// terminee (position au-dela du dernier noeud), la position designe
    /// desormais ce nouvel exercice : c'est le cas normal d'une seance libre.
    public static func appending(_ exercise: WorkoutExercisePlan, to plan: WorkoutPlan) -> WorkoutPlan {
        var result = plan
        result.nodes.append(.single(exercise))
        return result
    }

    /// Un noeud est commence des qu'un de ses exercices a une serie
    /// enregistree.
    public static func isStarted(_ node: WorkoutNode, startedExerciseIDs: Set<UUID>) -> Bool {
        node.exercises.contains { startedExerciseIDs.contains($0.id) }
    }

    /// Index des noeuds reordonnables, dans l'ordre actuel.
    public static func reorderableNodeIndices(
        in plan: WorkoutPlan,
        position: WorkoutPosition,
        startedExerciseIDs: Set<UUID>
    ) -> [Int] {
        let current = WorkoutStateMachine.clamp(position, in: plan)
        guard current.nodeIndex < plan.nodes.count else { return [] }
        return (current.nodeIndex..<plan.nodes.count).filter { index in
            let node = plan.nodes[index]
            return !node.exercises.isEmpty && !isStarted(node, startedExerciseIDs: startedExerciseIDs)
        }
    }

    /// Reordonne les noeuds reordonnables selon `newOrder` (identifiants de
    /// noeuds). Les noeuds verrouilles gardent leur index : les noeuds
    /// deplaces occupent les memes emplacements, dans le nouvel ordre.
    ///
    /// Retourne `nil` si `newOrder` n'est pas exactement une permutation des
    /// noeuds reordonnables : rien n'est alors modifie.
    ///
    /// La position reste sur le meme index de noeud. Si le noeud a cet index
    /// a change, elle repart du debut du nouveau noeud (il n'a, par
    /// construction, aucune serie enregistree).
    public static func reordering(
        _ plan: WorkoutPlan,
        position: WorkoutPosition,
        startedExerciseIDs: Set<UUID>,
        newOrder: [UUID]
    ) -> (plan: WorkoutPlan, position: WorkoutPosition)? {
        let slots = reorderableNodeIndices(in: plan, position: position, startedExerciseIDs: startedExerciseIDs)
        let movableIDs = slots.map { plan.nodes[$0].id }
        guard newOrder.count == movableIDs.count,
              Set(newOrder) == Set(movableIDs),
              Set(newOrder).count == newOrder.count else { return nil }

        let byID = Dictionary(uniqueKeysWithValues: slots.map { (plan.nodes[$0].id, plan.nodes[$0]) })
        var result = plan
        for (slot, id) in zip(slots, newOrder) {
            guard let node = byID[id] else { return nil }
            result.nodes[slot] = node
        }

        let current = WorkoutStateMachine.clamp(position, in: plan)
        var newPosition = current
        if current.nodeIndex < plan.nodes.count,
           result.nodes[current.nodeIndex].id != plan.nodes[current.nodeIndex].id {
            newPosition = WorkoutPosition(nodeIndex: current.nodeIndex)
        }
        return (result, WorkoutStateMachine.clamp(newPosition, in: result))
    }

    /// Correspondance des index « a plat » (`WorkoutPlan.allExercises`) d'un
    /// deroule a l'autre, par identifiant d'exercice. Les series
    /// enregistrees designent leur exercice par cet index : il faut les
    /// renumeroter quand des groupes de tailles differentes changent de
    /// place, sinon une serie pointerait vers un autre exercice.
    public static func flatIndexMapping(from old: WorkoutPlan, to new: WorkoutPlan) -> [Int: Int] {
        let newIndexByID = Dictionary(
            new.allExercises.enumerated().map { ($1.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var mapping: [Int: Int] = [:]
        for (oldIndex, exercise) in old.allExercises.enumerated() {
            if let newIndex = newIndexByID[exercise.id] { mapping[oldIndex] = newIndex }
        }
        return mapping
    }
}
