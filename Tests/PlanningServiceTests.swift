import XCTest
import SwiftData
import MuscuEngine
@testable import Muscu

@MainActor
final class PlanningServiceTests: XCTestCase {
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
    private func makeSchedule(weekdays: Set<Int> = [2, 5], start: String = "2026-01-05 00:00") -> PlanningSchedule {
        let schedule = PlanningSchedule(name: "Semaine type", startDate: date(start), hour: 18, minute: 0)
        schedule.weekdays = weekdays
        context.insert(schedule)
        try? context.save()
        return schedule
    }

    @discardableResult
    private func makeProgram(sessionNames: [String]) -> Program {
        let program = Program(name: "Programme", isActive: true)
        context.insert(program)
        for (index, name) in sessionNames.enumerated() {
            let session = ProgramSession(name: name, orderIndex: index)
            session.program = program
            program.sessions.append(session)
            context.insert(session)
        }
        try? context.save()
        return program
    }

    // MARK: - Récurrence

    func testRecurrenceCreatesWorkoutsAndRotatesSessions() throws {
        let schedule = makeSchedule()
        let program = makeProgram(sessionNames: ["A", "B"])

        let result = PlanningService.applyRecurrence(
            schedule,
            program: program,
            in: context,
            calendar: calendar,
            now: date("2026-01-05 08:00"),
            horizonWeeks: 2
        )
        try context.save()

        XCTAssertEqual(result.created, 4)
        let workouts = PlanningService.scheduledWorkouts(in: context)
        XCTAssertEqual(workouts.count, 4)
        XCTAssertEqual(workouts.map(\.displayName), ["A", "B", "A", "B"])
        XCTAssertTrue(workouts.allSatisfy { $0.scheduleId == schedule.id })
        XCTAssertTrue(workouts.allSatisfy { calendar.component(.hour, from: $0.plannedDate) == 18 })
    }

    func testRecurrenceIsIdempotent() throws {
        let schedule = makeSchedule()
        let program = makeProgram(sessionNames: ["A"])
        let now = date("2026-01-05 08:00")

        PlanningService.applyRecurrence(schedule, program: program, in: context, calendar: calendar, now: now, horizonWeeks: 2)
        try context.save()
        let second = PlanningService.applyRecurrence(schedule, program: program, in: context, calendar: calendar, now: now, horizonWeeks: 2)
        try context.save()

        XCTAssertEqual(second.created, 0)
        XCTAssertEqual(second.removed, 0)
        XCTAssertEqual(PlanningService.scheduledWorkouts(in: context).count, 4)
    }

    func testRecurrenceNeverRewritesSettledWorkouts() throws {
        let schedule = makeSchedule()
        let program = makeProgram(sessionNames: ["A"])
        let now = date("2026-01-05 08:00")

        PlanningService.applyRecurrence(schedule, program: program, in: context, calendar: calendar, now: now, horizonWeeks: 2)
        try context.save()

        let first = try XCTUnwrap(PlanningService.scheduledWorkouts(in: context).first)
        first.state = .completed
        first.displayName = "A (faite)"
        try context.save()

        // La récurrence change d'heure : la séance terminée ne doit pas bouger.
        schedule.hour = 7
        PlanningService.applyRecurrence(schedule, program: program, in: context, calendar: calendar, now: now, horizonWeeks: 2)
        try context.save()

        let reloaded = try XCTUnwrap(PlanningService.scheduledWorkouts(in: context).first { $0.id == first.id })
        XCTAssertEqual(reloaded.state, .completed)
        XCTAssertEqual(reloaded.displayName, "A (faite)")
        XCTAssertEqual(calendar.component(.hour, from: reloaded.plannedDate), 18)
    }

    func testRemovingAWeekdayRetiresOnlyUntouchedFutureWorkouts() throws {
        let schedule = makeSchedule(weekdays: [2, 5])
        let program = makeProgram(sessionNames: ["A"])
        let now = date("2026-01-05 08:00")

        PlanningService.applyRecurrence(schedule, program: program, in: context, calendar: calendar, now: now, horizonWeeks: 2)
        try context.save()

        // Une séance du jeudi est déjà commencée : elle doit survivre.
        let thursday = try XCTUnwrap(PlanningService.scheduledWorkouts(in: context)
            .first { calendar.component(.weekday, from: $0.plannedDate) == 5 })
        thursday.state = .started
        try context.save()

        schedule.weekdays = [2]
        PlanningService.applyRecurrence(schedule, program: program, in: context, calendar: calendar, now: now, horizonWeeks: 2)
        try context.save()

        let remaining = PlanningService.scheduledWorkouts(in: context)
        XCTAssertTrue(remaining.contains { $0.id == thursday.id })
        XCTAssertEqual(remaining.filter { calendar.component(.weekday, from: $0.plannedDate) == 5 }.count, 1)
    }

