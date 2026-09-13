import Foundation

/// Sens dans lequel un objectif progresse.
public enum GoalDirection: String, Codable, CaseIterable, Sendable {
    case increase
    case decrease
}

/// Ce que l'objectif vise. Chaque cas porte sa propre unite et son propre
/// sens de comparaison : on ne compare jamais des kilos a des seances.
public enum GoalTarget: Codable, Equatable, Hashable, Sendable {
    case sessionsPerWeek(count: Int)
    case weeklySetsForMuscle(muscle: String, sets: Int)
    case exerciseOneRepMax(exerciseId: String, kilograms: Double)
    case exerciseReps(exerciseId: String, reps: Int)
    case bodyMeasurement(kindRaw: String, value: Double, direction: GoalDirection)

    public var direction: GoalDirection {
        switch self {
        case .sessionsPerWeek, .weeklySetsForMuscle, .exerciseOneRepMax, .exerciseReps:
            return .increase
        case .bodyMeasurement(_, _, let direction):
            return direction
        }
    }

    public var targetValue: Double {
        switch self {
        case .sessionsPerWeek(let count): return Double(count)
        case .weeklySetsForMuscle(_, let sets): return Double(sets)
        case .exerciseOneRepMax(_, let kilograms): return kilograms
        case .exerciseReps(_, let reps): return Double(reps)
        case .bodyMeasurement(_, let value, _): return value
        }
    }

    public var unitSymbol: String {
        switch self {
        case .sessionsPerWeek, .weeklySetsForMuscle, .exerciseReps: return ""
        case .exerciseOneRepMax: return "kg"
        case .bodyMeasurement(let kindRaw, _, _): return kindRaw == "bodyweight" ? "kg" : "cm"
        }
    }

    /// Bornes de bon sens. Elles servent a refuser une saisie manifestement
    /// erronee, jamais a juger une intention.
    public var isWithinSaneBounds: Bool {
        switch self {
        case .sessionsPerWeek(let count): return (1...14).contains(count)
        case .weeklySetsForMuscle(_, let sets): return (1...60).contains(sets)
        case .exerciseOneRepMax(_, let kilograms): return kilograms.isFinite && (1...600).contains(kilograms)
        case .exerciseReps(_, let reps): return (1...1_000).contains(reps)
        case .bodyMeasurement(let kindRaw, let value, _):
            guard value.isFinite else { return false }
            return kindRaw == "bodyweight" ? (25...400).contains(value) : (10...300).contains(value)
        }
    }
}

/// Etat d'un objectif. Mettre en pause ou archiver ne reecrit jamais
/// l'historique : seul l'objectif change d'etat.
public enum GoalState: String, Codable, CaseIterable, Sendable {
    case active
    case paused
    case reached
    case archived
}

/// Avancement d'un objectif, tel qu'il doit etre presente.
public struct GoalProgress: Equatable, Sendable {
    /// Valeur observee. `nil` quand aucune donnee ne permet de la calculer :
    /// l'objectif s'affiche alors « pas encore mesurable », jamais 0 %.
    public var current: Double?
    public var target: Double
    public var startValue: Double?
    /// Avancement de 0 a 1. `nil` si non calculable.
    public var ratio: Double?
    public var isReached: Bool
    /// Phrase factuelle et neutre, sans jugement ni culpabilisation.
    public var statusText: String

    public init(
        current: Double?,
        target: Double,
        startValue: Double? = nil,
        ratio: Double?,
        isReached: Bool,
        statusText: String
    ) {
        self.current = current
        self.target = target
        self.startValue = startValue
        self.ratio = ratio
        self.isReached = isReached
        self.statusText = statusText
    }
}

/// Valeurs observees nécessaires pour evaluer un objectif. L'application les
/// calcule depuis ses donnees ; le moteur ne connait pas le stockage.
public struct GoalObservation: Equatable, Sendable {
    public var current: Double?
    public var startValue: Double?

    public init(current: Double?, startValue: Double? = nil) {
        self.current = current
        self.startValue = startValue
    }
}

public enum GoalEvaluator {
    /// Avancement d'un objectif au vu de la valeur observee.
    ///
    /// Trois principes :
    /// 1. sans valeur observee, on le dit — on n'affiche pas 0 % ;
    /// 2. un objectif en baisse se mesure depuis son point de depart ;
    /// 3. les formulations restent factuelles, jamais culpabilisantes.
    public static func progress(target: GoalTarget, observation: GoalObservation) -> GoalProgress {
        let targetValue = target.targetValue
        guard let current = observation.current else {
            return GoalProgress(
                current: nil,
                target: targetValue,
                startValue: observation.startValue,
                ratio: nil,
                isReached: false,
                statusText: "Pas encore de donnée pour mesurer cet objectif."
            )
        }

        switch target.direction {
        case .increase:
            let ratio = targetValue > 0 ? min(1, max(0, current / targetValue)) : nil
            let reached = current >= targetValue
            return GoalProgress(
                current: current,
                target: targetValue,
                startValue: observation.startValue,
                ratio: ratio,
                isReached: reached,
                statusText: reached
                    ? "Objectif atteint : \(formatted(current)) pour \(formatted(targetValue)) visés."
                    : "\(formatted(current)) sur \(formatted(targetValue)) visés."
            )

        case .decrease:
            let reached = current <= targetValue
            // Sans point de depart, on ne peut pas exprimer d'avancement :
            // « 80 kg vers 75 kg » ne dit pas d'ou l'on part.
            guard let start = observation.startValue, start > targetValue else {
                return GoalProgress(
                    current: current,
                    target: targetValue,
                    startValue: observation.startValue,
                    ratio: reached ? 1 : nil,
                    isReached: reached,
                    statusText: reached
                        ? "Objectif atteint : \(formatted(current)) pour \(formatted(targetValue)) visés."
                        : "\(formatted(current)) aujourd'hui, \(formatted(targetValue)) visés."
                )
            }
            let ratio = min(1, max(0, (start - current) / (start - targetValue)))
            return GoalProgress(
                current: current,
                target: targetValue,
                startValue: start,
                ratio: ratio,
                isReached: reached,
                statusText: reached
                    ? "Objectif atteint : \(formatted(current)) pour \(formatted(targetValue)) visés."
                    : "\(formatted(current)) aujourd'hui, depuis \(formatted(start)), \(formatted(targetValue)) visés."
            )
        }
    }

    /// Message prudent pour les objectifs portant sur le corps. Il ne juge
    /// pas l'objectif et ne donne aucune consigne : il rappelle simplement
    /// que l'application ne suit pas la sante de l'utilisateur.
    public static func cautionMessage(for target: GoalTarget) -> String? {
        guard case .bodyMeasurement = target else { return nil }
        return "Muscu n'évalue pas votre santé et ne donne aucun conseil nutritionnel. Pour un objectif de poids ou de mesure, l'avis d'un professionnel de santé reste la référence."
    }

    private static func formatted(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}
