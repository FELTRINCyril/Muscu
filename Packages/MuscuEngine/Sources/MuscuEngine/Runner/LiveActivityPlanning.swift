import Foundation

/// Ce que la Live Activity d'une seance en cours peut proposer.
///
/// Un bouton « Valider la série » sur l'ecran verrouille valide SANS saisie.
/// Il n'est donc propose que lorsque la serie est entierement connue
/// d'avance : serie classique poids x repetitions, charge ET repetitions
/// proposees. Dans tous les autres cas (palier de dropset, mini-serie,
/// serie au temps, charge inconnue, 1RM manquant...), la Live Activity
/// propose d'ouvrir l'application plutot que d'enregistrer une valeur
/// inventee.
///
/// Idee de la validation depuis l'ecran verrouille : Ischys (MIT). Aucun
/// code repris, la logique est propre a Muscu.
public enum LiveActivityPlanning {
    /// Serie a valider d'un tap.
    public struct SetProposal: Equatable, Sendable {
        public var weightKilograms: Double
        public var reps: Int

        public init(weightKilograms: Double, reps: Int) {
            self.weightKilograms = weightKilograms
            self.reps = reps
        }
    }

    /// Serie validable d'un tap, ou `nil` si une saisie est necessaire.
    ///
    /// - Parameters:
    ///   - proposedWeightKilograms: charge que l'application pre-remplirait.
    ///     `nil` = charge inconnue, jamais confondue avec zero.
    ///   - proposedReps: repetitions que l'application pre-remplirait,
    ///     `nil` si elles ne sont pas connues.
    ///   - needsReferenceValue: la charge ou les repetitions dependent d'un
    ///     1RM ou d'un maximum de repetitions qui n'a pas ete renseigne.
    public static func quickLogProposal(
        for target: WorkoutSetTarget,
        proposedWeightKilograms: Double?,
        proposedReps: Int?,
        needsReferenceValue: Bool
    ) -> SetProposal? {
        let exercise = target.exercise
        guard exercise.format == .classic,
              !target.isSubSet,
              exercise.effectiveMeasure == .weightReps,
              !needsReferenceValue,
              let reps = proposedReps, reps > 0 else { return nil }

        // Au poids du corps, zero est la charge attendue : c'est une valeur,
        // pas une absence. Partout ailleurs, une charge nulle signifie
        // qu'aucune charge n'est connue.
        switch exercise.loadKind {
        case .bodyweight:
            let weight = proposedWeightKilograms ?? 0
            guard weight >= 0, weight.isFinite else { return nil }
            return SetProposal(weightKilograms: weight, reps: reps)
        case .external, .weighted, .assisted, .unknown:
            guard let weight = proposedWeightKilograms, weight > 0, weight.isFinite else { return nil }
            return SetProposal(weightKilograms: weight, reps: reps)
        }
    }

    /// Etape qui suivra la validation de la serie courante.
    public enum NextStep: Equatable, Sendable {
        case set(exerciseName: String, setNumber: Int, totalSets: Int, isSameExercise: Bool)
        case timedBlock(exerciseName: String)
        case finished
    }

    /// Etape suivante, decidee par la machine a etats exactement comme le
    /// fera la validation : la Live Activity n'invente pas son propre ordre.
    /// La position n'est PAS modifiee : c'est une simulation.
    public static func nextStep(
        after position: WorkoutPosition,
        in plan: WorkoutPlan,
        outcome: WorkoutSetOutcome
    ) -> NextStep {
        let currentExerciseId: UUID?
        switch WorkoutStateMachine.step(at: position, in: plan) {
        case .logSet(let target): currentExerciseId = target.exercise.id
        case .timedBlock(let exercise): currentExerciseId = exercise.id
        case .finished: return .finished
        }
        let next = WorkoutStateMachine.advance(from: position, in: plan, outcome: outcome).position
        switch WorkoutStateMachine.step(at: next, in: plan) {
        case .logSet(let target):
            return .set(
                exerciseName: target.exercise.displayName,
                setNumber: target.setNumber,
                totalSets: target.totalSets,
                isSameExercise: target.exercise.id == currentExerciseId
            )
        case .timedBlock(let exercise):
            return .timedBlock(exerciseName: exercise.displayName)
        case .finished:
            return .finished
        }
    }
}