    /// Une séance déplacée à la main ne doit pas faire réapparaître un
    /// doublon à la date qu'on vient de quitter.
    func testMovedWorkoutDoesNotGetReplacedByANewOne() throws {
        let schedule = makeSchedule(weekdays: [2])
        let program = makeProgram(sessionNames: ["A"])
        let now = date("2026-01-05 08:00")

        PlanningService.applyRecurrence(schedule, program: program, in: context, calendar: calendar, now: now, horizonWeeks: 2)
        try context.save()
        let countBefore = PlanningService.scheduledWorkouts(in: context).count

        let moved = try XCTUnwrap(PlanningService.scheduledWorkouts(in: context).first)
        PlanningService.move(moved, to: date("2026-01-07 18:00"), in: context)

        PlanningService.applyRecurrence(schedule, program: program, in: context, calendar: calendar, now: now, horizonWeeks: 2)
        try context.save()

        let after = PlanningService.scheduledWorkouts(in: context)
        XCTAssertEqual(after.count, countBefore, "Aucun doublon ne doit apparaître au créneau libéré")
        XCTAssertEqual(after.first { $0.id == moved.id }?.plannedDate, date("2026-01-07 18:00"))
    }

    func testDisabledScheduleCreatesNothing() throws {
        let schedule = makeSchedule()
        schedule.isEnabled = false
        let result = PlanningService.applyRecurrence(schedule, program: nil, in: context, calendar: calendar, now: date("2026-01-05 08:00"))
        XCTAssertEqual(result.created, 0)
        XCTAssertTrue(PlanningService.scheduledWorkouts(in: context).isEmpty)
    }

    // MARK: - Déplacement

    func testMoveKeepsOriginalDateAndNeverTouchesHistory() throws {
        let workout = ScheduledWorkout(plannedDate: date("2026-01-05 18:00"), displayName: "A")
        context.insert(workout)
        let history = CompletedSession(date: date("2026-01-05 19:00"), programName: "P", sessionName: "A")
        context.insert(history)
        try context.save()

        PlanningService.move(workout, to: date("2026-01-07 18:00"), in: context)

        XCTAssertEqual(workout.originalDate, date("2026-01-05 18:00"))
        XCTAssertEqual(workout.state, .postponed)
        XCTAssertEqual(history.date, date("2026-01-05 19:00"))
        XCTAssertEqual(history.revision, 1)
    }

    func testCompletedWorkoutIsNeverMoved() throws {
        let workout = ScheduledWorkout(plannedDate: date("2026-01-05 18:00"), displayName: "A")
        workout.state = .completed
        context.insert(workout)
        try context.save()

        PlanningService.move(workout, to: date("2026-01-09 18:00"), in: context)
        XCTAssertEqual(workout.plannedDate, date("2026-01-05 18:00"))
    }

    // MARK: - Replanification

    func testProposalsAvoidStackingTwoMissedSessionsOnTheSameDay() throws {
        let schedule = makeSchedule(weekdays: [])
        _ = schedule
        let first = ScheduledWorkout(plannedDate: date("2026-01-05 18:00"), displayName: "A")
        let second = ScheduledWorkout(plannedDate: date("2026-01-06 18:00"), displayName: "B")
        context.insert(first)
        context.insert(second)
        try context.save()

        let proposals = PlanningService.rescheduleProposals(
            in: context,
            catalog: nil,
            calendar: calendar,
            now: date("2026-01-08 08:00")
        )

        XCTAssertEqual(proposals.count, 2)
        let days = proposals.map { calendar.startOfDay(for: $0.proposedDate) }
        XCTAssertEqual(Set(days).count, 2, "Deux séances manquées ne doivent pas atterrir le même jour")
    }

    func testAcceptingAProposalMovesTheWorkout() throws {
        let workout = ScheduledWorkout(plannedDate: date("2026-01-05 18:00"), displayName: "A")
        context.insert(workout)
        try context.save()

        let proposals = PlanningService.rescheduleProposals(
            in: context,
            catalog: nil,
            calendar: calendar,
            now: date("2026-01-08 08:00")
        )
        let proposal = try XCTUnwrap(proposals.first)
        PlanningService.accept(proposal, in: context)

        XCTAssertEqual(workout.plannedDate, proposal.proposedDate)
        XCTAssertEqual(workout.originalDate, date("2026-01-05 18:00"))
    }

    func testSkippedWorkoutIsNotProposedAgain() throws {
        let workout = ScheduledWorkout(plannedDate: date("2026-01-05 18:00"), displayName: "A")
        workout.state = .skipped
        context.insert(workout)
        try context.save()

        let proposals = PlanningService.rescheduleProposals(
            in: context,
            catalog: nil,
            calendar: calendar,
            now: date("2026-01-08 08:00")
        )
        XCTAssertTrue(proposals.isEmpty)
    }
}
