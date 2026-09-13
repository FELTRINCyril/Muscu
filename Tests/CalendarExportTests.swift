import XCTest
import SwiftData
import MuscuEngine
@testable import Muscu

@MainActor
final class CalendarExportTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let reference = Date(timeIntervalSince1970: 1_770_000_000)

    override func setUpWithError() throws {
        container = try TestStore.makeContainer()
    }

    override func tearDownWithError() throws {
        container = nil
    }

    @discardableResult
    private func makeWorkout(offsetDays: Int = 1, name: String = "Séance A") -> ScheduledWorkout {
        let workout = ScheduledWorkout(
            plannedDate: reference.addingTimeInterval(Double(offsetDays) * 86_400),
            displayName: name
        )
        context.insert(workout)
        try? context.save()
        return workout
    }

    func testExportCreatesOneEventAndRecordsTheLink() async throws {
        let workout = makeWorkout()
        let store = InMemoryCalendarStore(status: .authorized)

        let outcome = await CalendarExportService.export(
            workouts: [workout],
            to: "cal-1",
            store: store,
            in: context
        )

        XCTAssertEqual(outcome.created, 1)
        let link = try XCTUnwrap(CalendarExportService.link(for: workout.id, in: context))
        let event = try XCTUnwrap(store.event(identifier: link.eventIdentifier))
        XCTAssertEqual(event.title, "Séance A")
        XCTAssertEqual(event.startDate, workout.plannedDate)
    }

    func testExportingTwiceUpdatesInsteadOfDuplicating() async throws {
        let workout = makeWorkout()
        let store = InMemoryCalendarStore(status: .authorized)
        await CalendarExportService.export(workouts: [workout], to: "cal-1", store: store, in: context)

        workout.displayName = "Séance A (modifiée)"
        let outcome = await CalendarExportService.export(workouts: [workout], to: "cal-1", store: store, in: context)

        XCTAssertEqual(outcome.created, 0)
        XCTAssertEqual(outcome.updated, 1)
        XCTAssertEqual(CalendarExportService.links(in: context).count, 1)
        let link = try XCTUnwrap(CalendarExportService.link(for: workout.id, in: context))
        XCTAssertEqual(store.event(identifier: link.eventIdentifier)?.title, "Séance A (modifiée)")
    }

    func testExternalEventIsNeverModifiedOrRemoved() async throws {
        let workout = makeWorkout()
        let store = InMemoryCalendarStore(status: .authorized)
        // Un evenement externe au MEME moment, que Muscu n'a pas cree.
        let external = store.insertExternalEvent(
            identifier: "externe-1",
            title: "Dîner de famille",
            start: workout.plannedDate,
            end: workout.plannedDate.addingTimeInterval(3_600)
        )

        await CalendarExportService.export(workouts: [workout], to: "cal-1", store: store, in: context)
        await CalendarExportService.remove(workouts: [workout], store: store, in: context)

        let stillThere = try XCTUnwrap(store.event(identifier: "externe-1"))
        XCTAssertEqual(stillThere, external, "Un événement externe ne doit jamais être touché")
    }

    func testRemoveDeletesOnlyOurEventAndItsLink() async throws {
        let workout = makeWorkout()
        let store = InMemoryCalendarStore(status: .authorized)
        await CalendarExportService.export(workouts: [workout], to: "cal-1", store: store, in: context)
        let link = try XCTUnwrap(CalendarExportService.link(for: workout.id, in: context))

        let outcome = await CalendarExportService.remove(workouts: [workout], store: store, in: context)

        XCTAssertEqual(outcome.removed, 1)
        XCTAssertNil(store.event(identifier: link.eventIdentifier))
        XCTAssertTrue(CalendarExportService.links(in: context).isEmpty)
    }

    func testEventDeletedInCalendarIsRecreatedWithoutOrphanLink() async throws {
        let workout = makeWorkout()
        let store = InMemoryCalendarStore(status: .authorized)
        await CalendarExportService.export(workouts: [workout], to: "cal-1", store: store, in: context)
        let firstLink = try XCTUnwrap(CalendarExportService.link(for: workout.id, in: context))

        // L'utilisateur supprime l'evenement depuis l'app Calendrier.
        _ = store.removeEvent(identifier: firstLink.eventIdentifier)

        let outcome = await CalendarExportService.export(workouts: [workout], to: "cal-1", store: store, in: context)

        XCTAssertEqual(outcome.created, 1)
        XCTAssertEqual(CalendarExportService.links(in: context).count, 1)
        let newLink = try XCTUnwrap(CalendarExportService.link(for: workout.id, in: context))
        XCTAssertNotEqual(newLink.eventIdentifier, firstLink.eventIdentifier)
    }

    func testWithoutPermissionNothingIsWrittenAndAppStillWorks() async throws {
        let workout = makeWorkout()
        let store = InMemoryCalendarStore(status: .notDetermined)
        store.accessAnswer = .denied

        let outcome = await CalendarExportService.export(workouts: [workout], to: "cal-1", store: store, in: context)

        XCTAssertEqual(outcome.authorization, .denied)
        XCTAssertEqual(outcome.created, 0)
        XCTAssertTrue(CalendarExportService.links(in: context).isEmpty)
        XCTAssertEqual(PlanningService.scheduledWorkouts(in: context).count, 1)
    }

    func testImportingASlotCreatesASinglePlannedWorkout() throws {
        let workout = CalendarExportService.importSlot(
            title: "Créneau salle",
            date: reference,
            programSessionId: nil,
            in: context
        )

        XCTAssertEqual(workout.displayName, "Créneau salle")
        XCTAssertEqual(workout.state, .planned)
        XCTAssertEqual(PlanningService.scheduledWorkouts(in: context).count, 1)
    }

    func testExportToReadOnlyCalendarFailsWithoutLosingAnything() async throws {
        let workout = makeWorkout()
        let store = InMemoryCalendarStore(
            status: .authorized,
            calendars: [CalendarDescriptor(id: "cal-ro", title: "Jours fériés", isWritable: false)]
        )

        let outcome = await CalendarExportService.export(workouts: [workout], to: "cal-ro", store: store, in: context)

        XCTAssertEqual(outcome.failed, 1)
        XCTAssertEqual(outcome.created, 0)
        XCTAssertTrue(CalendarExportService.links(in: context).isEmpty)
    }
}
