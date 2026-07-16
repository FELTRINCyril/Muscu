import Foundation

public enum OneRepMax {
    /// Formule d'Epley. reps <= 0 -> 0 ; reps == 1 -> poids tel quel.
    public static func epley(weight: Double, reps: Int) -> Double {
        guard reps > 0 else { return 0 }
        guard reps > 1 else { return weight }
        return weight * (1.0 + Double(reps) / 30.0)
    }

    /// Charge de travail arrondie vers le bas au palier de chargement reel.
    public static func workingLoad(oneRepMax: Double, percent: Double, increment: Double = 2.5) -> Double {
        guard oneRepMax > 0, percent > 0, increment > 0 else { return 0 }
        let raw = oneRepMax * percent / 100.0
        return (raw / increment).rounded(.down) * increment
    }
}
