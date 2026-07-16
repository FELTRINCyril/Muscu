import Foundation

public struct IntervalSegment: Equatable, Sendable {
    public enum Kind: Sendable { case work, rest }
    public let kind: Kind
    public let seconds: Int
    public let round: Int
}

public struct IntervalPlan: Equatable, Sendable {
    public var workSeconds: Int
    public var restSeconds: Int
    public var rounds: Int

    public init(workSeconds: Int, restSeconds: Int, rounds: Int) {
        self.workSeconds = workSeconds
        self.restSeconds = restSeconds
        self.rounds = rounds
    }

    public static func thirtyThirty(rounds: Int) -> IntervalPlan {
        IntervalPlan(workSeconds: 30, restSeconds: 30, rounds: rounds)
    }
    public static let tabata = IntervalPlan(workSeconds: 20, restSeconds: 10, rounds: 8)
    public static func emom(minutes: Int) -> IntervalPlan {
        IntervalPlan(workSeconds: 60, restSeconds: 0, rounds: minutes)
    }

    /// Alternance travail/repos ; pas de segment de repos apres le dernier round.
    public func segments() -> [IntervalSegment] {
        var result: [IntervalSegment] = []
        for round in 1...max(1, rounds) {
            result.append(IntervalSegment(kind: .work, seconds: workSeconds, round: round))
            if round < rounds && restSeconds > 0 {
                result.append(IntervalSegment(kind: .rest, seconds: restSeconds, round: round))
            }
        }
        return result
    }

    public var totalDuration: Int { segments().reduce(0) { $0 + $1.seconds } }
}
