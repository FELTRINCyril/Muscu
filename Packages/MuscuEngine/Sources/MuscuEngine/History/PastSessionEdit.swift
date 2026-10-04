import Foundation

/// Regles de saisie de la correction d'une seance passee. Les bornes sont
/// celles de la validation d'import : une seance corrigee doit rester
/// exportable puis reimportable telle quelle.
public enum PastSessionEdit {
    /// Au-dela d'une journee, ce n'est plus une seance mais une erreur de
    /// saisie (fin le lendemain par megarde).
    public static let maximumDurationSeconds = 86_400
    public static let weightRange: ClosedRange<Double> = 0...10_000
    public static let repsRange = 0...100_000

    public enum TimingIssue: Equatable, Sendable {
        case endBeforeStart
        case tooLong
        case inFuture
    }

    /// Probleme d'horaires, `nil` si les horaires sont acceptables. Une fin
    /// egale au debut est acceptee : une seance saisie a posteriori n'a pas
    /// toujours de duree connue.
    public static func timingIssue(start: Date, end: Date, now: Date) -> TimingIssue? {
        guard end >= start else { return .endBeforeStart }
        guard end.timeIntervalSince(start) <= Double(maximumDurationSeconds) else { return .tooLong }
        // Une minute de tolerance : l'horloge a avance pendant la saisie.
        guard end <= now.addingTimeInterval(60) else { return .inFuture }
        return nil
    }

    /// Duree en secondes entieres entre deux horaires valides.
    public static func durationSeconds(start: Date, end: Date) -> Int {
        max(0, Int(end.timeIntervalSince(start).rounded()))
    }

    /// Une serie corrigee est valide si ses valeurs sont dans les bornes ET
    /// si elle mesure quelque chose : des repetitions, une duree ou une
    /// distance. Une serie vide n'est pas une serie.
    public static func isValidSet(
        weightKilograms: Double,
        reps: Int,
        durationSeconds: Int?,
        distanceMeters: Double?
    ) -> Bool {
        guard weightKilograms.isFinite, weightRange.contains(weightKilograms),
              repsRange.contains(reps) else { return false }
        if let durationSeconds, !SetMeasure.durationRange.contains(durationSeconds) { return false }
        if let distanceMeters {
            guard distanceMeters.isFinite, SetMeasure.distanceRange.contains(distanceMeters) else { return false }
        }
        return reps > 0 || durationSeconds != nil || distanceMeters != nil
    }
}
