import Foundation

/// Regles pures de la fusion de deux exercices : ou mene une redirection,
/// quel record survit, comment se reecrit une reference.
///
/// La fusion elle-meme (reaffecter les series, les prescriptions...) vit
/// dans l'application ; tout ce qui decide d'une VALEUR est ici, teste.
public enum ExerciseMerge {
    /// Longueur maximale d'une chaine de redirections suivie. Une chaine plus
    /// longue (ou un cycle, venu d'un import ou de deux appareils) est
    /// coupee : on ne boucle jamais.
    public static let maximumChainLength = 16

    /// Exercice final vers lequel mene `exerciseId`, en suivant les
    /// redirections (`A -> B -> C` donne `C`). Un cycle ramene a l'exercice
    /// de depart : aucune reference n'est alors reecrite.
    public static func resolve(_ exerciseId: String, redirects: [String: String]) -> String {
        var current = exerciseId
        var visited: Set<String> = [exerciseId]
        for _ in 0..<maximumChainLength {
            guard let next = redirects[current], !next.isEmpty, next != current else { return current }
            guard visited.insert(next).inserted else { return exerciseId }
            current = next
        }
        return exerciseId
    }

    /// Vrai si rediriger `duplicate` vers `survivor` creerait une boucle
    /// (le survivant est lui-meme redirige, directement ou non, vers le
    /// doublon).
    public static func wouldCreateCycle(duplicate: String, survivor: String, redirects: [String: String]) -> Bool {
        guard duplicate != survivor else { return true }
        var updated = redirects
        updated[duplicate] = survivor
        return resolve(duplicate, redirects: updated) == duplicate
    }

    /// Identifiants d'une liste apres fusion : le doublon devient le
    /// survivant, sans laisser deux fois le meme identifiant, ordre conserve.
    public static func replacing(_ duplicate: String, with survivor: String, in identifiers: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for identifier in identifiers {
            let replaced = identifier == duplicate ? survivor : identifier
            if seen.insert(replaced).inserted { result.append(replaced) }
        }
        return result
    }

    /// Record conserve apres fusion : le meilleur des deux exercices, jamais
    /// moins que ce qu'avait l'un d'eux (aucune regression). A egalite, le
    /// survivant garde le sien — son origine ne change pas sans raison.
    public static func reconcile(
        survivor: RecordValue?,
        duplicate: RecordValue?,
        lowerIsBetter: Bool
    ) -> (value: RecordValue, fromDuplicate: Bool)? {
        switch (survivor, duplicate) {
        case (nil, nil):
            return nil
        case (let kept?, nil):
            return (kept, false)
        case (nil, let moved?):
            return (moved, true)
        case (let kept?, let moved?):
            let better = lowerIsBetter
                ? moved.value < kept.value - RecordRevision.tolerance
                : moved.value > kept.value + RecordRevision.tolerance
            return better ? (moved, true) : (kept, false)
        }
    }
}

extension GoalTarget {
    /// La meme cible, reportee sur l'exercice conserve apres une fusion.
    /// Les cibles sans exercice sont rendues telles quelles.
    public func replacingExercise(_ duplicate: String, with survivor: String) -> GoalTarget {
        switch self {
        case .exerciseOneRepMax(let exerciseId, let kilograms) where exerciseId == duplicate:
            return .exerciseOneRepMax(exerciseId: survivor, kilograms: kilograms)
        case .exerciseReps(let exerciseId, let reps) where exerciseId == duplicate:
            return .exerciseReps(exerciseId: survivor, reps: reps)
        default:
            return self
        }
    }
}
