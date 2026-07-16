import Testing
@testable import MuscuEngine

@Suite
struct IntervalsTests {
    @Test
    func testThirtyThirtySegments() {
        let plan = IntervalPlan.thirtyThirty(rounds: 3)
        let segs = plan.segments()
        // travail/repos alternes, pas de repos apres le dernier round
        #expect(segs.count == 5)
        #expect(segs.first?.kind == .work)
        #expect(segs.last?.kind == .work)
        #expect(segs.last?.round == 3)
        #expect(segs.allSatisfy { $0.seconds == 30 })
    }

    @Test
    func testTotalDuration() {
        #expect(IntervalPlan.thirtyThirty(rounds: 3).totalDuration == 150)
    }

    @Test
    func testTabataPreset() {
        let plan = IntervalPlan.tabata
        #expect(plan.workSeconds == 20)
        #expect(plan.restSeconds == 10)
        #expect(plan.rounds == 8)
    }

    @Test
    func testEmomPreset() {
        // EMOM 10 min : 10 rounds de 60 s de travail, 0 repos
        let plan = IntervalPlan.emom(minutes: 10)
        #expect(plan.segments().count == 10)
        #expect(plan.totalDuration == 600)
    }
}
