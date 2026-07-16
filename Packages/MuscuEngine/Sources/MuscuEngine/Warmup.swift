import Foundation

public struct WarmupSet: Equatable, Sendable {
    public let weight: Double
    public let reps: Int
}

public enum Warmup {
    public static let cardioMinutes = 5
    static let ramp: [(fraction: Double, reps: Int)] = [(0.4, 8), (0.6, 5), (0.8, 2)]

    public static func rampSets(workingWeight: Double, increment: Double = 2.5) -> [WarmupSet] {
        guard workingWeight >= 30 else { return [] }
        return ramp.map { step in
            let raw = workingWeight * step.fraction
            let rounded = (raw / increment).rounded(.down) * increment
            return WarmupSet(weight: rounded, reps: step.reps)
        }
    }
}
