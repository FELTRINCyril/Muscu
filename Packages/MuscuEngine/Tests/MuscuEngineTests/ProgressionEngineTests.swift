import Foundation
import Testing
@testable import MuscuEngine

@Suite
struct ProgressionEngineTests {
    private let reference = Date(timeIntervalSince1970: 1_750_000_000)

    private func exposure(
        daysAgo: Int,
        reps: [Int],
        weight: Double = 60,
        effort: EffortRating? = nil,
        loadKind: LoadKind = .external
    ) -> ExerciseExposure {
        ExerciseExposure(
            date: reference.addingTimeInterval(TimeInterval(-daysAgo * 86_400)),
            sets: reps.map {
                ExposureSet(weightKilograms: weight, reps: $0, effort: effort, loadKind: loadKind)
            }
        )
    }

    private func context(
        rule: ProgressionRule = .doubleProgression(incrementKilograms: 2.5, requiredSuccesses: 1),
        sets: Int = 3,
        lower: Int = 8,
        upper: Int = 12,
        weight: Double? = 60,
        loadKind: LoadKind = .external,
        targetEffort: EffortRating? = nil,
        exposures: [ExerciseExposure] = []
    ) -> ProgressionContext {
        ProgressionContext(
            rule: rule,
            prescribedSets: sets,
            repsLower: lower,
            repsUpper: upper,
            currentWeightKilograms: weight,
            availableIncrementKilograms: 2.5,
            loadKind: loadKind,
            exposures: exposures,
            targetEffort: targetEffort
        )
    }

    // MARK: - Absence de données

    // Critere de la roadmap : toute progression doit etre justifiee par des
    // performances identifiables. Sans historique, on ne propose rien.
    @Test
    func testNoHistoryProposesNothing() {
        let proposal = ProgressionEngine.propose(context())
        #expect(proposal.outcome == .notEnoughData)
        #expect(proposal.changesAnything == false)
        #expect(proposal.factors.isEmpty == false)
    }

    @Test
    func testInvalidRuleIsRefusedRatherThanGuessed() {
        let invalid = context(rule: .doubleProgression(incrementKilograms: 0, requiredSuccesses: 0))
        #expect(ProgressionEngine.propose(invalid).outcome == .notEnoughData)
    }

    @Test
    func testNoRuleHoldsWithoutProposingAnything() {
        let proposal = ProgressionEngine.propose(
            context(rule: .none, exposures: [exposure(daysAgo: 2, reps: [12, 12, 12])])
        )
        #expect(proposal.outcome == .hold)
    }

    // MARK: - Double progression

    @Test
    func testDoubleProgressionIncreasesLoadAtTopOfRange() {
        let proposal = ProgressionEngine.propose(
            context(exposures: [exposure(daysAgo: 2, reps: [12, 12, 12])])
        )
        #expect(proposal.outcome == .increaseLoad(from: 60, to: 62.5))
        #expect(proposal.factors.isEmpty == false)
    }

    @Test
    func testDoubleProgressionHoldsInsideTheRange() {
        let proposal = ProgressionEngine.propose(
            context(exposures: [exposure(daysAgo: 2, reps: [12, 11, 10])])
        )
        #expect(proposal.outcome == .hold)
    }

    // Une serie manquante compte comme un echec : trois series prescrites,
    // deux realisees, la charge ne doit pas monter.
    @Test
    func testMissingSetIsNotASuccess() {
        let proposal = ProgressionEngine.propose(
            context(exposures: [exposure(daysAgo: 2, reps: [12, 12])])
        )
        #expect(proposal.outcome == .hold)
    }

    @Test
    func testDoubleProgressionRequiresSeveralSuccessesWhenConfigured() {
        let rule = ProgressionRule.doubleProgression(incrementKilograms: 2.5, requiredSuccesses: 2)
        let one = ProgressionEngine.propose(
            context(rule: rule, exposures: [exposure(daysAgo: 2, reps: [12, 12, 12])])
        )
        #expect(one.outcome == .hold)

        let two = ProgressionEngine.propose(
            context(rule: rule, exposures: [
                exposure(daysAgo: 2, reps: [12, 12, 12]),
                exposure(daysAgo: 5, reps: [12, 12, 12]),
            ])
        )
        #expect(two.outcome == .increaseLoad(from: 60, to: 62.5))
    }

    // Trois seances consecutives sous le bas de fourchette declenchent une
    // reduction proposee, jamais un diagnostic.
    @Test
    func testRepeatedFailuresProposeAReduction() {
        let proposal = ProgressionEngine.propose(
            context(exposures: [
                exposure(daysAgo: 2, reps: [6, 5, 5]),
                exposure(daysAgo: 5, reps: [7, 6, 5]),
                exposure(daysAgo: 8, reps: [7, 7, 6]),
            ])
        )
        #expect(proposal.outcome == .reduceLoad(from: 60, to: 55))
    }

