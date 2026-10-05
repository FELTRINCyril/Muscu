import Foundation
import Testing
@testable import MuscuEngine

@Suite
struct ReadinessAdvisorTests {
    @Test
    func testEmptyCheckInKeepsTheSessionUnchanged() {
        let advice = ReadinessAdvisor.advise(ReadinessCheckIn())
        #expect(advice.adjustment == .keepAsPlanned)
        #expect(advice.cautionMessage == nil)
        #expect(advice.factors.isEmpty == false)
    }

    @Test
    func testGoodFormKeepsTheSessionUnchanged() {
        let advice = ReadinessAdvisor.advise(
            ReadinessCheckIn(energy: 5, sleepQuality: 4, soreness: 1, stress: 1)
        )
        #expect(advice.adjustment == .keepAsPlanned)
    }

    @Test
    func testModerateFatigueReducesLoad() {
        let advice = ReadinessAdvisor.advise(
            ReadinessCheckIn(energy: 2, sleepQuality: 2, soreness: 2, stress: 2)
        )
        guard case .reduceLoad(let multiplier) = advice.adjustment else {
            Issue.record("Une réduction de charge était attendue, reçu \(advice.adjustment)")
            return
        }
        #expect(multiplier < 1)
    }

    @Test
    func testHeavyFatigueReducesVolume() {
        let advice = ReadinessAdvisor.advise(
            ReadinessCheckIn(energy: 2, sleepQuality: 2, soreness: 4, stress: 2)
        )
        guard case .reduceVolume(let multiplier) = advice.adjustment else {
            Issue.record("Une réduction de volume était attendue, reçu \(advice.adjustment)")
            return
        }
        #expect(multiplier < 1)
    }

    @Test
    func testExhaustionSuggestsRest() {
        let advice = ReadinessAdvisor.advise(
            ReadinessCheckIn(energy: 1, sleepQuality: 1, soreness: 5, stress: 5)
        )
        #expect(advice.adjustment == .suggestRest)
    }

    // MARK: - Douleur

    // Critere non negociable : une douleur ne produit jamais un diagnostic ni
    // une prescription, seulement un message prudent.
    @Test
    func testPainAlwaysProducesACautiousMessageNeverADiagnosis() {
        let advice = ReadinessAdvisor.advise(ReadinessCheckIn(painIntensity: 5, painArea: "épaule"))
        let message = advice.cautionMessage
        #expect(message != nil)
        #expect(message?.contains("professionnel de santé") == true)
        #expect(message?.contains("aucun diagnostic") == true)
    }

    @Test
    func testLowPainDoesNotTriggerTheCaution() {
        let advice = ReadinessAdvisor.advise(ReadinessCheckIn(painIntensity: 2, painArea: "genou"))
        #expect(advice.cautionMessage == nil)
        #expect(advice.adjustment == .keepAsPlanned)
    }

    @Test
    func testLocalisedPainSuggestsASubstitution() {
        let advice = ReadinessAdvisor.advise(ReadinessCheckIn(painIntensity: 5, painArea: "épaule"))
        #expect(advice.adjustment == .suggestSubstitution(area: "épaule"))
    }

    @Test
    func testPainWithoutAreaFallsBackOnGeneralAdvice() {
        let advice = ReadinessAdvisor.advise(ReadinessCheckIn(energy: 4, painIntensity: 5, painArea: "   "))
        #expect(advice.adjustment == .keepAsPlanned)
        #expect(advice.cautionMessage != nil)
    }

    @Test
    func testSeverePainSuggestsRestWhateverTheRest() {
        let advice = ReadinessAdvisor.advise(
            ReadinessCheckIn(energy: 5, sleepQuality: 5, soreness: 1, stress: 1, painIntensity: 9, painArea: "dos")
        )
        #expect(advice.adjustment == .suggestRest)
        #expect(advice.cautionMessage != nil)
    }

    // MARK: - Propriétés

    /// Propriete : toute suggestion est justifiee par au moins un facteur
    /// reprenant une valeur saisie.
    @Test
    func testEveryAdviceIsExplained() {
        for energy in [nil, 1, 3, 5] {
            for pain in [nil, 0, 5, 9] {
                let advice = ReadinessAdvisor.advise(
                    ReadinessCheckIn(energy: energy, painIntensity: pain, painArea: "genou")
                )
                #expect(advice.factors.isEmpty == false, "énergie=\(String(describing: energy)) douleur=\(String(describing: pain))")
            }
        }
    }

