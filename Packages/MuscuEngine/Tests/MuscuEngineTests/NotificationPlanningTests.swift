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

@Suite("Rappels de séance")
struct NotificationPlanningTests {
    private let calendar = parisCalendar()

    private func slot(_ day: String, id: UUID = UUID(), settled: Bool = false) -> PlannedSlot {
        PlannedSlot(id: id, date: date(day, in: calendar), title: "Séance A", isSettled: settled)
    }

    @Test("Sans autorisation, aucun rappel n'est planifié")
    func noAuthorizationMeansNoPlan() {
        let settings = ReminderSettings(isEnabled: true, leadMinutes: 60)
        let plan = NotificationPlanner.plan(
            slots: [slot("2026-03-02 18:00")],
            settings: settings,
            isAuthorized: false,
            now: date("2026-03-01 08:00", in: calendar),
            calendar: calendar
        )
        #expect(plan.isEmpty)
    }

    @Test("Rappels désactivés : rien n'est planifié même avec autorisation")
    func disabledSettingsMeanNoPlan() {
        let plan = NotificationPlanner.plan(
            slots: [slot("2026-03-02 18:00")],
            settings: .disabled,
            isAuthorized: true,
            now: date("2026-03-01 08:00", in: calendar),
            calendar: calendar
        )
        #expect(plan.isEmpty)
    }

    @Test("Délai avant séance et rappel du jour même")
    func leadAndDayOfReminders() {
        let id = UUID()
        let settings = ReminderSettings(
            isEnabled: true,
            leadMinutes: 90,
            dayOfTime: TimeOfDay(hour: 8, minute: 0)
        )
        let plan = NotificationPlanner.plan(
            slots: [slot("2026-03-02 18:00", id: id)],
            settings: settings,
            isAuthorized: true,
            now: date("2026-03-01 08:00", in: calendar),
            calendar: calendar
        )

        #expect(plan.count == 2)
        #expect(plan[0].kind == .dayOf)
        #expect(plan[1].kind == .before)
        #expect(plan[1].fireDate == date("2026-03-02 16:30", in: calendar))
        #expect(plan[1].identifier == PlannedNotification.identifier(workoutId: id, kind: .before))
    }

    @Test("Une séance déjà traitée ne déclenche aucun rappel")
    func settledSlotHasNoReminder() {
        let settings = ReminderSettings(isEnabled: true, leadMinutes: 60)
        let plan = NotificationPlanner.plan(
            slots: [slot("2026-03-02 18:00", settled: true)],
            settings: settings,
            isAuthorized: true,
            now: date("2026-03-01 08:00", in: calendar),
            calendar: calendar
        )
        #expect(plan.isEmpty)
    }

    @Test("Le rappel de reprise part de la dernière séance réelle")
    func comebackUsesLastActivity() {
        let settings = ReminderSettings(isEnabled: true, leadMinutes: 0, comebackAfterDays: 5)
        let plan = NotificationPlanner.plan(
            slots: [],
            settings: settings,
            isAuthorized: true,
            now: date("2026-03-01 08:00", in: calendar),
            calendar: calendar,
            lastActivity: date("2026-02-28 19:00", in: calendar)
        )

        #expect(plan.count == 1)
        #expect(plan[0].kind == .comeback)
        #expect(plan[0].fireDate == date("2026-03-05 19:00", in: calendar))
    }

    @Test("L'identifiant est stable : reprogrammer ne duplique pas")
    func identifiersAreStable() {
        let id = UUID()
        let settings = ReminderSettings(isEnabled: true, leadMinutes: 60)
        let now = date("2026-03-01 08:00", in: calendar)

        let first = NotificationPlanner.plan(slots: [slot("2026-03-02 18:00", id: id)], settings: settings, isAuthorized: true, now: now, calendar: calendar)
        let second = NotificationPlanner.plan(slots: [slot("2026-03-02 18:00", id: id)], settings: settings, isAuthorized: true, now: now, calendar: calendar)

        #expect(first.map(\.identifier) == second.map(\.identifier))

        let existing = Dictionary(uniqueKeysWithValues: first.map { ($0.identifier, $0.fireDate) })
        let reconciliation = NotificationPlanner.reconcile(desired: second, existing: existing, dismissedIdentifiers: [])
        #expect(reconciliation.isEmpty)
    }

    @Test("Un rappel supprimé par l'utilisateur ne revient jamais")
    func dismissedReminderNeverReturns() {
        let id = UUID()
        let settings = ReminderSettings(isEnabled: true, leadMinutes: 60)
        let desired = NotificationPlanner.plan(
            slots: [slot("2026-03-02 18:00", id: id)],
            settings: settings,
            isAuthorized: true,
            now: date("2026-03-01 08:00", in: calendar),
            calendar: calendar
        )
        let dismissed: Set<String> = [PlannedNotification.identifier(workoutId: id, kind: .before)]

        // Premier lancement après suppression : rien à programmer.
        let first = NotificationPlanner.reconcile(desired: desired, existing: [:], dismissedIdentifiers: dismissed)
        #expect(first.toSchedule.isEmpty)

        // Relance de l'application : toujours rien.
        let second = NotificationPlanner.reconcile(desired: desired, existing: [:], dismissedIdentifiers: dismissed)
        #expect(second.toSchedule.isEmpty)
    }

    @Test("Une séance déplacée reprogramme le rappel au lieu d'en ajouter un")
    func movedWorkoutReschedulesSameIdentifier() {
        let id = UUID()
        let settings = ReminderSettings(isEnabled: true, leadMinutes: 60)
        let now = date("2026-03-01 08:00", in: calendar)

        let before = NotificationPlanner.plan(slots: [slot("2026-03-02 18:00", id: id)], settings: settings, isAuthorized: true, now: now, calendar: calendar)
        let after = NotificationPlanner.plan(slots: [slot("2026-03-03 20:00", id: id)], settings: settings, isAuthorized: true, now: now, calendar: calendar)

        let existing = Dictionary(uniqueKeysWithValues: before.map { ($0.identifier, $0.fireDate) })
        let reconciliation = NotificationPlanner.reconcile(desired: after, existing: existing, dismissedIdentifiers: [])

        #expect(reconciliation.toSchedule.count == 1)
        #expect(reconciliation.toCancel.isEmpty)
        #expect(reconciliation.toSchedule[0].fireDate == date("2026-03-03 19:00", in: calendar))
    }

    @Test("Un rappel devenu inutile est annulé")
    func obsoleteReminderIsCancelled() {
        let id = UUID()
        let identifier = PlannedNotification.identifier(workoutId: id, kind: .before)
        let reconciliation = NotificationPlanner.reconcile(
            desired: [],
            existing: [identifier: date("2026-03-02 17:00", in: calendar)],
            dismissedIdentifiers: []
        )
        #expect(reconciliation.toCancel == [identifier])
    }

    @Test("Les jours autorisés filtrent les rappels")
    func allowedWeekdaysFilter() {
        let settings = ReminderSettings(
            isEnabled: true,
            leadMinutes: 60,
            allowedWeekdays: [2] // lundi seulement
        )
        let plan = NotificationPlanner.plan(
            slots: [slot("2026-03-03 18:00")], // mardi
            settings: settings,
            isAuthorized: true,
            now: date("2026-03-01 08:00", in: calendar),
            calendar: calendar
        )
        #expect(plan.isEmpty)
    }
}
