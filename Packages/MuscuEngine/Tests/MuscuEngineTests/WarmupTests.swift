import Testing
@testable import MuscuEngine

@Suite
struct WarmupTests {
    @Test
    func testRampForHundredKilos() {
        let sets = Warmup.rampSets(workingWeight: 100)
        #expect(sets.map(\.weight) == [40, 60, 80])
        #expect(sets.map(\.reps) == [8, 5, 2])
    }

    @Test
    func testRampRoundsToPlate() {
        // 85 kg -> 34/51/68 bruts -> arrondis bas : 32.5 / 50 / 67.5
        #expect(Warmup.rampSets(workingWeight: 85).map(\.weight) == [32.5, 50, 67.5])
    }

    @Test
    func testLightWeightSkipsRamp() {
        // Sous 30 kg la montee en charge n'a pas d'interet (barre a vide ~20 kg)
        #expect(Warmup.rampSets(workingWeight: 25).isEmpty)
    }
}
