import Foundation
import Testing
@testable import MuscuEngine

@Suite("Valeur précédente par série")
struct PreviousPerformanceTests {
    private let sets: [HistoricalSet] = [
        HistoricalSet(weightKilograms: 40, reps: 10, isPrescribedWorkingSet: false, setIndex: 0, sequenceIndex: 0),
        HistoricalSet(weightKilograms: 80, reps: 8, setIndex: 0, sequenceIndex: 1),
        HistoricalSet(weightKilograms: 80, reps: 7, setIndex: 1, sequenceIndex: 2),
        HistoricalSet(weightKilograms: 60, reps: 6, setIndex: 1, subSetIndex: 1, sequenceIndex: 3),
        HistoricalSet(weightKilograms: 77.5, reps: 6, setIndex: 2, sequenceIndex: 4),
    ]

    @Test("Le rang ignore échauffements et paliers")
    func rankIgnoresExtras() {
        #expect(PreviousPerformance.reference(atWorkingRank: 0, in: sets)?.weightKilograms == 80)
        #expect(PreviousPerformance.reference(atWorkingRank: 1, in: sets)?.reps == 7)
        #expect(PreviousPerformance.reference(atWorkingRank: 2, in: sets)?.weightKilograms == 77.5)
    }

    @Test("Une série en plus n'a pas de référence")
    func missingRankIsNil() {
        #expect(PreviousPerformance.reference(atWorkingRank: 3, in: sets) == nil)
        #expect(PreviousPerformance.reference(atWorkingRank: -1, in: sets) == nil)
    }

    @Test("Rang dans un superset : un tour par série")
    func rankInGroups() {
        #expect(PreviousPerformance.workingRank(round: 1, setNumber: 3, totalSets: 4) == 2)
        #expect(PreviousPerformance.workingRank(round: 3, setNumber: 1, totalSets: 1) == 2)
        let superset = [
            HistoricalSet(weightKilograms: 20, reps: 12, roundIndex: 1, setIndex: 0),
            HistoricalSet(weightKilograms: 22, reps: 10, roundIndex: 0, setIndex: 0),
        ]
        #expect(PreviousPerformance.reference(atWorkingRank: 0, in: superset)?.weightKilograms == 22)
    }
}

@Suite("Bandeau des dernières séances")
struct PreviousSessionsStripTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    @Test("Séries groupées par charge consécutive")
    func runsGroupConsecutiveWeights() {
        let runs = PreviousSessionsStrip.runs(for: [
            .init(weightKilograms: 20, reps: 15),
            .init(weightKilograms: 20, reps: 9),
            .init(weightKilograms: 22.5, reps: 6),
            .init(weightKilograms: 20, reps: 8),
        ])
        #expect(runs == [
            .init(weightKilograms: 20, reps: [15, 9]),
            .init(weightKilograms: 22.5, reps: [6]),
            .init(weightKilograms: 20, reps: [8]),
        ])
    }

    @Test("Ancienneté en jours calendaires")
    func relativeAges() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        func age(_ days: Double) -> PreviousSessionsStrip.RelativeAge {
            PreviousSessionsStrip.relativeAge(of: now.addingTimeInterval(-days * 86_400), now: now, calendar: calendar)
        }
        #expect(age(0) == .today)
        #expect(age(1) == .yesterday)
        #expect(age(4) == .days(4))
        #expect(age(21) == .weeks(3))
        #expect(age(90) == .months(3))
    }

    @Test("Les dix plus récentes, de la plus ancienne à la plus récente, séances vides exclues")
    func entriesOrderAndLimit() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        var sessions = (1...12).map { index in
            PreviousSessionsStrip.SessionSets(
                id: UUID(),
                date: now.addingTimeInterval(-Double(index) * 86_400 * 3),
                sets: [.init(weightKilograms: Double(index), reps: 5)]
            )
        }
        sessions.append(.init(id: UUID(), date: now, sets: []))
        let entries = PreviousSessionsStrip.entries(from: sessions.shuffled(), now: now, calendar: calendar)
        #expect(entries.count == 10)
        #expect(entries.first?.runs.first?.weightKilograms == 10)
        #expect(entries.last?.runs.first?.weightKilograms == 1)
    }
}

