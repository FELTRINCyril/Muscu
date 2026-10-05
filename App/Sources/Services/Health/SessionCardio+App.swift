import Foundation
import MuscuEngine

extension CompletedSession {
    /// Au moins une valeur cardio est connue.
    var hasCardio: Bool {
        avgHeartRate != nil || maxHeartRate != nil || minHeartRate != nil || activeEnergyKcal != nil
    }

    /// Cardio de la seance tel qu'enregistre.
    var cardio: SessionCardio {
        SessionCardio(
            averageHeartRate: avgHeartRate,
            minimumHeartRate: minHeartRate,
            maximumHeartRate: maxHeartRate,
            activeEnergyKilocalories: activeEnergyKcal
        )
    }

    /// Complete le cardio sans jamais ecraser une valeur deja connue. Ces
    /// valeurs ne sont pas synchronisees (decision 0011) : `updatedAt` n'est
    /// donc pas touche.
    func apply(_ cardio: SessionCardio) {
        if avgHeartRate == nil { avgHeartRate = cardio.averageHeartRate }
        if minHeartRate == nil { minHeartRate = cardio.minimumHeartRate }
        if maxHeartRate == nil { maxHeartRate = cardio.maximumHeartRate }
        if activeEnergyKcal == nil { activeEnergyKcal = cardio.activeEnergyKilocalories }
    }
}
