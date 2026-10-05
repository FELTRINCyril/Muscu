import Foundation

/// Ce que la Live Activity d'une seance en cours peut proposer.
///
/// « Valider » sur l'ecran verrouille enregistre EXACTEMENT ce que l'ecran
/// de saisie de l'application pre-remplit : l'utilisateur qui veut autre
/// chose ouvre l'application (un tap sur le bandeau suffit). Le bouton est
/// donc propose des qu'une serie est a faire et que la saisie de
/// l'application se valide sans rien taper :
///
/// - serie classique, dropset, rest-pause, myo-reps (paliers compris) :
///   charge et repetitions pre-remplies, telles quelles. Une charge que
///   l'application laisse a zero (aucune charge connue, 1RM manquant) est
///   validee a zero, comme le ferait « Valider » dans l'application ;
///   l'utilisateur la corrige dans l'historique ;
/// - pyramide : les repetitions du palier courant, fixees a la creation, au
///   poids du corps (meme chemin que `logPyramidStep`) ;
/// - serie au temps ou a la distance, formats chronometres (intervalles,
///   EMOM, AMRAP, For Time) : rien, il n'y a pas de valeur a valider sans
///   saisie. Aucun bouton n'est alors affiche.
///
/// Idee de la validation depuis l'ecran verrouille : Ischys (MIT). Aucun
/// code repris, la logique est propre a Muscu.
public enum LiveActivityPlanning {
    /// Serie a valider d'un tap.
    public struct SetProposal: Equatable, Sendable {
        public var weightKilograms: Double
        public var reps: Int
        /// Palier de pyramide : enregistre par le chemin de la pyramide.
        public var isPyramidStep: Bool

        public init(weightKilograms: Double, reps: Int, isPyramidStep: Bool = false) {
            self.weightKilograms = weightKilograms
            self.reps = reps
            self.isPyramidStep = isPyramidStep
        }
    }

    /// Serie validable d'un tap, ou `nil` si la serie ne se valide pas sans
    /// saisie (temps, distance, format chronometre).
    ///
    /// - Parameters:
    ///   - prefillWeightKilograms: charge pre-remplie par l'ecran de saisie
    ///     (`WorkoutState.prefillWeight`), zero compris.
    ///   - prefillReps: repetitions pre-remplies (`WorkoutState.prefillReps`).
    public static func quickLogProposal(
        for target: WorkoutSetTarget,
        prefillWeightKilograms: Double,
        prefillReps: Int
    ) -> SetProposal? {
        let exercise = target.exercise
        switch exercise.format {
        case .intervals, .emom, .amrap, .forTime:
            return nil
        case .pyramid:
            // Les repetitions du palier sont celles de la pyramide : le
            // deroule les affiche et les pre-remplit, sans charge.
            let reps = target.targetRepsLower
            guard reps > 0 else { return nil }
            return SetProposal(weightKilograms: 0, reps: reps, isPyramidStep: true)
        case .classic, .dropset, .restPause, .myoReps:
            guard exercise.effectiveMeasure == .weightReps,
                  prefillReps > 0,
                  prefillWeightKilograms >= 0, prefillWeightKilograms.isFinite else { return nil }
            return SetProposal(weightKilograms: prefillWeightKilograms, reps: prefillReps)
        }
    }

    /// Palier de montee en charge a valider pendant l'echauffement guide :
    /// le premier qui n'est pas encore coche, comme la liste de l'ecran
    /// d'echauffement. `nil` si tout est fait (ou rien n'est prevu).
    public static func nextWarmupRampIndex(rampCount: Int, loggedIndexes: Set<Int>) -> Int? {
        guard rampCount > 0 else { return nil }
        return (0..<rampCount).first { !loggedIndexes.contains($0) }
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
