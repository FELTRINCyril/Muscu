import Foundation

/// Regle de progression typee et serialisable, attachee a une prescription.
/// Chaque cas porte ses propres seuils : aucune regle n'est devinee a partir
/// d'un texte libre.
public enum ProgressionRule: Codable, Equatable, Hashable, Sendable {
    /// Double progression : monter en repetitions dans la fourchette, puis
    /// ajouter `incrementKilograms` et revenir au bas de la fourchette.
    case doubleProgression(incrementKilograms: Double, requiredSuccesses: Int)
    /// Increment fixe de charge a chaque seance reussie.
    case linearLoad(incrementKilograms: Double, requiredSuccesses: Int)
    /// Progression en repetitions jusqu'a un plafond.
    case repsProgression(step: Int, maximumReps: Int)
    /// Progression en nombre de series jusqu'a un plafond.
    case setsProgression(step: Int, maximumSets: Int)
    /// Pourcentage du 1RM estime, avec increment de pourcentage par cycle.
    case percentOneRepMax(percent: Double, percentStep: Double)
    /// Cible d'effort : ajuster la charge pour rester dans la fenetre RIR.
    case effortTarget(targetRepsInReserve: Int, incrementKilograms: Double)
    /// Tractions lestees / assistees : le lest monte, l'assistance descend.
    case assistedOrWeighted(incrementKilograms: Double, targetReps: Int)
    /// Formats chronometres : allonger le travail ou raccourcir le repos.
    case timeProgression(workStepSeconds: Int, restStepSeconds: Int)
    /// Aucune progression automatique.
    case none

    public static let `default` = ProgressionRule.doubleProgression(
        incrementKilograms: 2.5,
        requiredSuccesses: 1
    )

    /// Nombre de seances consecutives echouees avant de proposer une
    /// reduction de charge. Volontairement conservateur et identique pour
    /// toutes les regles tant qu'aucun reglage utilisateur n'existe.
    public static let failuresBeforeDeload = 3

    public var incrementKilograms: Double? {
        switch self {
        case .doubleProgression(let increment, _),
             .linearLoad(let increment, _),
             .effortTarget(_, let increment),
             .assistedOrWeighted(let increment, _):
            return increment
        case .repsProgression, .setsProgression, .percentOneRepMax, .timeProgression, .none:
            return nil
        }
    }

    /// Verifie que les seuils sont coherents ; une regle invalide ne doit
    /// jamais etre appliquee (import, IA ou saisie manuelle).
    public var isValid: Bool {
        switch self {
        case .doubleProgression(let increment, let successes),
             .linearLoad(let increment, let successes):
            return increment.isFinite && (0.25...50).contains(increment) && (1...10).contains(successes)
        case .repsProgression(let step, let maximum):
            return (1...10).contains(step) && (1...1_000).contains(maximum)
        case .setsProgression(let step, let maximum):
            return (1...5).contains(step) && (1...20).contains(maximum)
        case .percentOneRepMax(let percent, let step):
            return percent.isFinite && (30...110).contains(percent)
                && step.isFinite && (0...20).contains(step)
        case .effortTarget(let rir, let increment):
            return (0...10).contains(rir) && increment.isFinite && (0.25...50).contains(increment)
        case .assistedOrWeighted(let increment, let reps):
            return increment.isFinite && (0.25...50).contains(increment) && (1...100).contains(reps)
        case .timeProgression(let work, let rest):
            return (0...600).contains(work) && (-600...600).contains(rest) && (work != 0 || rest != 0)
        case .none:
            return true
        }
    }
}
