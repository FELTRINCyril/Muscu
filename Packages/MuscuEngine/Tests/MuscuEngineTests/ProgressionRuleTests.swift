import Foundation
import Testing
@testable import MuscuEngine

@Suite
struct ProgressionRuleTests {
    @Test
    func testDefaultRuleIsValid() {
        #expect(ProgressionRule.default.isValid)
        #expect(ProgressionRule.default.incrementKilograms == 2.5)
    }

    @Test(arguments: [
        ProgressionRule.doubleProgression(incrementKilograms: 0, requiredSuccesses: 1),
        ProgressionRule.doubleProgression(incrementKilograms: 2.5, requiredSuccesses: 0),
        ProgressionRule.percentOneRepMax(percent: 5, percentStep: 1),
        ProgressionRule.repsProgression(step: 0, maximumReps: 10),
        ProgressionRule.timeProgression(workStepSeconds: 0, restStepSeconds: 0),
        ProgressionRule.effortTarget(targetRepsInReserve: 11, incrementKilograms: 2.5),
        ProgressionRule.setsProgression(step: 1, maximumSets: 0),
        ProgressionRule.assistedOrWeighted(incrementKilograms: 2.5, targetReps: 0),
    ])
    func testInvalidThresholdsAreRejected(rule: ProgressionRule) {
        #expect(rule.isValid == false)
    }

    @Test(arguments: [
        ProgressionRule.linearLoad(incrementKilograms: 5, requiredSuccesses: 1),
        ProgressionRule.repsProgression(step: 1, maximumReps: 12),
        ProgressionRule.setsProgression(step: 1, maximumSets: 5),
        ProgressionRule.percentOneRepMax(percent: 75, percentStep: 2.5),
        ProgressionRule.effortTarget(targetRepsInReserve: 2, incrementKilograms: 2.5),
        ProgressionRule.assistedOrWeighted(incrementKilograms: 2.5, targetReps: 8),
        ProgressionRule.timeProgression(workStepSeconds: 5, restStepSeconds: -5),
        ProgressionRule.none,
    ])
    func testValidRules(rule: ProgressionRule) {
        #expect(rule.isValid)
    }

    @Test
    func testCodableRoundTrip() throws {
        let rules: [ProgressionRule] = [
            .doubleProgression(incrementKilograms: 2.5, requiredSuccesses: 1),
            .percentOneRepMax(percent: 80, percentStep: 2.5),
            .none,
        ]
        let data = try JSONEncoder().encode(rules)
        #expect(try JSONDecoder().decode([ProgressionRule].self, from: data) == rules)
    }
}
