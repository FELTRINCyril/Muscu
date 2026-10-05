import Foundation
import Testing
@testable import MuscuEngine

@Suite("Recalcul des semaines à venir")
struct PlanRecalculationTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        calendar.firstWeekday = 2
        return calendar
    }

    private func date(_ string: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Paris")!
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)!
    }

    private func weeks(settledCount: Int, count: Int = 6) -> [PlanWeekState] {
        (1...count).map { number in
            PlanWeekState(
                number: number,
                blockKind: .accumulation,
                startDate: date("2026-01-05").addingTimeInterval(Double(number - 1) * 7 * 86_400),
                volumeMultiplier: 1,
                intensityMultiplier: 1,
                isSettled: number <= settledCount
            )
        }
    }

    private func preview(_ weeks: [PlanWeekState], from start: String) -> PlanRecalculationPreview {
        PlanRecalculation.preview(
            weeks: weeks,
            style: .linear,
            deloadEveryWeeks: 4,
            goal: .hypertrophy,
            experience: .intermediate,
            firstFutureWeekStart: date(start),
            calendar: calendar
        )
    }

    @Test("Les semaines déjà entamées ne sont jamais recalculées")
    func settledWeeksAreUntouched() {
        let result = preview(weeks(settledCount: 2), from: "2026-02-02")

        #expect(result.settledWeekNumbers == [1, 2])
        #expect(result.changes.map(\.number) == [3, 4, 5, 6])
        #expect(result.rationale.contains { $0.contains("laissées intactes") })
    }

    @Test("Les semaines à venir sont replanifiées de semaine en semaine")
    func futureWeeksAreRescheduled() {
        let result = preview(weeks(settledCount: 2), from: "2026-02-02")

        let starts = result.changes.map(\.newStartDate)
        for (previous, next) in zip(starts, starts.dropFirst()) {
            let days = calendar.dateComponents([.day], from: previous, to: next).day
            #expect(days == 7)
        }
        #expect(calendar.startOfDay(for: starts[0]) == date("2026-02-02"))
    }

    @Test("La décharge est réalignée sur la périodisation")
    func deloadMultipliersAreRealigned() {
        let result = preview(weeks(settledCount: 1), from: "2026-01-12")
        let fourth = result.changes.first { $0.number == 4 }

        #expect(fourth?.newVolumeMultiplier == Periodization.deloadVolumeMultiplier)
        #expect(fourth?.changesLoad == true)
    }

    @Test("Le décalage en jours est rapporté")
    func dayShiftIsReported() {
        // Les semaines partent du 5 janvier ; on repousse la 1re semaine à
        // venir de sept jours.
        let result = preview(weeks(settledCount: 0), from: "2026-01-12")
        #expect(result.changes.first?.dayShift == 7)
    }

    @Test("Un plan terminé ne propose rien")
    func finishedPlanHasNothingToDo() {
        let result = preview(weeks(settledCount: 6), from: "2026-03-02")
        #expect(result.changes.isEmpty)
        #expect(!result.hasChanges)
        #expect(result.rationale.contains { $0.contains("terminé") })
    }

    @Test("Un plan déjà aligné ne bouge pas")
    func alreadyAlignedPlanReportsNoMove() {
        // On recale sur la date de depart existante : aucune date ne bouge.
        let base = weeks(settledCount: 0, count: 4).map { week in
            PlanWeekState(
                number: week.number,
                blockKind: week.blockKind,
                startDate: week.startDate,
                volumeMultiplier: Periodization.weeks(
                    PeriodizationInput(
                        totalWeeks: 4,
                        style: .linear,
                        deloadEveryWeeks: 4,
                        goal: .hypertrophy,
                        experience: .intermediate
                    )
                ).first { $0.number == week.number }?.volumeMultiplier ?? 1,
                intensityMultiplier: Periodization.weeks(
                    PeriodizationInput(
                        totalWeeks: 4,
                        style: .linear,
                        deloadEveryWeeks: 4,
                        goal: .hypertrophy,
                        experience: .intermediate
                    )
                ).first { $0.number == week.number }?.intensityMultiplier ?? 1,
                isSettled: false
            )
        }
        let result = preview(base, from: "2026-01-05")

        #expect(!result.hasChanges)
        #expect(result.rationale.contains { $0.contains("déjà aligné") })
    }

    @Test("Le recalcul est déterministe")
    func recalculationIsDeterministic() {
        #expect(preview(weeks(settledCount: 2), from: "2026-02-02") == preview(weeks(settledCount: 2), from: "2026-02-02"))
    }
}
