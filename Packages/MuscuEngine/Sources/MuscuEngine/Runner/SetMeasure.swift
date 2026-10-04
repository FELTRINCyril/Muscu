import Foundation

/// Ce que mesure une serie classique. Par defaut une charge et des
/// repetitions ; un gainage se mesure en temps, un portage ou une course en
/// distance, une course chronometree en temps ET distance.
///
/// Seul le format classique porte une mesure : les formats chronometres
/// (AMRAP, For Time...) ont deja la leur, et les techniques d'intensification
/// (dropset, rest-pause, myo-reps) n'ont de sens qu'en repetitions.
public enum SetMeasure: String, Codable, CaseIterable, Sendable {
    case weightReps
    case duration
    case distance
    case durationAndDistance

    public var measuresReps: Bool { self == .weightReps }
    public var measuresDuration: Bool { self == .duration || self == .durationAndDistance }
    public var measuresDistance: Bool { self == .distance || self == .durationAndDistance }

    /// Mesure deduite des cibles d'une prescription. Les cibles persistees
    /// valent zero quand elles ne sont pas prescrites : une cible strictement
    /// positive est donc le seul signal fiable.
    public init(targetDurationSeconds: Int, targetDistanceMeters: Double) {
        let hasDuration = targetDurationSeconds > 0
        let hasDistance = targetDistanceMeters.isFinite && targetDistanceMeters > 0
        switch (hasDuration, hasDistance) {
        case (true, true): self = .durationAndDistance
        case (true, false): self = .duration
        case (false, true): self = .distance
        case (false, false): self = .weightReps
        }
    }

    /// Cible de duree par defaut quand l'utilisateur choisit cette mesure
    /// (un gainage courant), en secondes.
    public static let defaultTargetDurationSeconds = 30
    /// Cible de distance par defaut, en metres.
    public static let defaultTargetDistanceMeters: Double = 100

    /// Bornes de saisie, identiques a la validation d'import.
    public static let durationRange = 1...86_400
    public static let distanceRange: ClosedRange<Double> = 0.1...1_000_000
}

/// Resultat d'une serie mesuree en temps et / ou en distance.
public struct MeasuredSetResult: Equatable, Sendable {
    public var durationSeconds: Int?
    public var distanceMeters: Double?

    public init(durationSeconds: Int?, distanceMeters: Double?) {
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
    }

    /// Une serie mesuree n'est valide que si chaque grandeur demandee par la
    /// mesure est presente ET dans ses bornes. Une duree nulle n'est pas une
    /// serie : c'est une absence de serie.
    public func isValid(for measure: SetMeasure) -> Bool {
        guard measure != .weightReps else { return false }
        if measure.measuresDuration {
            guard let durationSeconds, SetMeasure.durationRange.contains(durationSeconds) else { return false }
        } else if durationSeconds != nil {
            return false
        }
        if measure.measuresDistance {
            guard let distanceMeters, distanceMeters.isFinite,
                  SetMeasure.distanceRange.contains(distanceMeters) else { return false }
        } else if distanceMeters != nil {
            return false
        }
        return true
    }
}

extension WorkoutExercisePlan {
    /// Mesure reellement appliquee : seul le format classique en porte une
    /// autre que poids x repetitions.
    public var effectiveMeasure: SetMeasure {
        format == .classic ? (measure ?? .weightReps) : .weightReps
    }
}