@Suite("Calculateur de disques")
struct PlateMathTests {
    private let standard = PlateInventory.standard(for: .kilograms)

    @Test("Charge exacte : plus gros disques d'abord")
    func exactLoad() {
        guard case .exact(let load) = PlateMath.solve(targetKilograms: 100, inventory: standard) else {
            Issue.record("100 kg doit être chargeable")
            return
        }
        #expect(load.perSideWeight == 40)
        #expect(load.eachPlate == [25, 15])
    }

    @Test("Barre seule et charge sous la barre")
    func barOnlyAndBelowBar() {
        guard case .exact(let load) = PlateMath.solve(targetKilograms: 20, inventory: standard) else {
            Issue.record("La barre seule est chargeable")
            return
        }
        #expect(load.plates.isEmpty)
        #expect(PlateMath.solve(targetKilograms: 15, inventory: standard) == .belowBar(barWeight: 20))
    }

    @Test("Charge impossible : voisines chargeables et pas minimal")
    func roundedNeighbours() {
        guard case .rounded(let below, let above, let step) = PlateMath.solve(targetKilograms: 101, inventory: standard) else {
            Issue.record("101 kg n'est pas chargeable")
            return
        }
        #expect(below?.totalWeight == 100)
        #expect(above?.totalWeight == 102.5)
        #expect(step == 2.5)
    }

    @Test("Pas glouton : un seul 20, un 15 et un 10")
    func notGreedy() {
        let inventory = PlateInventory(unit: .kilograms, barWeight: 20, plates: [
            .init(weight: 20, pairs: 1), .init(weight: 15, pairs: 1), .init(weight: 10, pairs: 1),
        ])
        guard case .exact(let load) = PlateMath.solve(targetKilograms: 70, inventory: inventory) else {
            Issue.record("70 kg = 20 + 15 + 10 x 2 doit être chargeable")
            return
        }
        #expect(load.eachPlate == [15, 10])
    }

    @Test("Inventaire en livres : 225 lb exactement")
    func pounds() {
        let inventory = PlateInventory.standard(for: .pounds)
        let target = MassUnit.pounds.toKilograms(225)
        guard case .exact(let load) = PlateMath.solve(targetKilograms: target, inventory: inventory) else {
            Issue.record("225 lb doit être chargeable")
            return
        }
        #expect(load.eachPlate == [45, 45])
        #expect(abs(load.totalKilograms - target) < 0.000_1)
    }

    @Test("Les fractions de disque restent exactes")
    func quarterPlates() {
        guard case .exact(let load) = PlateMath.solve(targetKilograms: 22.5, inventory: standard) else {
            Issue.record("22,5 kg doit être chargeable")
            return
        }
        #expect(load.eachPlate == [1.25])
    }

    @Test("Un inventaire corrompu est assaini")
    func sanitizes() {
        let broken = PlateInventory(unit: .kilograms, barWeight: 0, plates: [
            .init(weight: -5, pairs: 2), .init(weight: .nan, pairs: 1), .init(weight: 10, pairs: 0), .init(weight: 5, pairs: 2),
        ])
        let clean = broken.sanitized()
        #expect(clean.barWeight == 20)
        #expect(clean.plates.map(\.weight) == [10, 5])
        #expect(clean.smallestStep == 10)
    }

    @Test("Aucun disque : seule la barre est chargeable")
    func noPlates() {
        let inventory = PlateInventory(unit: .kilograms, barWeight: 20, plates: [])
        guard case .rounded(let below, let above, let step) = PlateMath.solve(targetKilograms: 30, inventory: inventory) else {
            Issue.record("30 kg sans disque n'est pas chargeable")
            return
        }
        #expect(below?.totalWeight == 20)
        #expect(above == nil)
        #expect(step == 0)
    }
}

