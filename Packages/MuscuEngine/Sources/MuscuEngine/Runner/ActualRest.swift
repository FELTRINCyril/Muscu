import Foundation

/// Repos REELLEMENT pris avant une serie.
///
/// Mesure entre la fin de la serie precedente de la seance (sa validation)
/// et le debut de celle-ci. Le debut d'une serie en repetitions n'est pas
/// connu : on retient sa validation, ce qui inclut le temps de travail.
/// Pour une serie chronometree, la duree saisie est retiree pour approcher
/// le vrai debut.
///
/// `nil` signifie « non mesure », jamais « zero » :
/// - premiere serie de la seance (rien avant) ;
/// - interruption longue (au-dela d'une heure, ce n'est plus un repos :
///   l'application a ete quittee, la seance reprise le lendemain...) ;
/// - horloge incoherente (validation anterieure a la serie precedente).
public enum ActualRest {
    /// Au-dela, l'ecart n'est plus un repos mais une interruption.
    public static let maximumSeconds = 3_600

    public static func seconds(
        previousSetEnd: Date?,
        validatedAt now: Date,
        currentSetDurationSeconds: Int? = nil
    ) -> Int? {
        guard let previousSetEnd else { return nil }
        let elapsed = now.timeIntervalSince(previousSetEnd)
        guard elapsed.isFinite, elapsed >= 0, elapsed <= Double(maximumSeconds) else { return nil }
        let work = Double(max(0, currentSetDurationSeconds ?? 0))
        return Int(max(0, elapsed - work).rounded())
    }
}
