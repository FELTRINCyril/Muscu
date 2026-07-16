import Testing
@testable import MuscuEngine

@Suite
struct PyramidTests {
    @Test
    func testProposalsForMaxTen() {
        let p = Pyramid.proposals(maxReps: 10)
        #expect(p.count == 3)
        // montante-descendante : paliers 20/40/60/40/20 % du max
        #expect(p[0].reps == [2, 4, 6, 4, 2])
        // progressive : 10..50..10 %
        #expect(p[1].reps == [1, 2, 3, 4, 5, 4, 3, 2, 1])
        // descendante : 60 -> 10 %
        #expect(p[2].reps == [6, 5, 4, 3, 2, 1])
    }

    @Test
    func testProposalsScaleWithMax() {
        let p = Pyramid.proposals(maxReps: 20)
        #expect(p[0].reps == [4, 8, 12, 8, 4])
    }

    @Test
    func testNoZeroRepSteps() {
        for proposal in Pyramid.proposals(maxReps: 3) {
            #expect(!proposal.reps.contains(0))
        }
    }

    @Test
    func testTotalVolume() {
        #expect(Pyramid.proposals(maxReps: 10)[0].totalVolume == 18)
    }

    @Test
    func testInvalidMaxGivesEmpty() {
        #expect(Pyramid.proposals(maxReps: 0).isEmpty)
    }
}