@Suite("Record célébré en direct")
struct LiveRecordTests {
    private func set(_ weight: Double, _ reps: Int, kind: LoadKind = .external, warmup: Bool = false) -> SetMetricsInput {
        SetMetricsInput(weightKilograms: weight, reps: reps, loadKind: kind, isWarmup: warmup)
    }

    @Test("Un 1RM estimé battu est célébré")
    func oneRepMax() {
        let baseline = LiveRecord.Baseline(bestEstimatedOneRepMax: 100, bestLoad: 95)
        let kind = LiveRecord.improvement(of: set(90, 5), over: baseline)
        #expect(kind == .estimatedOneRepMax(new: OneRepMax.epley(weight: 90, reps: 5), previous: 100))
    }

    @Test("Charge battue sans 1RM battu")
    func loadOnly() {
        let baseline = LiveRecord.Baseline(bestEstimatedOneRepMax: 200, bestLoad: 95)
        #expect(LiveRecord.improvement(of: set(97.5, 1), over: baseline) == .maxLoad(new: 97.5, previous: 95))
    }

    @Test("Rien sans référence, ni sur un échauffement, ni en assisté")
    func noBaselineNoParty() {
        #expect(LiveRecord.improvement(of: set(200, 5), over: .init()) == nil)
        let baseline = LiveRecord.Baseline(bestEstimatedOneRepMax: 10, bestLoad: 10)
        #expect(LiveRecord.improvement(of: set(200, 5, warmup: true), over: baseline) == nil)
        #expect(LiveRecord.improvement(of: set(30, 5, kind: .assisted), over: baseline) == nil)
    }

    @Test("Une seule célébration par exercice et par séance")
    func onlyOnce() {
        let baseline = LiveRecord.Baseline(bestEstimatedOneRepMax: 100, bestLoad: 95)
        #expect(LiveRecord.celebration(for: set(100, 3), earlierThisSession: [set(80, 5)], baseline: baseline) != nil)
        #expect(LiveRecord.celebration(for: set(105, 3), earlierThisSession: [set(100, 3)], baseline: baseline) == nil)
    }
}

@Suite("Calculateur de 1RM")
struct OneRepMaxCalculatorTests {
    @Test("Estimation par la formule du moteur, bornée par le plafond")
    func estimate() {
        #expect(OneRepMaxCalculator.estimate(weightKilograms: 100, reps: 1) == 100)
        #expect(OneRepMaxCalculator.estimate(weightKilograms: 90, reps: 5) == OneRepMax.epley(weight: 90, reps: 5))
        #expect(OneRepMaxCalculator.estimate(weightKilograms: 50, reps: 15, maximumReps: 12) == nil)
        #expect(OneRepMaxCalculator.estimate(weightKilograms: 0, reps: 5) == nil)
    }

    @Test("Tableau 95 % à 50 % arrondi au palier")
    func table() {
        let rows = OneRepMaxCalculator.table(oneRepMaxKilograms: 101, stepKilograms: 2.5)
        #expect(rows.map(\.percent) == [95, 90, 85, 80, 75, 70, 65, 60, 55, 50])
        #expect(rows.first?.roundedKilograms == 95)
        #expect(rows.last?.roundedKilograms == 50)
        #expect(OneRepMaxCalculator.table(oneRepMaxKilograms: 0, stepKilograms: 2.5).isEmpty)
    }
}

@Suite("Bips de fin de repos")
struct RestBeepsTests {
    @Test("Trois bips aux trois dernières secondes, jamais dans le passé")
    func beepTimes() {
        let now = Date(timeIntervalSince1970: 1_000)
        let end = now.addingTimeInterval(60)
        #expect(RestBeeps.times(endDate: end, now: now).map { end.timeIntervalSince($0) } == [3, 2, 1])
        #expect(RestBeeps.times(endDate: now.addingTimeInterval(2.5), now: now).count == 2)
        #expect(RestBeeps.times(endDate: now, now: now).isEmpty)
    }
}
