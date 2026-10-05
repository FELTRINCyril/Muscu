import Foundation
import Testing
@testable import MuscuEngine

/// Rejeu de `ProgressionEngine` sur plusieurs semaines d'un athlete simule.
/// Ces tests ne valident pas une decision isolee (c'est le role de
/// `ProgressionEngineTests`) mais le COMPORTEMENT dans la duree : aucune
/// hausse dangereuse, aucune hausse apres un echec, decharge respectee.
@Suite("Rejeu de la progression")
struct ProgressionReplayTests {
    private let rules: [ProgressionRule] = [
        .doubleProgression(incrementKilograms: 2.5, requiredSuccesses: 1),
        .doubleProgression(incrementKilograms: 2.5, requiredSuccesses: 2),
        .linearLoad(incrementKilograms: 2.5, requiredSuccesses: 1),
    ]

    @Test("Invariants respectés pour chaque règle de charge et plusieurs athlètes")
    func invariantsHoldAcrossRulesAndAthletes() {
        for rule in rules {
            for seed in [1, 7, 42, 2026] as [UInt64] {
                let athlete = SimulatedAthlete(seed: seed)
                let scenario = ProgressionReplayScenario(
                    rule: rule,
                    repsLower: rule == rules[2] ? 5 : 8,
                    repsUpper: rule == rules[2] ? 5 : 12
                )
                let report = ProgressionReplay.run(scenario, athlete: athlete)
                let violations = ProgressionReplay.violations(in: report)
                #expect(violations.isEmpty, "\(rule), graine \(seed) : \(violations)")
                #expect(report.steps.count == scenario.weeks * scenario.sessionsPerWeek)
            }
        }
    }

    @Test("Métriques de la double progression : la charge monte, sans emballement")
    func doubleProgressionMetrics() throws {
        let report = ProgressionReplay.run(
            ProgressionReplayScenario(rule: .default, weeks: 20),
            athlete: SimulatedAthlete(seed: 42)
        )
        let start = try #require(report.startingWeight)
        let end = try #require(report.finalWeight)
        #expect(end > start, "Un athlète qui progresse voit sa charge monter")
        #expect(report.increaseCount > 0)
        // Une hausse toutes les 2 à 3 séances au plus : au-delà, la règle
        // monterait plus vite que la force réelle.
        #expect(report.increaseRate <= 0.5, "taux de hausses \(report.increaseRate)")
        #expect(report.largestRelativeIncrease <= 0.1)
    }

    @Test("Un athlète au plafond finit par décharger, puis repart")
    func plateauLeadsToDeload() {
        // Charge de départ trop lourde pour la fourchette : échecs répétés.
        let report = ProgressionReplay.run(
            ProgressionReplayScenario(rule: .default, startingWeightKilograms: 95, weeks: 6),
            athlete: SimulatedAthlete(startingOneRepMax: 100, weeklyGainFraction: 0, ceilingOneRepMax: 100, badDayEvery: 0, repetitionNoise: 0)
        )
        #expect(report.reductionCount > 0)
        #expect(ProgressionReplay.violations(in: report).isEmpty)
        let firstReduction = report.steps.firstIndex { if case .reduceLoad = $0.proposal { return true }; return false }
        #expect(firstReduction == ProgressionRule.failuresBeforeDeload - 1, "Décharge dès le 3e échec d'affilée")
    }

    @Test("Le contrôle détecte bien une trace fautive")
    func violationsAreDetected() {
        let date = Date(timeIntervalSince1970: 0)
        let failing = ProgressionReplayStep(date: date, weightKilograms: 100, reps: [5, 5, 5], reachedTarget: false, proposal: .increaseLoad(from: 100, to: 120))
        let report = ProgressionReplayReport(steps: [failing, failing, failing.with(proposal: .hold)])
        let messages = ProgressionReplay.violations(in: report).map(\.message)
        #expect(messages.contains { $0.contains("après une séance ratée") })
        #expect(messages.contains { $0.contains("hausse de 20 %") })
        #expect(messages.contains { $0.contains("sans décharge") })
    }

    @Test("Rejeu déterministe : même graine, même trace")
    func deterministic() {
        let scenario = ProgressionReplayScenario(rule: .default)
        let first = ProgressionReplay.run(scenario, athlete: SimulatedAthlete(seed: 9))
        let second = ProgressionReplay.run(scenario, athlete: SimulatedAthlete(seed: 9))
        #expect(first == second)
    }
}

private extension ProgressionReplayStep {
    func with(proposal: ProgressionOutcome) -> ProgressionReplayStep {
        var copy = self
        copy.proposal = proposal
        return copy
    }
}
