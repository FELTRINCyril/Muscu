import Foundation

/// Alternatives pertinentes pour remplacer un exercice :
/// 1. Exercice de la liste blanche -> les autres membres de son groupe de
///    mouvement, tries par rang (squat barre -> presse, smith, front...).
/// 2. Sinon (exo perso, hors liste) -> repli catalogue : meme muscle principal
///    et meme mechanic, staples en tete puis tri alphabetique, plafonne a 12.
public enum ExerciseAlternatives {
    public static func alternatives(for exerciseId: String, in catalog: ExerciseCatalog) -> [CatalogExercise] {
        let byId = Dictionary(uniqueKeysWithValues: catalog.all.map { ($0.id, $0) })

        if let staple = StapleExercises.staple(for: exerciseId) {
            return StapleExercises.members(of: staple.group)
                .filter { $0.catalogId != exerciseId }
                .compactMap { byId[$0.catalogId] }
        }

        guard let current = byId[exerciseId],
              let muscle = current.primaryMuscles.first else {
            return []
        }

        let candidates = catalog.all.filter { exercise in
            exercise.id != exerciseId
                && exercise.primaryMuscles.contains(muscle)
                && exercise.mechanic == current.mechanic
                && exercise.category != "stretching"
        }
        let sorted = candidates.sorted { lhs, rhs in
            let lhsIsStaple = StapleExercises.staple(for: lhs.id) != nil
            let rhsIsStaple = StapleExercises.staple(for: rhs.id) != nil
            if lhsIsStaple != rhsIsStaple { return lhsIsStaple }
            return lhs.id < rhs.id
        }
        return Array(sorted.prefix(12))
    }
}
