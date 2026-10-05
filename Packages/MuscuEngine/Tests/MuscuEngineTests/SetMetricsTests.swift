import Testing
@testable import MuscuEngine

@Suite
struct SetMetricsTests {
    @Test
    func testExternalLoadUsesWeightDirectly() {
        let input = SetMetricsInput(weightKilograms: 100, reps: 5, loadKind: .external)
        #expect(SetMetrics.effectiveLoad(input) == 100)
        #expect(SetMetrics.tonnage(input) == 500)
    }

    // Sans poids de corps connu, la charge deplacee est inconnue : les vues
    // doivent afficher "donnee manquante", jamais zero.
    @Test
    func testBodyweightNeedsBodyweightValue() {
        let unknown = SetMetricsInput(weightKilograms: 0, reps: 10, loadKind: .bodyweight)
        #expect(SetMetrics.effectiveLoad(unknown) == nil)
        #expect(SetMetrics.tonnage(unknown) == nil)

        let known = SetMetricsInput(weightKilograms: 0, reps: 10, loadKind: .bodyweight, bodyweightKilograms: 75)
        #expect(SetMetrics.effectiveLoad(known) == 75)
        #expect(SetMetrics.tonnage(known) == 750)
    }

    @Test
    func testWeightedAddsBodyweightButProgressionUsesBeltLoadOnly() {
        let input = SetMetricsInput(weightKilograms: 20, reps: 6, loadKind: .weighted, bodyweightKilograms: 80)
        #expect(SetMetrics.effectiveLoad(input) == 100)
        #expect(SetMetrics.progressionLoad(input) == 20)
    }

    @Test
    func testAssistedSubtractsAssistanceAndNeverProducesLoadRecord() {
        let input = SetMetricsInput(weightKilograms: 30, reps: 8, loadKind: .assisted, bodyweightKilograms: 80)
        #expect(SetMetrics.effectiveLoad(input) == 50)
        #expect(SetMetrics.isEligibleForOneRepMax(input) == false)
        #expect(SetMetrics.estimatedOneRepMax(input) == nil)
    }

    // Huit tractions avec 30 kg d'aide ne doivent jamais ecraser un record
    // de tractions strictes : le record assiste porte une configuration.
    @Test
    func testAssistedSetNeedsConfigurationToHoldARepsRecord() {
        let assisted = SetMetricsInput(weightKilograms: 30, reps: 8, loadKind: .assisted, bodyweightKilograms: 80)
        #expect(SetMetrics.allowsRepetitionRecord(assisted) == false)
        #expect(SetMetrics.recordConfigurationKey(assisted) == "assisted:30.0")

        let strict = SetMetricsInput(weightKilograms: 0, reps: 8, loadKind: .bodyweight, bodyweightKilograms: 80)
        #expect(SetMetrics.allowsRepetitionRecord(strict))
        #expect(SetMetrics.recordConfigurationKey(strict) == "")
    }

    // Les series enregistrees avant le typage explicite ne portent que leur
    // charge : une charge nulle se lit comme du poids de corps.
    @Test
    func testLegacyUntypedSetsKeepTheirRecords() {
        let legacyBodyweight = SetMetricsInput(weightKilograms: 0, reps: 25, loadKind: .unknown)
        #expect(SetMetrics.allowsRepetitionRecord(legacyBodyweight))
        #expect(SetMetrics.allowsLoadRecord(legacyBodyweight) == false)

        let legacyLoaded = SetMetricsInput(weightKilograms: 60, reps: 5, loadKind: .unknown)
        #expect(SetMetrics.allowsRepetitionRecord(legacyLoaded) == false)
        #expect(SetMetrics.allowsLoadRecord(legacyLoaded))
        #expect(SetMetrics.isEligibleForOneRepMax(legacyLoaded))
    }

    @Test
    func testWarmupNeverHoldsARepsRecord() {
        let warmup = SetMetricsInput(weightKilograms: 0, reps: 30, loadKind: .bodyweight, isWarmup: true)
        #expect(SetMetrics.allowsRepetitionRecord(warmup) == false)
    }

    @Test
    func testAssistanceGreaterThanBodyweightClampsToZero() {
        let input = SetMetricsInput(weightKilograms: 120, reps: 8, loadKind: .assisted, bodyweightKilograms: 80)
        #expect(SetMetrics.effectiveLoad(input) == 0)
    }

    @Test
    func testPerSideDoublesTonnage() {
        let input = SetMetricsInput(weightKilograms: 20, reps: 10, loadKind: .external, side: .perSide)
        #expect(SetMetrics.tonnage(input) == 400)
    }

    @Test(arguments: [0, 13, 20])
    func testOneRepMaxIneligibleOutsideRepRange(reps: Int) {
        let input = SetMetricsInput(weightKilograms: 100, reps: reps, loadKind: .external)
        #expect(SetMetrics.isEligibleForOneRepMax(input) == false)
    }

    @Test(arguments: Array(1...12))
    func testOneRepMaxEligibleInsideRepRange(reps: Int) {
        let input = SetMetricsInput(weightKilograms: 100, reps: reps, loadKind: .external)
        #expect(SetMetrics.isEligibleForOneRepMax(input))
    }

    @Test
    func testWarmupSetsAreNeverEligible() {
        let input = SetMetricsInput(weightKilograms: 100, reps: 5, loadKind: .external, isWarmup: true)
        #expect(SetMetrics.isEligibleForOneRepMax(input) == false)
    }

    @Test
    func testWeightedSetIsEligibleForOneRepMaxWithBodyweight() {
        let input = SetMetricsInput(weightKilograms: 20, reps: 5, loadKind: .weighted, bodyweightKilograms: 80)
        #expect(SetMetrics.estimatedOneRepMax(input) == OneRepMax.epley(weight: 100, reps: 5))
    }

    @Test
    func testTotalTonnageSeparatesUnknownSets() {
        let inputs = [
            SetMetricsInput(weightKilograms: 100, reps: 5, loadKind: .external),
            SetMetricsInput(weightKilograms: 0, reps: 10, loadKind: .bodyweight),
            SetMetricsInput(weightKilograms: 50, reps: 5, loadKind: .external, isWarmup: true),
        ]
        let result = SetMetrics.totalTonnage(inputs)
        #expect(result.total == 500)
        #expect(result.unknownSets == 1)
    }

    @Test
    func testTimeUnderTensionPrefersMeasuredDuration() {
        let tempo = Tempo(eccentric: 3, bottomPause: 1, concentric: 1, topPause: 0)
        let timed = SetMetricsInput(weightKilograms: 0, reps: 0, loadKind: .bodyweight, durationSeconds: 45)
        #expect(SetMetrics.timeUnderTension(timed, tempo: tempo) == 45)

        let reps = SetMetricsInput(weightKilograms: 60, reps: 10, loadKind: .external)
        #expect(SetMetrics.timeUnderTension(reps, tempo: tempo) == 50)
        #expect(SetMetrics.timeUnderTension(reps, tempo: nil) == nil)
    }
}
