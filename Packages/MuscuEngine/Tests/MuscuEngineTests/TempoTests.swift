import Foundation
import Testing
@testable import MuscuEngine

@Suite
struct TempoTests {
    @Test
    func testNotationRoundTrip() {
        let tempo = Tempo(notation: "3-1-1-0")
        #expect(tempo?.notation == "3-1-1-0")
        #expect(tempo?.secondsPerRep == 5)
    }

    // "X" designe un mouvement explosif dans la notation usuelle : 0 seconde.
    @Test
    func testExplosivePhaseIsZeroSeconds() {
        #expect(Tempo(notation: "3-0-X-0")?.secondsPerRep == 3)
    }

    @Test(arguments: ["3-1-1", "3-1-1-0-2", "a-b-c-d", "3-1-1--1", "3-1-1-99"])
    func testInvalidNotationIsRejected(notation: String) {
        #expect(Tempo(notation: notation) == nil)
    }

    @Test
    func testZeroTempo() {
        #expect(Tempo(eccentric: 0, bottomPause: 0, concentric: 0, topPause: 0).isZero)
    }

    @Test
    func testNegativeValuesAreClamped() {
        #expect(Tempo(eccentric: -3, bottomPause: 0, concentric: 1, topPause: 0).eccentric == 0)
    }

    @Test
    func testEffortConversion() {
        #expect(EffortRating.rpe(8).repsInReserve == 2)
        #expect(EffortRating.rpe(10).repsInReserve == 0)
        #expect(EffortRating.rir(3).repsInReserve == 3)
        #expect(EffortRating.rpe(0).repsInReserve == nil)
        #expect(EffortRating.rpe(11).isValid == false)
        #expect(EffortRating.rir(-1).isValid == false)
    }

    @Test
    func testEffortDisplayText() {
        #expect(EffortRating.rpe(8).displayText == "RPE 8")
        #expect(EffortRating.rpe(8.5).displayText == "RPE 8.5")
        #expect(EffortRating.rir(2).displayText == "RIR 2")
    }

    @Test
    func testSetRoleWorkingSets() {
        #expect(SetRole.working.countsAsWorkingSet)
        #expect(SetRole.backoff.countsAsWorkingSet)
        #expect(SetRole.warmup.countsAsWorkingSet == false)
        #expect(SetRole.approach.countsAsWorkingSet == false)
    }

    @Test
    func testEffortCodableRoundTrip() throws {
        let values: [EffortRating] = [.rpe(8.5), .rir(2)]
        let data = try JSONEncoder().encode(values)
        #expect(try JSONDecoder().decode([EffortRating].self, from: data) == values)
    }
}
