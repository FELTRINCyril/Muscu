import Foundation

/// Etape d'un test de 1RM guide.
public struct OneRepMaxTestStep: Equatable, Sendable, Identifiable {
    public enum Kind: String, Equatable, Sendable {
        /// Montee en charge : plusieurs repetitions, effort modere.
        case warmup
        /// Tentative : une repetition, a valider ou a echouer.
        case attempt
    }

    public let id: Int
    public let kind: Kind
    public let weightKilograms: Double
    public let reps: Int
    /// Repos conseille APRES cette etape, en secondes.
    public let restSeconds: Int
    /// Part de la reference de depart, pour que l'etape reste lisible.
    public let fractionOfReference: Double

    public init(
        id: Int,
        kind: Kind,
        weightKilograms: Double,
        reps: Int,
        restSeconds: Int,
        fractionOfReference: Double
    ) {
        self.id = id
        self.kind = kind
        self.weightKilograms = weightKilograms
        self.reps = reps
        self.restSeconds = restSeconds
        self.fractionOfReference = fractionOfReference
    }
}

/// Protocole de test de 1RM, facultatif et explicitement encadre.
///
/// L'application PRIVILEGIE l'estimation : ce protocole n'existe que pour
/// l'athlete qui choisit de tester, et il refuse de produire un protocole
/// quand il n'a pas de reference fiable pour le construire.
public enum OneRepMaxTest {
    /// Reference minimale sous laquelle un test maximal n'a pas de sens :
    /// la montee en charge ne comporterait pas assez de paliers.
    public static let minimumReferenceKilograms = 30.0

    /// Paliers de montee en charge, en part de la reference.
    private static let warmupRamp: [(fraction: Double, reps: Int, rest: Int)] = [
        (0.50, 5, 120),
        (0.70, 3, 180),
        (0.85, 2, 180),
    ]

    /// Tentatives successives. Au-dela, l'athlete decide lui-meme : un
    /// protocole qui pousse indefiniment serait dangereux.
    private static let attempts: [(fraction: Double, rest: Int)] = [
        (0.95, 240),
        (1.00, 240),
        (1.03, 240),
    ]

    public static let maximumAttempts = attempts.count

    /// Construit le protocole a partir d'une reference : 1RM estime connu,
    /// ou a defaut la meilleure charge de travail.
    ///
    /// Retourne une liste VIDE quand la reference est absente ou trop
    /// faible : mieux vaut ne rien proposer qu'un protocole inventé.
    public static func protocolSteps(
        referenceOneRepMax: Double?,
        increment: Double = 2.5
    ) -> [OneRepMaxTestStep] {
        guard let reference = referenceOneRepMax,
              reference.isFinite,
              reference >= minimumReferenceKilograms,
              increment > 0 else { return [] }

        var steps: [OneRepMaxTestStep] = []
        var identifier = 0

        for step in warmupRamp {
            identifier += 1
            steps.append(OneRepMaxTestStep(
                id: identifier,
                kind: .warmup,
                weightKilograms: Units.roundedToIncrement(reference * step.fraction, increment: increment),
                reps: step.reps,
                restSeconds: step.rest,
                fractionOfReference: step.fraction
            ))
        }

        for attempt in attempts {
            identifier += 1
            steps.append(OneRepMaxTestStep(
                id: identifier,
                kind: .attempt,
                weightKilograms: Units.roundedToIncrement(reference * attempt.fraction, increment: increment),
                reps: 1,
                restSeconds: attempt.rest,
                fractionOfReference: attempt.fraction
            ))
        }

        // Une tentative doit toujours peser plus que la precedente : avec un
        // increment grossier, deux fractions voisines peuvent s'arrondir sur
        // la meme valeur, ce qui rendrait le test absurde.
        return enforceStrictProgression(steps, increment: increment)
    }

    private static func enforceStrictProgression(
        _ steps: [OneRepMaxTestStep],
        increment: Double
    ) -> [OneRepMaxTestStep] {
        var result: [OneRepMaxTestStep] = []
        var previousAttemptWeight: Double?

        for step in steps {
            guard step.kind == .attempt else {
                result.append(step)
                continue
            }
            var weight = step.weightKilograms
            if let previous = previousAttemptWeight, weight <= previous {
                weight = previous + increment
            }
            previousAttemptWeight = weight
            result.append(OneRepMaxTestStep(
                id: step.id,
                kind: step.kind,
                weightKilograms: weight,
                reps: step.reps,
                restSeconds: step.restSeconds,
                fractionOfReference: step.fractionOfReference
            ))
        }
        return result
    }

    /// Meilleure tentative REUSSIE. `nil` si aucune n'a été validée : un
    /// test raté ne produit aucun record.
    public static func result(validatedWeights: [Double]) -> Double? {
        validatedWeights.filter { $0 > 0 }.max()
    }

    /// Avertissement affiche AVANT le test, et non apres. Il n'est pas
    /// negociable : un test maximal se fait echauffe, en securite, et
    /// s'arrete des que la technique se degrade.
    public static let safetyWarning = """
    Un test de force maximale se prépare. Avant de commencer :
    • assurez-vous d’être bien échauffé et reposé ;
    • travaillez avec un pareur ou des barres de sécurité ;
    • arrêtez immédiatement si la technique se dégrade ou si une douleur apparaît.
    Ce test est facultatif : l’estimation à partir de vos séries habituelles suffit pour programmer, et Muscu la privilégie.
    """
}
