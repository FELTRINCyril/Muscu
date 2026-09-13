import XCTest
import SwiftData
import MuscuEngine
import UserNotifications
@testable import Muscu

@MainActor
final class ReminderServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    override func setUpWithError() throws {
        container = try TestStore.makeContainer()
    }

    override func tearDownWithError() throws {
        container = nil
    }

    private func date(_ string: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: string)!
    }

    @discardableResult
    private func makeScheduleWithWorkout(leadMinutes: Int = 60) -> (PlanningSchedule, ScheduledWorkout) {
        let schedule = PlanningSchedule(name: "Semaine type", startDate: date("2026-03-01 00:00"), hour: 18, minute: 0)
        schedule.weekdays = [2]
        schedule.remindersEnabled = true
        schedule.reminderLeadMinutes = leadMinutes
        context.insert(schedule)

        let workout = ScheduledWorkout(
            plannedDate: date("2026-03-02 18:00"),
            displayName: "Séance A",
            scheduleId: schedule.id
        )
        context.insert(workout)
        try? context.save()
        return (schedule, workout)
    }

    // MARK: - Autorisation

    func testNothingIsScheduledWithoutAuthorization() async throws {
        makeScheduleWithWorkout()
        let scheduler = InMemoryNotificationScheduler(status: .notDetermined)

        let outcome = await ReminderService.refresh(
            in: context,
            scheduler: scheduler,
            calendar: calendar,
            now: date("2026-03-01 08:00")
        )

        XCTAssertEqual(outcome.scheduled, 0)
        let pending = await scheduler.pendingIdentifiers()
        XCTAssertTrue(pending.isEmpty)
        XCTAssertEqual(scheduler.authorizationRequestCount, 0, "Le rafraîchissement ne doit jamais demander l’autorisation")
    }

    func testEnablingRemindersAsksOnceAndSchedules() async throws {
        let (schedule, _) = makeScheduleWithWorkout()
        schedule.remindersEnabled = false
        let scheduler = InMemoryNotificationScheduler(status: .notDetermined)

        let outcome = await ReminderService.enableReminders(
            for: schedule,
            in: context,
            scheduler: scheduler,
            calendar: calendar,
            now: date("2026-03-01 08:00")
        )

        XCTAssertEqual(scheduler.authorizationRequestCount, 1)
        XCTAssertTrue(outcome.isAuthorized)
        XCTAssertTrue(schedule.remindersEnabled)
        let pending = await scheduler.pendingIdentifiers()
        XCTAssertEqual(pending.count, 1)
    }

    func testRefusedAuthorizationLeavesRemindersOff() async throws {
        let (schedule, _) = makeScheduleWithWorkout()
        schedule.remindersEnabled = false
        let scheduler = InMemoryNotificationScheduler(status: .notDetermined)
        scheduler.authorizationAnswer = .denied

        let outcome = await ReminderService.enableReminders(
            for: schedule,
            in: context,
            scheduler: scheduler,
            calendar: calendar,
            now: date("2026-03-01 08:00")
        )

        XCTAssertEqual(outcome.authorization, .denied)
        XCTAssertFalse(schedule.remindersEnabled)
        let pending = await scheduler.pendingIdentifiers()
        XCTAssertTrue(pending.isEmpty)
    }

    func testRevokedAuthorizationCancelsRemindersWithoutTouchingData() async throws {
        let (_, workout) = makeScheduleWithWorkout()
        let scheduler = InMemoryNotificationScheduler(status: .authorized)
        await ReminderService.refresh(in: context, scheduler: scheduler, calendar: calendar, now: date("2026-03-01 08:00"))
        var pending = await scheduler.pendingIdentifiers()
        XCTAssertEqual(pending.count, 1)

        let revoked = InMemoryNotificationScheduler(status: .denied)
        await revoked.schedule([
            PlannedNotification(
                identifier: PlannedNotification.identifier(workoutId: workout.id, kind: .before),
                kind: .before,
                fireDate: date("2026-03-02 17:00"),
                workoutId: workout.id,
                title: "Séance A",
                body: "",
                isSoundEnabled: true
            ),
        ])

        let outcome = await ReminderService.refresh(in: context, scheduler: revoked, calendar: calendar, now: date("2026-03-01 08:00"))

        XCTAssertEqual(outcome.authorization, .denied)
        pending = await revoked.pendingIdentifiers()
        XCTAssertTrue(pending.isEmpty)
        XCTAssertEqual(PlanningService.scheduledWorkouts(in: context).count, 1, "Les séances planifiées ne doivent jamais être supprimées")
    }

    // MARK: - Suppression volontaire

    func testDismissedReminderIsNotRecreatedAfterRelaunch() async throws {
        let (_, workout) = makeScheduleWithWorkout()
        let scheduler = InMemoryNotificationScheduler(status: .authorized)
        let now = date("2026-03-01 08:00")

        await ReminderService.refresh(in: context, scheduler: scheduler, calendar: calendar, now: now)
        let identifier = PlannedNotification.identifier(workoutId: workout.id, kind: .before)
        var pending = await scheduler.pendingIdentifiers()
        XCTAssertNotNil(pending[identifier])

        await ReminderService.dismiss(identifier: identifier, in: context, scheduler: scheduler)
        pending = await scheduler.pendingIdentifiers()
        XCTAssertNil(pending[identifier])

        // « Relancement » : on repart d'un planificateur vierge, comme au
        // demarrage de l'application, et on recalcule.
        let afterRelaunch = InMemoryNotificationScheduler(status: .authorized)
        await ReminderService.refresh(in: context, scheduler: afterRelaunch, calendar: calendar, now: now)

        pending = await afterRelaunch.pendingIdentifiers()
        XCTAssertTrue(pending.isEmpty, "Un rappel supprimé ne doit jamais réapparaître")
    }

    func testReEnablingRemindersClearsPreviousDismissals() async throws {
        let (schedule, workout) = makeScheduleWithWorkout()
        let scheduler = InMemoryNotificationScheduler(status: .authorized)
        let now = date("2026-03-01 08:00")
        await ReminderService.refresh(in: context, scheduler: scheduler, calendar: calendar, now: now)

        let identifier = PlannedNotification.identifier(workoutId: workout.id, kind: .before)
        await ReminderService.dismiss(identifier: identifier, in: context, scheduler: scheduler)

        _ = await ReminderService.enableReminders(
            for: schedule,
            in: context,
            scheduler: scheduler,
            calendar: calendar,
            now: now
        )

        let pending = await scheduler.pendingIdentifiers()
        XCTAssertNotNil(pending[identifier])
        XCTAssertTrue(ReminderService.dismissedIdentifiers(in: context).isEmpty)
    }

    func testStandaloneWorkoutAlsoGetsAReminder() async throws {
        makeScheduleWithWorkout()
        let standalone = ScheduledWorkout(plannedDate: date("2026-03-04 12:00"), displayName: "Séance ponctuelle")
        context.insert(standalone)
        try context.save()

        let scheduler = InMemoryNotificationScheduler(status: .authorized)
        await ReminderService.refresh(in: context, scheduler: scheduler, calendar: calendar, now: date("2026-03-01 08:00"))

        let pending = await scheduler.pendingIdentifiers()
        XCTAssertEqual(pending.count, 2)
        XCTAssertNotNil(pending[PlannedNotification.identifier(workoutId: standalone.id, kind: .before)])
    }

    // MARK: - Recalcul

    func testMovingAWorkoutReschedulesInsteadOfDuplicating() async throws {
        let (_, workout) = makeScheduleWithWorkout()
        let scheduler = InMemoryNotificationScheduler(status: .authorized)
        let now = date("2026-03-01 08:00")
        await ReminderService.refresh(in: context, scheduler: scheduler, calendar: calendar, now: now)

        PlanningService.move(workout, to: date("2026-03-03 20:00"), in: context)
        await ReminderService.refresh(in: context, scheduler: scheduler, calendar: calendar, now: now)

        let pending = await scheduler.pendingIdentifiers()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.values.first, date("2026-03-03 19:00"))
    }

    func testTimeZoneChangeRecomputesLocalFireTime() async throws {
        let (_, _) = makeScheduleWithWorkout()
        let scheduler = InMemoryNotificationScheduler(status: .authorized)
        let now = date("2026-03-01 08:00")

        await ReminderService.refresh(in: context, scheduler: scheduler, calendar: calendar, now: now)
        let afterFirstRefresh = await scheduler.pendingIdentifiers()
        let parisFire = try XCTUnwrap(afterFirstRefresh.values.first)

        // Le meme planning relu depuis Tokyo : l'INSTANT ne change pas, car
        // la seance est datee, mais le calcul reste coherent et ne duplique
        // aucun rappel.
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        await ReminderService.refresh(in: context, scheduler: scheduler, calendar: tokyo, now: now)

        let pending = await scheduler.pendingIdentifiers()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.values.first, parisFire)
    }

    func testSettledWorkoutCancelsItsReminder() async throws {
        let (_, workout) = makeScheduleWithWorkout()
        let scheduler = InMemoryNotificationScheduler(status: .authorized)
        let now = date("2026-03-01 08:00")
        await ReminderService.refresh(in: context, scheduler: scheduler, calendar: calendar, now: now)
        let before = await scheduler.pendingIdentifiers()
        XCTAssertEqual(before.count, 1)

        PlanningService.update(workout, to: .completed, in: context)
        let outcome = await ReminderService.refresh(in: context, scheduler: scheduler, calendar: calendar, now: now)

        XCTAssertEqual(outcome.cancelled, 1)
        let after = await scheduler.pendingIdentifiers()
        XCTAssertTrue(after.isEmpty)
    }

    func testGlobalSwitchCancelsEveryReminderAtOnce() async throws {
        let (schedule, _) = makeScheduleWithWorkout()
        let other = PlanningSchedule(name: "Autre", startDate: date("2026-03-01 00:00"), hour: 7, minute: 0)
        other.weekdays = [3]
        other.remindersEnabled = true
        context.insert(other)
        let secondWorkout = ScheduledWorkout(
            plannedDate: date("2026-03-03 07:00"),
            displayName: "Séance B",
            scheduleId: other.id
        )
        context.insert(secondWorkout)
        try context.save()

        let scheduler = InMemoryNotificationScheduler(status: .authorized)
        let now = date("2026-03-01 08:00")
        await ReminderService.refresh(in: context, scheduler: scheduler, calendar: calendar, now: now)
        let before = await scheduler.pendingIdentifiers()
        XCTAssertEqual(before.count, 2)
        XCTAssertTrue(ReminderService.hasEnabledReminders(in: context))

        let outcome = await ReminderService.disableAllReminders(in: context, scheduler: scheduler, now: now)

        XCTAssertEqual(outcome.cancelled, 2)
        let after = await scheduler.pendingIdentifiers()
        XCTAssertTrue(after.isEmpty)
        XCTAssertFalse(ReminderService.hasEnabledReminders(in: context))
        XCTAssertFalse(schedule.remindersEnabled)
        XCTAssertFalse(other.remindersEnabled)
        XCTAssertEqual(PlanningService.scheduledWorkouts(in: context).count, 2, "Le planning reste intact")
    }

    func testDisablingRemindersCancelsEverything() async throws {
        let (schedule, _) = makeScheduleWithWorkout()
        let scheduler = InMemoryNotificationScheduler(status: .authorized)
        let now = date("2026-03-01 08:00")
        await ReminderService.refresh(in: context, scheduler: scheduler, calendar: calendar, now: now)

        _ = await ReminderService.disableReminders(
            for: schedule,
            in: context,
            scheduler: scheduler,
            calendar: calendar,
            now: now
        )

        let pending = await scheduler.pendingIdentifiers()
        XCTAssertTrue(pending.isEmpty)
        XCTAssertFalse(schedule.remindersEnabled)
    }
}

