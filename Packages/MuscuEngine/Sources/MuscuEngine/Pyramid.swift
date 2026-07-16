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
}
