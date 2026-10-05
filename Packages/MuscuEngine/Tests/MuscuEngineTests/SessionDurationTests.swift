import Foundation
import Testing
@testable import MuscuEngine

@Suite
struct SessionDurationTests {
    private func classic(sets: Int, rest: Int) -> WorkoutExercisePlan {
        WorkoutExercisePlan(
            exerciseId: "bench",
            displayName: "Développé",
            format: .classic,
            setCount: sets,
            restSeconds: rest
        )
    }

    @Test
    func testClassicExerciseCountsWorkAndInternalRestOnly() {
        // 4 series : 4 x 45 s de travail + 3 repos de 120 s.
        #expect(SessionDuration.estimatedSeconds(for: classic(sets: 4, rest: 120)) == 4 * 45 + 3 * 120)
    }

    @Test
    func testWarmupIsCountedOncePerSession() {
        let plan = WorkoutPlan(nodes: [.single(classic(sets: 1, rest: 0)), .single(classic(sets: 1, rest: 0))])
        let withWarmup = SessionDuration.estimatedSeconds(for: plan)
        let withoutWarmup = SessionDuration.estimatedSeconds(for: plan, includingWarmup: false)
        #expect(withWarmup - withoutWarmup == SessionDuration.warmupSeconds)
    }

    // Dans un superset, le travail compte une fois PAR TOUR : estimer
    // `setCount` series par exercice doublerait la duree.
    @Test
    func testGroupCountsWorkPerRoundNotPerSetCount() {
        let node = WorkoutNode(
            kind: .superset,
            exercises: [classic(sets: 4, rest: 120), classic(sets: 4, rest: 120)],
            rounds: 3,
            restBetweenExercisesSeconds: 15,
            restBetweenRoundsSeconds: 90
        )
        let expected = 3 * (2 * (45 + 15)) + 2 * 90
        #expect(SessionDuration.estimatedSeconds(for: node) == expected)
    }

    @Test
    func testTimedFormatsUseTheirOwnDuration() {
        var amrap = classic(sets: 1, rest: 0)
        amrap.format = .amrap
        amrap.amrapSeconds = 600
        #expect(SessionDuration.estimatedSeconds(for: amrap) == 600)

        var emom = classic(sets: 1, rest: 0)
        emom.format = .emom
        emom.intervalWorkSeconds = 60
        emom.intervalRounds = 10
        #expect(SessionDuration.estimatedSeconds(for: emom) == 600)

        var forTime = classic(sets: 1, rest: 0)
        forTime.format = .forTime
        forTime.capSeconds = 900
        #expect(SessionDuration.estimatedSeconds(for: forTime) == 900)
    }

    @Test
    func testDropsetAddsItsDropsToTheEstimate() {
        var dropset = classic(sets: 2, rest: 90)
        dropset.format = .dropset
        dropset.dropset = DropsetPlan(drops: [20, 20], usesPercent: true, restSeconds: 10)
        let perSet = 45 + 2 * (30 + 10)
        #expect(SessionDuration.estimatedSeconds(for: dropset) == 2 * perSet + 90)
    }

    @Test
    func testRoundedMinutesNeverGoesBelowFive() {
        #expect(SessionDuration.roundedMinutes(0) == 5)
        #expect(SessionDuration.roundedMinutes(60) == 5)
        #expect(SessionDuration.roundedMinutes(46 * 60) == 45)
        #expect(SessionDuration.roundedMinutes(48 * 60) == 50)
    }

    @Test
    func testEmptyPlanIsFiveMinutes() {
        #expect(SessionDuration.estimatedMinutes(for: WorkoutPlan(nodes: [])) == 5)
    }
}
