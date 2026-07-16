import Testing
@testable import MuscuEngine

@Suite
struct AdaptiveRestTests {
    @Test
    func testSameRepsMoreRestForLowerMax() {
        // serie de 5 : plus dure pour un max a 8 que pour un max a 15
        let hard = Pyramid.adaptiveRest(repsDone: 5, maxReps: 8)
        let easy = Pyramid.adaptiveRest(repsDone: 5, maxReps: 15)
        #expect(hard > easy)
    }

    @Test
    func testKnownValues() {
        // intensite 5/8 = 0.625 -> 30 + 0.625^1.5 * 150 = 104.1 -> 105
        #expect(Pyramid.adaptiveRest(repsDone: 5, maxReps: 8) == 105)
        // intensite 5/15 = 0.333 -> 30 + 0.333^1.5 * 150 = 58.8 -> 60
        #expect(Pyramid.adaptiveRest(repsDone: 5, maxReps: 15) == 60)
    }

    @Test
    func testMaxEffortGivesMaxRest() {
        #expect(Pyramid.adaptiveRest(repsDone: 10, maxReps: 10) == 180)
    }

    @Test
    func testIntensityCappedAtOne() {
        #expect(Pyramid.adaptiveRest(repsDone: 14, maxReps: 10) == 180)
    }

    @Test
    func testInvalidMaxFallsBackToMin() {
        #expect(Pyramid.adaptiveRest(repsDone: 5, maxReps: 0) == 30)
    }
}
