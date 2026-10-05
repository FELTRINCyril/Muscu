import Foundation

public struct PyramidProposal: Equatable, Sendable {
    public let name: String
    public let reps: [Int]
    public var totalVolume: Int { reps.reduce(0, +) }
}

public enum Pyramid {
    /// Paliers exprimes en fraction du max, arrondis (minimum 1 rep).
    static func steps(_ fractions: [Double], maxReps: Int) -> [Int] {
        fractions.map { max(1, Int((Double(maxReps) * $0).rounded())) }
    }

    public static func proposals(maxReps: Int) -> [PyramidProposal] {
        guard maxReps >= 1 else { return [] }
        return [
            PyramidProposal(
                name: "Montante-descendante",
                reps: steps([0.2, 0.4, 0.6, 0.4, 0.2], maxReps: maxReps)),
            PyramidProposal(
                name: "Progressive",
                reps: steps([0.1, 0.2, 0.3, 0.4, 0.5, 0.4, 0.3, 0.2, 0.1], maxReps: maxReps)),
            PyramidProposal(
                name: "Descendante",
                reps: steps([0.6, 0.5, 0.4, 0.3, 0.2, 0.1], maxReps: maxReps)),
        ]
    }

    // MARK: - Pyramide libre

    /// Bornes d'un palier saisi a la main.
    public static let allowedStepReps = 1...100
    /// Au-dela, la seance devient un circuit plus qu'une pyramide, et
    /// l'estimation de duree perd son sens.
    public static let maximumSteps = 30

    /// Paliers d'une pyramide libre, rendus valides : chaque palier borne,
    /// liste tronquee a `maximumSteps`. Une liste vide reste vide — c'est a
    /// l'editeur de refuser l'enregistrement, pas d'inventer un palier.
    public static func normalizedSteps(_ reps: [Int]) -> [Int] {
        reps.prefix(maximumSteps).map {
            min(max($0, allowedStepReps.lowerBound), allowedStepReps.upperBound)
        }
    }

    /// Proposition correspondant exactement a ces paliers, ou `nil` pour une
    /// pyramide libre. Sert a afficher « Personnalisee » sans mentir sur la
    /// forme choisie.
    public static func matchingProposal(for reps: [Int], maxReps: Int) -> PyramidProposal? {
        proposals(maxReps: maxReps).first { $0.reps == reps }
    }

    /// Palier ajoute en fin de liste : on reprend le dernier, l'utilisateur
    /// l'ajuste ensuite. Sans palier, on part du max de reps.
    public static func appendingStep(to reps: [Int], maxReps: Int) -> [Int] {
        guard reps.count < maximumSteps else { return reps }
        let next = reps.last ?? max(allowedStepReps.lowerBound, maxReps)
        return normalizedSteps(reps + [next])
    }

    /// Repos apres une serie, base sur l'intensite relative (reps faites / max).
    /// Formule de la spec : repos = min + intensite^1.5 * (max - min), arrondi a 5 s.
    public static func adaptiveRest(repsDone: Int, maxReps: Int,
                                    minRest: Int = 30, maxRest: Int = 180) -> Int {
        guard maxReps > 0, repsDone > 0, maxRest > minRest else { return minRest }
        let intensity = min(1.0, Double(repsDone) / Double(maxReps))
        let rest = Double(minRest) + pow(intensity, 1.5) * Double(maxRest - minRest)
        return Int((rest / 5.0).rounded()) * 5
    }
}
