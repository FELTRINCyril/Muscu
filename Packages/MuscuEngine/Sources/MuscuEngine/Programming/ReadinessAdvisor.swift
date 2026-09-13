import Foundation

/// Check-in de forme avant une seance. Toutes les valeurs sont facultatives :
/// un check-in partiel reste exploitable.
public struct ReadinessCheckIn: Equatable, Sendable {
    /// Echelles 1...5 (1 = tres bas, 5 = tres bon).
    public var energy: Int?
    public var sleepQuality: Int?
    /// 1 = aucune courbature, 5 = courbatures importantes.
    public var soreness: Int?
    /// 1 = serein, 5 = tres stresse.
    public var stress: Int?
    /// 0...10, avec la zone concernee.
    public var painIntensity: Int?
    public var painArea: String

    public init(
        energy: Int? = nil,
        sleepQuality: Int? = nil,
        soreness: Int? = nil,
        stress: Int? = nil,
        painIntensity: Int? = nil,
        painArea: String = ""
    ) {
        self.energy = energy
        self.sleepQuality = sleepQuality
        self.soreness = soreness
        self.stress = stress
        self.painIntensity = painIntensity
        self.painArea = painArea
    }

    public var hasAnyValue: Bool {
        energy != nil || sleepQuality != nil || soreness != nil || stress != nil || painIntensity != nil
    }
}

/// Ce que le moteur local propose. Une suggestion n'est jamais appliquee
/// d'office : elle est affichee, expliquee, et reste modifiable.
public enum ReadinessAdjustment: Equatable, Sendable {
    case keepAsPlanned
    /// Reduire le volume : multiplicateur applique au nombre de series.
    case reduceVolume(multiplier: Double)
    /// Reduire la charge : multiplicateur applique aux charges de travail.
    case reduceLoad(multiplier: Double)
    /// Proposer de remplacer les exercices sollicitant une zone donnee.
    case suggestSubstitution(area: String)
    /// Proposer du repos.
    case suggestRest
}

public struct ReadinessAdvice: Equatable, Sendable {
    public var adjustment: ReadinessAdjustment
    /// Facteurs pris en compte, affichables tels quels.
    public var factors: [String]
    /// Message prudent affiche en cas de douleur. Jamais un diagnostic,
    /// jamais une prescription : une invitation a consulter.
    public var cautionMessage: String?

    public init(adjustment: ReadinessAdjustment, factors: [String], cautionMessage: String? = nil) {
        self.adjustment = adjustment
        self.factors = factors
        self.cautionMessage = cautionMessage
    }
}

/// Traduit un check-in en suggestion d'adaptation.
///
/// Limites assumees et non negociables :
/// - aucune interpretation medicale, aucun diagnostic, aucun traitement ;
/// - une douleur declenche un message prudent invitant a consulter un
///   professionnel, jamais une prescription ;
/// - toute suggestion est explicable par les valeurs saisies.
public enum ReadinessAdvisor {
    /// Au-dela de ce niveau, une douleur declenche systematiquement le
    /// message prudent, quelle que soit la suggestion d'entrainement.
    public static let painCautionThreshold = 4

    /// Au-dela de ce niveau, la seance n'est plus proposee telle quelle.
    public static let painRestThreshold = 7

    public static func advise(_ checkIn: ReadinessCheckIn) -> ReadinessAdvice {
        guard checkIn.hasAnyValue else {
            return ReadinessAdvice(
                adjustment: .keepAsPlanned,
                factors: ["Aucune information de forme saisie : la séance reste inchangée."]
            )
        }

        var factors: [String] = []
        if let energy = checkIn.energy { factors.append("Énergie \(clamped(energy))/5.") }
        if let sleep = checkIn.sleepQuality { factors.append("Sommeil perçu \(clamped(sleep))/5.") }
        if let soreness = checkIn.soreness { factors.append("Courbatures \(clamped(soreness))/5.") }
        if let stress = checkIn.stress { factors.append("Stress \(clamped(stress))/5.") }
        if let pain = checkIn.painIntensity {
            if pain <= 0 {
                factors.append("Aucune douleur déclarée.")
            } else {
                let area = checkIn.painArea.trimmingCharacters(in: .whitespacesAndNewlines)
                factors.append(area.isEmpty ? "Douleur déclarée \(pain)/10." : "Douleur déclarée \(pain)/10 (\(area)).")
            }
        }
        // Un check-in renseigne doit toujours produire au moins un facteur :
        // une suggestion sans justification serait inexplicable.
        if factors.isEmpty {
            factors.append("Check-in enregistré sans valeur exploitable : la séance reste inchangée.")
        }

        let caution = cautionMessage(for: checkIn)

        // 1. Une douleur forte prime sur tout le reste.
        if let pain = checkIn.painIntensity, pain >= painRestThreshold {
            return ReadinessAdvice(adjustment: .suggestRest, factors: factors, cautionMessage: caution)
        }

        // 2. Une douleur localisee moderee : proposer de contourner la zone.
        if let pain = checkIn.painIntensity,
           pain >= painCautionThreshold,
           !checkIn.painArea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ReadinessAdvice(
                adjustment: .suggestSubstitution(area: checkIn.painArea),
                factors: factors,
                cautionMessage: caution
            )
        }

        // 3. Fatigue generale : score simple et explicable.
        let score = fatigueScore(checkIn)
        switch score {
        case 4...:
            return ReadinessAdvice(adjustment: .suggestRest, factors: factors, cautionMessage: caution)
        case 3:
            return ReadinessAdvice(adjustment: .reduceVolume(multiplier: 0.6), factors: factors, cautionMessage: caution)
        case 2:
            return ReadinessAdvice(adjustment: .reduceLoad(multiplier: 0.9), factors: factors, cautionMessage: caution)
        default:
            return ReadinessAdvice(adjustment: .keepAsPlanned, factors: factors, cautionMessage: caution)
        }
    }

    /// Score de fatigue : un point par signal defavorable. Volontairement
    /// simple pour rester explicable ligne par ligne a l'utilisateur.
    public static func fatigueScore(_ checkIn: ReadinessCheckIn) -> Int {
        var score = 0
        if let energy = checkIn.energy, clamped(energy) <= 2 { score += 1 }
        if let sleep = checkIn.sleepQuality, clamped(sleep) <= 2 { score += 1 }
        if let soreness = checkIn.soreness, clamped(soreness) >= 4 { score += 1 }
        if let stress = checkIn.stress, clamped(stress) >= 4 { score += 1 }
        if let energy = checkIn.energy, clamped(energy) == 1 { score += 1 }
        return score
    }

    /// Message prudent, non medical. Present des qu'une douleur notable est
    /// declaree, meme si la seance reste proposee telle quelle.
    public static func cautionMessage(for checkIn: ReadinessCheckIn) -> String? {
        guard let pain = checkIn.painIntensity, pain >= painCautionThreshold else { return nil }
        return "Une douleur inhabituelle mérite l'avis d'un professionnel de santé. Muscu ne pose aucun diagnostic et ne remplace pas une consultation."
    }

    private static func clamped(_ value: Int) -> Int {
        min(max(value, 1), 5)
    }
}
