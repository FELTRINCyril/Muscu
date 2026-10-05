import Foundation

/// Valeur d'un record et son origine.
public struct RecordValue: Equatable, Sendable {
    public var value: Double
    /// Seance d'origine. `nil` = inconnue (saisie manuelle, test de 1RM).
    public var sessionId: UUID?
    public var achievedAt: Date?

    public init(value: Double, sessionId: UUID? = nil, achievedAt: Date? = nil) {
        self.value = value
        self.sessionId = sessionId
        self.achievedAt = achievedAt
    }
}

/// Ce que devient un record apres la correction (ou la suppression) d'une
/// seance passee.
public enum RecordRevisionDecision: Equatable, Sendable {
    /// Le record reste tel quel.
    case keep
    /// Le record prend cette valeur (et cette origine).
    case set(RecordValue)
    /// Plus aucune seance ne justifie ce record.
    case remove
}

/// Recalcul d'un record apres correction d'une seance passee.
///
/// Deux regles, qui ensemble rendent le recalcul juste ET non regressif :
/// 1. un record qui ne vient PAS de la seance corrigee ne peut que
///    s'ameliorer — la correction ne touche jamais ce qu'une autre seance,
///    une saisie manuelle ou un test a etabli ;
/// 2. un record qui VIENT de la seance corrigee est recalcule depuis
///    l'historique : si sa serie a ete supprimee ou abaissee, il redescend
///    a la meilleure valeur encore justifiee, ou disparait si plus rien ne
///    le justifie.
///
/// `raisesFromOtherSessions` decide si ce recalcul peut aller AU-DELA de la
/// valeur courante grace a une autre seance. Faux pour les records valides
/// un par un par l'utilisateur (1RM servant au calcul des charges) : une
/// valeur qu'il avait ignoree ne doit pas reapparaitre a la faveur d'une
/// correction sans rapport.
public enum RecordRevision {
    static let tolerance = 1e-9

    public static func revise(
        current: RecordValue?,
        attributedToEditedSession: Bool,
        editedSessionBest: RecordValue?,
        otherSessionsBest: RecordValue?,
        lowerIsBetter: Bool,
        raisesFromOtherSessions: Bool = true
    ) -> RecordRevisionDecision {
        func isBetter(_ lhs: Double, than rhs: Double) -> Bool {
            lowerIsBetter ? lhs < rhs - tolerance : lhs > rhs + tolerance
        }

        guard let current else {
            // Aucun record : seule la seance corrigee peut en creer un. Les
            // autres seances avaient deja eu leur chance.
            return editedSessionBest.map { .set($0) } ?? .keep
        }

        guard attributedToEditedSession else {
            if let edited = editedSessionBest, isBetter(edited.value, than: current.value) {
                return .set(edited)
            }
            return .keep
        }

        if let edited = editedSessionBest, !isBetter(current.value, than: edited.value) {
            // La seance corrigee atteint toujours (ou depasse) le record.
            return isBetter(edited.value, than: current.value) ? .set(edited) : .keep
        }

        // La seance corrigee ne justifie plus le record : meilleure valeur
        // restante de l'historique.
        var candidates: [RecordValue] = []
        if let edited = editedSessionBest { candidates.append(edited) }
        if let other = otherSessionsBest {
            if !raisesFromOtherSessions, isBetter(other.value, than: current.value) {
                // Une autre seance justifie au moins la valeur courante : on
                // la garde, sans monter plus haut.
                return .keep
            }
            candidates.append(other)
        }
        guard var best = candidates.first else { return .remove }
        for candidate in candidates.dropFirst() where isBetter(candidate.value, than: best.value) {
            best = candidate
        }
        return abs(best.value - current.value) <= tolerance && best.sessionId == current.sessionId
            ? .keep
            : .set(best)
    }

    /// Meilleure valeur d'une liste, selon le sens du record.
    public static func best(_ values: [RecordValue], lowerIsBetter: Bool) -> RecordValue? {
        values.reduce(nil) { best, candidate in
            guard let best else { return candidate }
            let better = lowerIsBetter ? candidate.value < best.value : candidate.value > best.value
            return better ? candidate : best
        }
    }
}
