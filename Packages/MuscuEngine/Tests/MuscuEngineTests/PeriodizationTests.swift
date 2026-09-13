import Foundation
import Testing
@testable import MuscuEngine

@Suite
struct PeriodizationTests {
    @Test
    func testWeekCountIsClampedToTheSupportedRange() {
        #expect(Periodization.weeks(PeriodizationInput(totalWeeks: 1)).count == Periodization.minimumWeeks)
        #expect(Periodization.weeks(PeriodizationInput(totalWeeks: 52)).count == Periodization.maximumWeeks)
        #expect(Periodization.weeks(PeriodizationInput(totalWeeks: 8)).count == 8)
    }

    @Test
    func testWeekNumbersAreContiguousAndOrdered() {
        let weeks = Periodization.weeks(PeriodizationInput(totalWeeks: 12))
        #expect(weeks.map(\.number) == Array(1...12))
    }

    // Critere de la roadmap : une decharge doit REELLEMENT reduire le volume
    // et/ou l'intensite, pas seulement porter une etiquette.
    @Test
    func testDeloadWeeksActuallyReduceVolumeAndIntensity() {
        let weeks = Periodization.weeks(PeriodizationInput(totalWeeks: 12, deloadEveryWeeks: 4))
        let deloads = weeks.filter(\.isDeload)
        #expect(deloads.isEmpty == false)
        for deload in deloads {
            #expect(deload.volumeMultiplier < 1)
            #expect(deload.intensityMultiplier <= 1)
            #expect(deload.rationale.isEmpty == false)
        }
    }

    @Test
    func testDeloadFallsOnTheConfiguredCycle() {
        let weeks = Periodization.weeks(PeriodizationInput(totalWeeks: 12, deloadEveryWeeks: 4))
        #expect(weeks.filter(\.isDeload).map(\.number) == [4, 8])
    }

    // Un plan ne se termine jamais par une semaine de decharge : le cycle
    // doit finir sur du travail reel.
    @Test
    func testPlanNeverEndsOnADeload() {
        for total in Periodization.minimumWeeks...Periodization.maximumWeeks {
            for every in [2, 3, 4, 5] {
                let weeks = Periodization.weeks(PeriodizationInput(totalWeeks: total, deloadEveryWeeks: every))
                #expect(weeks.last?.isDeload == false, "plan de \(total) semaines, décharge toutes les \(every)")
            }
        }
    }

    @Test
    func testNoDeloadWhenDisabled() {
        let weeks = Periodization.weeks(PeriodizationInput(totalWeeks: 12, deloadEveryWeeks: nil))
        #expect(weeks.contains(where: \.isDeload) == false)
    }

    @Test
    func testFlatStyleKeepsEveryWeekIdentical() {
        let weeks = Periodization.weeks(PeriodizationInput(totalWeeks: 8, style: .flat, deloadEveryWeeks: nil))
        #expect(Set(weeks.map(\.volumeMultiplier)) == [1])
        #expect(Set(weeks.map(\.intensityMultiplier)) == [1])
    }

    // Ondulation : une semaine volume, une semaine intensite.
    @Test
    func testUndulatingAlternatesVolumeAndIntensity() {
        let weeks = Periodization.weeks(PeriodizationInput(totalWeeks: 6, style: .undulating, deloadEveryWeeks: nil))
        let volumeWeeks = weeks.filter { $0.block == .accumulation }
        let intensityWeeks = weeks.filter { $0.block == .intensification }
        #expect(volumeWeeks.count == 3)
        #expect(intensityWeeks.count == 3)
        for week in volumeWeeks { #expect(week.volumeMultiplier > week.intensityMultiplier) }
        for week in intensityWeeks { #expect(week.intensityMultiplier > week.volumeMultiplier) }
    }

    // La force passe par une phase de realisation ; l'endurance non : il n'y
    // a pas de maximal a exprimer.
    @Test
    func testLinearBlocksDependOnTheGoal() {
        let strength = Periodization.plan(PeriodizationInput(totalWeeks: 12, goal: .strength))
        #expect(strength.contains { $0.kind == .realization })

        let endurance = Periodization.plan(PeriodizationInput(totalWeeks: 12, goal: .endurance))
        #expect(endurance.contains { $0.kind == .realization } == false)

        let hypertrophy = Periodization.plan(PeriodizationInput(totalWeeks: 12, goal: .hypertrophy))
        #expect(hypertrophy.contains { $0.kind == .intensification })
    }

    @Test
    func testBlocksCoverEveryWeekExactlyOnce() {
        for style in PeriodizationStyle.allCases {
            let input = PeriodizationInput(totalWeeks: 10, style: style)
            let blocks = Periodization.plan(input)
            let numbers = blocks.flatMap(\.weeks).map(\.number).sorted()
            #expect(numbers == Array(1...10), "\(style)")
            #expect(blocks.map(\.orderIndex) == Array(0..<blocks.count))
        }
    }

    @Test
    func testEveryWeekAndBlockCarriesAnExplanation() {
        for style in PeriodizationStyle.allCases {
            let blocks = Periodization.plan(PeriodizationInput(totalWeeks: 8, style: style))
            for block in blocks {
                #expect(block.rationale.isEmpty == false)
                for week in block.weeks { #expect(week.rationale.isEmpty == false) }
            }
        }
    }

    /// Propriete : le meme parametrage donne toujours le meme plan.
    @Test
    func testPlanIsDeterministic() {
        let input = PeriodizationInput(totalWeeks: 12, style: .linear, deloadEveryWeeks: 4, goal: .strength)
        let reference = Periodization.plan(input)
        for _ in 0..<10 {
            #expect(Periodization.plan(input) == reference)
        }
    }

    /// Propriete : les multiplicateurs restent dans des bornes raisonnables,
    /// jamais nuls ni absurdes.
    @Test
    func testMultipliersStayWithinSaneBounds() {
        for style in PeriodizationStyle.allCases {
            for goal in Goal.allCases {
                for total in [4, 8, 12, 16] {
                    let weeks = Periodization.weeks(
                        PeriodizationInput(totalWeeks: total, style: style, deloadEveryWeeks: 4, goal: goal)
                    )
                    for week in weeks {
                        #expect(week.volumeMultiplier > 0 && week.volumeMultiplier <= 1.5)
                        #expect(week.intensityMultiplier > 0 && week.intensityMultiplier <= 1.5)
                    }
                }
            }
        }
    }
}
