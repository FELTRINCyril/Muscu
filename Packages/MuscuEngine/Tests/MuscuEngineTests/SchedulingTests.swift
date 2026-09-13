import Foundation
import Testing
@testable import MuscuEngine

private func parisCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    return calendar
}

private func date(_ string: String, in calendar: Calendar) -> Date {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    return formatter.date(from: string)!
}

@Suite("Collisions et replanification")
struct SchedulingTests {
    @Test("Deux séances le même jour sont signalées")
    func sameDayIsReported() {
        let calendar = parisCalendar()
        let slots = [
            PlannedSlot(id: UUID(), date: date("2026-02-02 09:00", in: calendar), title: "Haut"),
            PlannedSlot(id: UUID(), date: date("2026-02-02 19:00", in: calendar), title: "Bas"),
        ]

        let conflicts = ScheduleConflictDetector.conflicts(among: slots, calendar: calendar)
        #expect(conflicts.count == 1)
        #expect(conflicts.first?.kind == .sameDay)
    }

    @Test("Une séance terminée n'entre plus en collision")
    func settledSlotsAreIgnored() {
        let calendar = parisCalendar()
        let slots = [
            PlannedSlot(id: UUID(), date: date("2026-02-02 09:00", in: calendar), title: "Haut", isSettled: true),
            PlannedSlot(id: UUID(), date: date("2026-02-02 19:00", in: calendar), title: "Bas"),
        ]

        #expect(ScheduleConflictDetector.conflicts(among: slots, calendar: calendar).isEmpty)
    }

    @Test("Deux séances trop rapprochées sur le même muscle sont signalées")
    func insufficientRecoveryIsReported() {
        let calendar = parisCalendar()
        let slots = [
            PlannedSlot(id: UUID(), date: date("2026-02-02 09:00", in: calendar), title: "Pecs", primaryMuscles: ["chest"]),
            PlannedSlot(id: UUID(), date: date("2026-02-03 09:00", in: calendar), title: "Pecs bis", primaryMuscles: ["chest", "triceps"]),
        ]

        let conflicts = ScheduleConflictDetector.conflicts(among: slots, calendar: calendar)
        #expect(conflicts.count == 1)
        if case .insufficientRecovery(let hours, let muscles) = conflicts[0].kind {
            #expect(hours == 24)
            #expect(muscles == ["chest"])
        } else {
            Issue.record("Conflit de récupération attendu")
        }
    }

    @Test("Des muscles différents ne créent aucun conflit")
    func differentMusclesDoNotConflict() {
        let calendar = parisCalendar()
        let slots = [
            PlannedSlot(id: UUID(), date: date("2026-02-02 09:00", in: calendar), title: "Haut", primaryMuscles: ["chest"]),
            PlannedSlot(id: UUID(), date: date("2026-02-03 09:00", in: calendar), title: "Bas", primaryMuscles: ["quadriceps"]),
        ]

        #expect(ScheduleConflictDetector.conflicts(among: slots, calendar: calendar).isEmpty)
    }

    @Test("Une séance passée et non traitée est considérée manquée")
    func missedSlotsAreDetected() {
        let calendar = parisCalendar()
        let now = date("2026-02-05 08:00", in: calendar)
        let missed = PlannedSlot(id: UUID(), date: date("2026-02-03 18:00", in: calendar), title: "Manquée")
        let done = PlannedSlot(id: UUID(), date: date("2026-02-02 18:00", in: calendar), title: "Faite", isSettled: true)
        let upcoming = PlannedSlot(id: UUID(), date: date("2026-02-07 18:00", in: calendar), title: "À venir")

        let result = RescheduleAdvisor.missedSlots(among: [missed, done, upcoming], now: now, calendar: calendar)
        #expect(result.map(\.id) == [missed.id])
    }

    @Test("La proposition tombe sur un jour habituel libre")
    func proposalPrefersHabitualDays() {
        let calendar = parisCalendar()
        let now = date("2026-02-05 08:00", in: calendar) // jeudi
        let missed = PlannedSlot(id: UUID(), date: date("2026-02-03 18:00", in: calendar), title: "Manquée")
        let occupied = PlannedSlot(id: UUID(), date: date("2026-02-06 18:00", in: calendar), title: "Vendredi pris")

        // 2 = lundi, 6 = vendredi.
        let proposal = RescheduleAdvisor.proposal(
            for: missed,
            among: [missed, occupied],
            preferredWeekdays: [2, 6],
            now: now,
            calendar: calendar
        )

        let proposed = try! #require(proposal)
        // Vendredi 6 est occupé : la proposition passe au lundi 9.
        #expect(calendar.component(.weekday, from: proposed.proposedDate) == 2)
        #expect(calendar.component(.day, from: proposed.proposedDate) == 9)
        #expect(calendar.component(.hour, from: proposed.proposedDate) == 18)
        #expect(proposed.remainingConflicts.isEmpty)
    }

    @Test("Sans jour habituel libre, la proposition prend le premier jour libre et le dit")
    func proposalFallsBackAndExplains() {
        let calendar = parisCalendar()
        let now = date("2026-02-05 08:00", in: calendar)
        let missed = PlannedSlot(id: UUID(), date: date("2026-02-03 18:00", in: calendar), title: "Manquée")

        let proposal = RescheduleAdvisor.proposal(
            for: missed,
            among: [missed],
            preferredWeekdays: [1], // dimanche uniquement, hors fenêtre courte
            now: now,
            calendar: calendar,
            searchDays: 2
        )

        let proposed = try! #require(proposal)
        #expect(proposed.rationale.contains("Premier jour libre"))
    }

    @Test("Une proposition qui reste en conflit le signale au lieu de le taire")
    func remainingConflictIsSurfaced() {
        let calendar = parisCalendar()
        let now = date("2026-02-05 08:00", in: calendar)
        let missed = PlannedSlot(
            id: UUID(),
            date: date("2026-02-03 18:00", in: calendar),
            title: "Pecs",
            primaryMuscles: ["chest"]
        )
        let nextDay = PlannedSlot(
            id: UUID(),
            date: date("2026-02-06 18:00", in: calendar),
            title: "Pecs bis",
            primaryMuscles: ["chest"]
        )

        let proposal = RescheduleAdvisor.proposal(
            for: missed,
            among: [missed, nextDay],
            preferredWeekdays: [],
            now: now,
            calendar: calendar
        )

        let proposed = try! #require(proposal)
        #expect(calendar.component(.day, from: proposed.proposedDate) == 5)
        #expect(proposed.remainingConflicts.count == 1)
    }
}
