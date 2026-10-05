import Foundation

/// Ajustement d'un repos en cours : « −15 s » et « +15 s », dans
/// l'application, sur la Live Activity et sur la montre.
///
/// Le temps restant est borne : jamais negatif (un « −15 s » a 10 s de la
/// fin termine le repos, il ne passe pas sous zero), jamais au-dela de
/// `maximumRemainingSeconds`. La duree totale suit le meme ajustement pour
/// que la barre de progression reste juste.
public enum RestAdjustment {
    /// Seul pas propose, dans un sens ou dans l'autre.
    public static let stepSeconds = 15
    /// Au-dela, ce n'est plus un repos entre deux series.
    public static let maximumRemainingSeconds = 1_800

    public enum Result: Equatable, Sendable {
        /// Le repos continue jusqu'a `endDate`, sur `totalSeconds` au total.
        case running(endDate: Date, totalSeconds: Int)
        /// Le repos atteint zero : il est termine.
        case finished
    }

    /// Ajustements acceptes : un pas, dans un sens ou dans l'autre.
    public static func isAllowed(_ seconds: Int) -> Bool {
        seconds == stepSeconds || seconds == -stepSeconds
    }

    public static func adjust(endDate: Date, totalSeconds: Int, by seconds: Int, now: Date) -> Result {
        let remaining = max(0, endDate.timeIntervalSince(now))
        let wanted = remaining + Double(seconds)
        guard wanted > 0 else { return .finished }
        let bounded = min(wanted, Double(maximumRemainingSeconds))
        let applied = bounded - remaining
        let newTotal = max(1, totalSeconds + Int(applied.rounded()))
        return .running(endDate: now.addingTimeInterval(bounded), totalSeconds: newTotal)
    }
}