    @Test
    func testTwoFailuresAreNotEnoughToReduce() {
        let proposal = ProgressionEngine.propose(
            context(exposures: [
                exposure(daysAgo: 2, reps: [6, 5, 5]),
                exposure(daysAgo: 5, reps: [7, 6, 5]),
            ])
        )
        #expect(proposal.outcome == .hold)
    }

    // Un effort declare plus dur que la cible empeche la montee de charge,
    // meme si les repetitions sont atteintes.
    @Test
    func testEffortHarderThanTargetBlocksTheIncrease() {
        let proposal = ProgressionEngine.propose(
            context(
                targetEffort: .rir(2),
                exposures: [exposure(daysAgo: 2, reps: [12, 12, 12], effort: .rir(0))]
            )
        )
        #expect(proposal.outcome == .hold)
    }

    @Test
    func testEffortEasierThanTargetAllowsTheIncrease() {
        let proposal = ProgressionEngine.propose(
            context(
                targetEffort: .rir(2),
                exposures: [exposure(daysAgo: 2, reps: [12, 12, 12], effort: .rir(3))]
            )
        )
        #expect(proposal.outcome == .increaseLoad(from: 60, to: 62.5))
    }

    // MARK: - Autres règles

    @Test
    func testLinearLoadIncreasesOnASuccessfulSession() {
        let proposal = ProgressionEngine.propose(
            context(
                rule: .linearLoad(incrementKilograms: 5, requiredSuccesses: 1),
                exposures: [exposure(daysAgo: 2, reps: [8, 8, 8])]
            )
        )
        #expect(proposal.outcome == .increaseLoad(from: 60, to: 65))
    }

    @Test
    func testRepsProgressionRespectsItsCeiling() {
        let below = ProgressionEngine.propose(
            context(
                rule: .repsProgression(step: 2, maximumReps: 20),
                upper: 12,
                exposures: [exposure(daysAgo: 2, reps: [8, 8, 8])]
            )
        )
        #expect(below.outcome == .increaseReps(from: 12, to: 14))

        let atCeiling = ProgressionEngine.propose(
            context(
                rule: .repsProgression(step: 2, maximumReps: 12),
                upper: 12,
                exposures: [exposure(daysAgo: 2, reps: [8, 8, 8])]
            )
        )
        #expect(atCeiling.outcome == .hold)
    }

    @Test
    func testSetsProgressionRespectsItsCeiling() {
        let proposal = ProgressionEngine.propose(
            context(
                rule: .setsProgression(step: 1, maximumSets: 5),
                sets: 3,
                exposures: [exposure(daysAgo: 2, reps: [8, 8, 8])]
            )
        )
        #expect(proposal.outcome == .increaseSets(from: 3, to: 4))

        let full = ProgressionEngine.propose(
            context(
                rule: .setsProgression(step: 1, maximumSets: 3),
                sets: 3,
                exposures: [exposure(daysAgo: 2, reps: [8, 8, 8])]
            )
        )
        #expect(full.outcome == .hold)
    }

    @Test
    func testPercentProgressionNeverExceedsOneHundred() {
        let proposal = ProgressionEngine.propose(
            context(
                rule: .percentOneRepMax(percent: 99, percentStep: 5),
                exposures: [exposure(daysAgo: 2, reps: [8, 8, 8])]
            )
        )
        #expect(proposal.outcome == .increasePercent(from: 99, to: 100))
    }

    // MARK: - Cible d'effort

    @Test
    func testEffortTargetNeedsDeclaredEffort() {
        let proposal = ProgressionEngine.propose(
            context(
                rule: .effortTarget(targetRepsInReserve: 2, incrementKilograms: 2.5),
                exposures: [exposure(daysAgo: 2, reps: [8, 8, 8])]
            )
        )
        #expect(proposal.outcome == .notEnoughData)
    }

    @Test
    func testEffortTargetFollowsDeclaredRepsInReserve() {
        let tooEasy = ProgressionEngine.propose(
            context(
                rule: .effortTarget(targetRepsInReserve: 2, incrementKilograms: 2.5),
                exposures: [exposure(daysAgo: 2, reps: [8, 8, 8], effort: .rir(4))]
            )
        )
        #expect(tooEasy.outcome == .increaseLoad(from: 60, to: 62.5))

        let tooHard = ProgressionEngine.propose(
            context(
                rule: .effortTarget(targetRepsInReserve: 2, incrementKilograms: 2.5),
                exposures: [exposure(daysAgo: 2, reps: [8, 8, 8], effort: .rir(0))]
            )
        )
        #expect(tooHard.outcome == .reduceLoad(from: 60, to: 57.5))

        let onTarget = ProgressionEngine.propose(
            context(
                rule: .effortTarget(targetRepsInReserve: 2, incrementKilograms: 2.5),
                exposures: [exposure(daysAgo: 2, reps: [8, 8, 8], effort: .rir(2))]
            )
        )
        #expect(onTarget.outcome == .hold)
    }

    // MARK: - Lesté / assisté