/// Les trois actions proposées depuis un rappel sont sûres : aucune n'écrit
/// de performance, aucune ne supprime de donnée.
@MainActor
final class NotificationResponderTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let reference = Date(timeIntervalSince1970: 1_772_000_000)

    override func setUpWithError() throws {
        container = try TestStore.makeContainer()
    }

    override func tearDownWithError() throws {
        container = nil
    }

    @discardableResult
    private func makeWorkout() -> ScheduledWorkout {
        let workout = ScheduledWorkout(plannedDate: reference, displayName: "Séance A")
        context.insert(workout)
        try? context.save()
        return workout
    }

    func testPostponeMovesTheWorkoutByOneDay() throws {
        let workout = makeWorkout()
        NotificationResponder.handle(
            action: WorkoutNotificationActions.postpone,
            workoutId: workout.id,
            container: container
        )

        XCTAssertEqual(workout.plannedDate, reference.addingTimeInterval(86_400))
        XCTAssertEqual(workout.state, .postponed)
        XCTAssertEqual(workout.originalDate, reference)
    }

    func testSkipMarksTheWorkoutWithoutDeletingIt() throws {
        let workout = makeWorkout()
        NotificationResponder.handle(
            action: WorkoutNotificationActions.skip,
            workoutId: workout.id,
            container: container
        )

        XCTAssertEqual(workout.state, .skipped)
        XCTAssertEqual(PlanningService.scheduledWorkouts(in: context).count, 1)
    }

    func testStartOnlyRoutesAndChangesNothing() throws {
        let workout = makeWorkout()
        NotificationResponder.handle(
            action: WorkoutNotificationActions.start,
            workoutId: workout.id,
            container: container
        )

        XCTAssertEqual(workout.state, .planned)
        XCTAssertEqual(workout.plannedDate, reference)
        XCTAssertEqual(IntentRouter.shared.consume(), .home)
    }

    func testDismissingTheBannerChangesNothing() throws {
        let workout = makeWorkout()
        NotificationResponder.handle(
            action: UNNotificationDismissActionIdentifier,
            workoutId: workout.id,
            container: container
        )

        XCTAssertEqual(workout.state, .planned)
        XCTAssertEqual(workout.plannedDate, reference)
    }

    func testAnUnknownWorkoutIsIgnoredSafely() throws {
        makeWorkout()
        NotificationResponder.handle(
            action: WorkoutNotificationActions.skip,
            workoutId: UUID(),
            container: container
        )

        XCTAssertEqual(PlanningService.scheduledWorkouts(in: context).first?.state, .planned)
    }
}
