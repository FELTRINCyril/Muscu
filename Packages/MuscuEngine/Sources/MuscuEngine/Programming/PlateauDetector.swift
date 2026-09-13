import Foundation

/// Resultat d'une detection de plateau. La fenetre et le seuil sont toujours
/// renvoyes : l'utilisateur doit pouvoir voir sur quoi repose la detection.
public struct PlateauFinding: Equatable, Sendable {
    public var isPlateau: Bool
    /// Nombre d'expositions comparables examinees.
    public var windowSize: Int
    /// Progression relative observee sur la fenetre (0.02 = +2 %).
    public var relativeChange: Double
    public var factors: [String]

    public init(isPlateau: Bool, windowSize: Int, relativeChange: Double, factors: [String]) {
        self.isPlateau = isPlateau
        self.windowSize = windowSize
        self.relativeChange = relativeChange
        self.factors = factors
    }
}

/// Detecte une stagnation sur plusieurs expositions comparables.
///
/// « Comparable » signifie : meme exercice, series de travail, charge reelle
/// connue. Une seance sans donnee exploitable est ignoree plutot que comptee
/// comme un echec.
public enum PlateauDetector {
    /// Nombre minimum d'expositions avant de pouvoir parler de plateau.
    public static let minimumExposures = 3
    /// En dessous de cette progression relative sur la fenetre, on considere
    /// qu'il n'y a plus de progres mesurable.
    public static let defaultThreshold = 0.02

    public static func detect(
        exposures: [ExerciseExposure],
        window: Int = minimumExposures,
        threshold: Double = defaultThreshold,
        bodyweightKilograms: Double? = nil
    ) -> PlateauFinding {
        let window = max(minimumExposures, window)
        // Les expositions arrivent de la plus recente a la plus ancienne ;
        // on raisonne dans l'ordre chronologique.
        let usable = exposures
            .prefix(window)
            .compactMap { best(in: $0, bodyweightKilograms: bodyweightKilograms) }
            .reversed()
            .map { $0 }

        guard usable.count >= window else {
            return PlateauFinding(
                isPlateau: false,
                windowSize: usable.count,
                relativeChange: 0,
                factors: ["\(usable.count) séance(s) comparable(s) : il en faut \(window) pour parler de stagnation."]
            )
        }

        guard let first = usable.first, first > 0, let last = usable.last else {
            return PlateauFinding(
                isPlateau: false,
                windowSize: usable.count,
                relativeChange: 0,
                factors: ["Aucune charge exploitable sur la période."]
            )
        }

        let change = (last - first) / first
        let isPlateau = change < threshold
        let percent = Int((change * 100).rounded())
        return PlateauFinding(
            isPlateau: isPlateau,
            windowSize: usable.count,
            relativeChange: change,
            factors: [
                "\(usable.count) séances comparées, de \(formatted(first)) à \(formatted(last)) kg estimés.",
                "Progression de \(percent) % sur la période, seuil fixé à \(Int(threshold * 100)) %.",
            ]
        )
    }

    /// Meilleur 1RM estime d'une exposition, ou a defaut la meilleure charge
    /// effective. `nil` si rien n'est exploitable.
    private static func best(in exposure: ExerciseExposure, bodyweightKilograms: Double?) -> Double? {
        let inputs = exposure.workingSets.map {
            SetMetricsInput(
                weightKilograms: $0.weightKilograms,
                reps: $0.reps,
                loadKind: $0.loadKind,
                bodyweightKilograms: bodyweightKilograms
            )
        }
        if let estimated = inputs.compactMap(SetMetrics.estimatedOneRepMax).max() { return estimated }
        // Exercice au poids du corps : on compare alors les repetitions.
        let reps = exposure.workingSets.map(\.reps).max()
        return reps.map(Double.init)
    }

    private static func formatted(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}
