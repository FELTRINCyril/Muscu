import Testing
@testable import MuscuEngine

@Suite
struct OneRepMaxTests {
    @Test
    func testEpleySingleRepIsWeightItself() {
        #expect(OneRepMax.epley(weight: 100, reps: 1) == 100)
    }

    @Test
    func testEpleyFiveRepsAtNinety() {
        // 90 * (1 + 5/30) = 105
        let result = OneRepMax.epley(weight: 90, reps: 5)
        #expect(abs(result - 105) < 0.01)
    }

    @Test
    func testEpleyZeroRepsIsZero() {
        #expect(OneRepMax.epley(weight: 90, reps: 0) == 0)
    }

    @Test
    func testWorkingLoadRoundsDownToPlate() {
        // 100 * 0.75 = 75 -> 75 ; 103 * 0.75 = 77.25 -> 77.5 est trop haut -> 75.0? non: floor(77.25/2.5)*2.5 = 75.0
        #expect(OneRepMax.workingLoad(oneRepMax: 100, percent: 75) == 75)
        #expect(OneRepMax.workingLoad(oneRepMax: 103, percent: 75) == 75)
        #expect(OneRepMax.workingLoad(oneRepMax: 104, percent: 75) == 77.5)
    }
}
