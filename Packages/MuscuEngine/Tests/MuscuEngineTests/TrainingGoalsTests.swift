import Foundation
import Testing
@testable import MuscuEngine

@Suite
struct TrainingGoalsTests {
    // Sans donnée observée, un objectif n'est pas « à 0 % » : il n'est pas
    // encore mesurable.
    @Test
    func testMissingObservationIsStatedNotZeroed() {
        let progress = GoalEvaluator.progress(
            target: .sessionsPerWeek(count: 4),
            observation: GoalObservation(current: nil)
        )
        #expect(progress.ratio == nil)
        #expect(progress.isReached == false)
        #expect(progress.statusText.contains("Pas encore de donnée"))
    }

    @Test
    func testIncreasingGoalReportsItsRatio() {
        let progress = GoalEvaluator.progress(
            target: .sessionsPerWeek(count: 4),
            observation: GoalObservation(current: 3)
        )
        #expect(progress.ratio == 0.75)
        #expect(progress.isReached == false)
    }

    @Test
    func testReachedGoalIsMarkedAndCappedAtOne() {
        let progress = GoalEvaluator.progress(
            target: .weeklySetsForMuscle(muscle: "chest", sets: 10),
            observation: GoalObservation(current: 14)
        )
        #expect(progress.isReached)
        #expect(progress.ratio == 1)
    }

    /// Un objectif en baisse se mesure depuis son point de départ : sans lui,
    /// aucun avancement n'est exprimable.
    @Test
    func testDecreasingGoalNeedsAStartingPoint() {
        let withoutStart = GoalEvaluator.progress(
            target: .bodyMeasurement(kindRaw: "waist", value: 80, direction: .decrease),
            observation: GoalObservation(current: 90)
        )
        #expect(withoutStart.ratio == nil)

        let withStart = GoalEvaluator.progress(
            target: .bodyMeasurement(kindRaw: "waist", value: 80, direction: .decrease),
            observation: GoalObservation(current: 90, startValue: 100)
        )
        #expect(withStart.ratio == 0.5)
        #expect(withStart.isReached == false)
    }

    @Test
    func testDecreasingGoalIsReachedWhenBelowTarget() {
        let progress = GoalEvaluator.progress(
            target: .bodyMeasurement(kindRaw: "bodyweight", value: 78, direction: .decrease),
            observation: GoalObservation(current: 77, startValue: 85)
        )
        #expect(progress.isReached)
    }

    /// Les formulations restent factuelles : aucun jugement, aucune
    /// injonction.
    @Test
    func testStatusTextsStayFactual() {
        let targets: [GoalTarget] = [
            .sessionsPerWeek(count: 4),
            .weeklySetsForMuscle(muscle: "chest", sets: 12),
            .exerciseOneRepMax(exerciseId: "bench", kilograms: 100),
            .exerciseReps(exerciseId: "pullup", reps: 12),
            .bodyMeasurement(kindRaw: "bodyweight", value: 78, direction: .decrease),
        ]
        let forbidden = ["doit", "raté", "échec", "faut"]
        for target in targets {
            for current in [nil, Double(1), target.targetValue] {
                let text = GoalEvaluator.progress(
                    target: target,
                    observation: GoalObservation(current: current, startValue: 100)
                ).statusText
                #expect(text.isEmpty == false)
                for word in forbidden {
                    #expect(text.lowercased().contains(word) == false, "« \(word) » dans : \(text)")
                }
            }
        }
    }

    @Test
    func testBodyGoalsCarryACautiousMessage() {
        let message = GoalEvaluator.cautionMessage(for: .bodyMeasurement(kindRaw: "bodyweight", value: 70, direction: .decrease))
        #expect(message?.contains("professionnel de santé") == true)
        #expect(GoalEvaluator.cautionMessage(for: .sessionsPerWeek(count: 3)) == nil)
    }

    @Test
    func testSaneBoundsRejectAbsurdTargets() {
        #expect(GoalTarget.sessionsPerWeek(count: 0).isWithinSaneBounds == false)
        #expect(GoalTarget.sessionsPerWeek(count: 40).isWithinSaneBounds == false)
        #expect(GoalTarget.sessionsPerWeek(count: 4).isWithinSaneBounds)
        #expect(GoalTarget.bodyMeasurement(kindRaw: "bodyweight", value: 5, direction: .decrease).isWithinSaneBounds == false)
        #expect(GoalTarget.exerciseOneRepMax(exerciseId: "bench", kilograms: .nan).isWithinSaneBounds == false)
    }

    @Test
    func testTargetsRoundTripThroughCoding() throws {
        let targets: [GoalTarget] = [
            .sessionsPerWeek(count: 4),
            .weeklySetsForMuscle(muscle: "lats", sets: 14),
            .exerciseOneRepMax(exerciseId: "squat", kilograms: 140),
            .exerciseReps(exerciseId: "pullup", reps: 15),
            .bodyMeasurement(kindRaw: "waist", value: 82, direction: .decrease),
        ]
        let data = try JSONEncoder().encode(targets)
        #expect(try JSONDecoder().decode([GoalTarget].self, from: data) == targets)
    }
}
