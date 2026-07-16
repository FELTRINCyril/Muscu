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