    /// Propriete : des valeurs hors echelle ne font jamais planter et sont
    /// ramenees dans les bornes.
    @Test
    func testOutOfRangeValuesAreClampedNotTrusted() {
        let advice = ReadinessAdvisor.advise(
            ReadinessCheckIn(energy: 99, sleepQuality: -5, soreness: 42, stress: 0)
        )
        #expect(advice.factors.contains { $0.contains("5/5") })
        #expect(advice.factors.contains { $0.contains("1/5") })
    }

    /// Propriete : le meme check-in donne toujours le meme conseil.
    @Test
    func testAdviceIsDeterministic() {
        let checkIn = ReadinessCheckIn(energy: 2, sleepQuality: 2, soreness: 4, stress: 3, painIntensity: 3, painArea: "genou")
        let reference = ReadinessAdvisor.advise(checkIn)
        for _ in 0..<10 {
            #expect(ReadinessAdvisor.advise(checkIn) == reference)
        }
    }
}

@Suite
struct PlateauDetectorTests {
    private let reference = Date(timeIntervalSince1970: 1_750_000_000)

    private func exposure(weeksAgo: Int, weight: Double, reps: Int = 5) -> ExerciseExposure {
        ExerciseExposure(
            date: reference.addingTimeInterval(TimeInterval(-weeksAgo * 7 * 86_400)),
            sets: [ExposureSet(weightKilograms: weight, reps: reps, loadKind: .external)]
        )
    }

    @Test
    func testTooFewExposuresIsNeverAPlateau() {
        let finding = PlateauDetector.detect(exposures: [exposure(weeksAgo: 0, weight: 100)])
        #expect(finding.isPlateau == false)
        #expect(finding.windowSize == 1)
        #expect(finding.factors.isEmpty == false)
    }

    @Test
    func testStagnantLoadsAreDetected() {
        let finding = PlateauDetector.detect(exposures: [
            exposure(weeksAgo: 0, weight: 100),
            exposure(weeksAgo: 1, weight: 100),
            exposure(weeksAgo: 2, weight: 100),
        ])
        #expect(finding.isPlateau)
        #expect(finding.relativeChange == 0)
    }

    @Test
    func testRealProgressIsNotAPlateau() {
        let finding = PlateauDetector.detect(exposures: [
            exposure(weeksAgo: 0, weight: 110),
            exposure(weeksAgo: 1, weight: 105),
            exposure(weeksAgo: 2, weight: 100),
        ])
        #expect(finding.isPlateau == false)
        #expect(finding.relativeChange > 0)
    }

    // Une regression est aussi une stagnation au sens de la detection : il
    // n'y a plus de progres mesurable.
    @Test
    func testRegressionCountsAsNoProgress() {
        let finding = PlateauDetector.detect(exposures: [
            exposure(weeksAgo: 0, weight: 95),
            exposure(weeksAgo: 1, weight: 100),
            exposure(weeksAgo: 2, weight: 100),
        ])
        #expect(finding.isPlateau)
        #expect(finding.relativeChange < 0)
    }

    // La fenetre et le seuil doivent etre visibles : l'utilisateur doit
    // pouvoir comprendre sur quoi repose la detection.
    @Test
    func testFindingAlwaysExposesItsWindowAndThreshold() {
        let finding = PlateauDetector.detect(
            exposures: (0..<4).map { exposure(weeksAgo: $0, weight: 100) },
            window: 4,
            threshold: 0.05
        )
        #expect(finding.windowSize == 4)
        #expect(finding.factors.contains { $0.contains("4 séances") })
        #expect(finding.factors.contains { $0.contains("5 %") })
    }

    @Test
    func testBodyweightExercisesCompareRepetitions() {
        let exposures = (0..<3).map { index in
            ExerciseExposure(
                date: reference.addingTimeInterval(TimeInterval(-index * 7 * 86_400)),
                sets: [ExposureSet(weightKilograms: 0, reps: 12, loadKind: .bodyweight)]
            )
        }
        let finding = PlateauDetector.detect(exposures: exposures)
        #expect(finding.isPlateau)
    }
}