    // Une traction ASSISTEE progresse en diminuant l'assistance.
    @Test
    func testAssistedProgressionReducesAssistance() {
        let proposal = ProgressionEngine.propose(
            context(
                rule: .assistedOrWeighted(incrementKilograms: 5, targetReps: 8),
                weight: 30,
                loadKind: .assisted,
                exposures: [exposure(daysAgo: 2, reps: [8, 8, 8], weight: 30, loadKind: .assisted)]
            )
        )
        #expect(proposal.outcome == .reduceLoad(from: 30, to: 25))
    }

    @Test
    func testWeightedProgressionAddsBeltLoad() {
        let proposal = ProgressionEngine.propose(
            context(
                rule: .assistedOrWeighted(incrementKilograms: 2.5, targetReps: 8),
                weight: 10,
                loadKind: .weighted,
                exposures: [exposure(daysAgo: 2, reps: [8, 8, 8], weight: 10, loadKind: .weighted)]
            )
        )
        #expect(proposal.outcome == .increaseLoad(from: 10, to: 12.5))
    }

    @Test
    func testAssistanceNeverGoesBelowZero() {
        let proposal = ProgressionEngine.propose(
            context(
                rule: .assistedOrWeighted(incrementKilograms: 5, targetReps: 8),
                weight: 2.5,
                loadKind: .assisted,
                exposures: [exposure(daysAgo: 2, reps: [10, 10, 10], weight: 2.5, loadKind: .assisted)]
            )
        )
        #expect(proposal.outcome == .reduceLoad(from: 2.5, to: 0))
    }

    // MARK: - Arrondis

    // Une proposition ne doit jamais produire une charge impossible a charger.
    @Test
    func testProposedLoadsUseAvailableIncrements() {
        var context = self.context(exposures: [exposure(daysAgo: 2, reps: [12, 12, 12], weight: 61)])
        context.currentWeightKilograms = 61
        context.availableIncrementKilograms = 5
        let proposal = ProgressionEngine.propose(context)
        guard case .increaseLoad(_, let target) = proposal.outcome else {
            Issue.record("Une montée de charge était attendue")
            return
        }
        #expect(target.truncatingRemainder(dividingBy: 5) == 0)
    }

    // MARK: - Formats chronométrés

    @Test
    func testTimeProgressionProposesTheConfiguredAdjustment() {
        let proposal = ProgressionEngine.propose(
            context(
                rule: .timeProgression(workStepSeconds: 5, restStepSeconds: -5),
                exposures: [exposure(daysAgo: 2, reps: [1])]
            )
        )
        #expect(proposal.outcome == .adjustTime(workDeltaSeconds: 5, restDeltaSeconds: -5))
    }

    // MARK: - Propriétés

    /// Propriete : quelle que soit la regle et l'historique, une proposition
    /// porte TOUJOURS au moins un facteur explicatif.
    @Test(arguments: [
        ProgressionRule.doubleProgression(incrementKilograms: 2.5, requiredSuccesses: 1),
        .linearLoad(incrementKilograms: 5, requiredSuccesses: 1),
        .repsProgression(step: 1, maximumReps: 15),
        .setsProgression(step: 1, maximumSets: 5),
        .percentOneRepMax(percent: 75, percentStep: 2.5),
        .effortTarget(targetRepsInReserve: 2, incrementKilograms: 2.5),
        .assistedOrWeighted(incrementKilograms: 2.5, targetReps: 8),
        .timeProgression(workStepSeconds: 5, restStepSeconds: 0),
        .none,
    ])
    func testEveryProposalIsExplained(rule: ProgressionRule) {
        for reps in [[12, 12, 12], [8, 8, 8], [5, 4, 3], []] {
            let proposal = ProgressionEngine.propose(
                context(rule: rule, exposures: reps.isEmpty ? [] : [exposure(daysAgo: 2, reps: reps, effort: .rir(2))])
            )
            #expect(proposal.factors.isEmpty == false, "\(rule) sans facteur explicatif")
        }
    }

    /// Propriete : une montee de charge n'est jamais proposee quand la
    /// derniere seance n'a pas atteint le bas de la fourchette.
    @Test
    func testLoadNeverIncreasesAfterAFailedSession() {
        for rule in [
            ProgressionRule.doubleProgression(incrementKilograms: 2.5, requiredSuccesses: 1),
            .linearLoad(incrementKilograms: 5, requiredSuccesses: 1),
        ] {
            let proposal = ProgressionEngine.propose(
                context(rule: rule, exposures: [exposure(daysAgo: 2, reps: [7, 6, 5])])
            )
            if case .increaseLoad = proposal.outcome {
                Issue.record("\(rule) a proposé une montée après une séance ratée")
            }
        }
    }

    /// Propriete : le meme contexte donne toujours la meme proposition.
    @Test
    func testProposalsAreDeterministic() {
        let sample = context(exposures: [exposure(daysAgo: 2, reps: [12, 12, 12], effort: .rir(2))])
        let first = ProgressionEngine.propose(sample)
        for _ in 0..<20 {
            #expect(ProgressionEngine.propose(sample) == first)
        }
    }
}
