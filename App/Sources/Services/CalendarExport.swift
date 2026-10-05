import Foundation
import SwiftData
import EventKit
import MuscuEngine

enum CalendarAuthorization: Sendable, Equatable {
    case notDetermined
    case authorized
    case denied
    /// L'appareil ne donne pas acces au calendrier (Mac Catalyst sans
    /// autorisation, profil restreint...). L'application reste utilisable.
    case unavailable
}

struct CalendarDescriptor: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let isWritable: Bool
}

/// Instantane d'un evenement, suffisant pour verifier ce qui a ete ecrit
/// sans dependre d'EventKit dans les tests.
struct CalendarEventSnapshot: Hashable, Sendable {
    let identifier: String
    let calendarId: String
    var title: String
    var startDate: Date
    var endDate: Date
    var notes: String
}

/// Acces au calendrier du systeme, abstrait pour rester testable.
protocol CalendarStoring: AnyObject, Sendable {
    func authorizationStatus() -> CalendarAuthorization
    func requestAccess() async -> CalendarAuthorization
    func writableCalendars() -> [CalendarDescriptor]
    func event(identifier: String) -> CalendarEventSnapshot?
    /// Cree l'evenement et renvoie son identifiant, ou `nil` en cas d'echec.
    func createEvent(in calendarId: String, title: String, start: Date, end: Date, notes: String) -> String?
    func updateEvent(identifier: String, title: String, start: Date, end: Date, notes: String) -> Bool
    func removeEvent(identifier: String) -> Bool
}

/// Implementation EventKit.
final class EventKitCalendarStore: CalendarStoring, @unchecked Sendable {
    private let store = EKEventStore()

    func authorizationStatus() -> CalendarAuthorization {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .writeOnly: return .authorized
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .unavailable
        }
    }

    func requestAccess() async -> CalendarAuthorization {
        do {
            let granted = try await store.requestFullAccessToEvents()
            return granted ? .authorized : .denied
        } catch {
            return .denied
        }
    }

    func writableCalendars() -> [CalendarDescriptor] {
        store.calendars(for: .event)
            .filter { $0.allowsContentModifications }
            .map { CalendarDescriptor(id: $0.calendarIdentifier, title: $0.title, isWritable: true) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func event(identifier: String) -> CalendarEventSnapshot? {
        guard let event = store.event(withIdentifier: identifier),
              let start = event.startDate,
              let end = event.endDate else { return nil }
        return CalendarEventSnapshot(
            identifier: identifier,
            calendarId: event.calendar?.calendarIdentifier ?? "",
            title: event.title ?? "",
            startDate: start,
            endDate: end,
            notes: event.notes ?? ""
        )
    }

    func createEvent(in calendarId: String, title: String, start: Date, end: Date, notes: String) -> String? {
        guard let calendar = store.calendar(withIdentifier: calendarId), calendar.allowsContentModifications else {
            return nil
        }
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = title
        event.startDate = start
        event.endDate = end
        event.notes = notes
        do {
            try store.save(event, span: .thisEvent, commit: true)
            return event.eventIdentifier
        } catch {
            return nil
        }
    }

    func updateEvent(identifier: String, title: String, start: Date, end: Date, notes: String) -> Bool {
        guard let event = store.event(withIdentifier: identifier) else { return false }
        event.title = title
        event.startDate = start
        event.endDate = end
        event.notes = notes
        do {
            try store.save(event, span: .thisEvent, commit: true)
            return true
        } catch {
            return false
        }
    }

    func removeEvent(identifier: String) -> Bool {
        guard let event = store.event(withIdentifier: identifier) else { return false }
        do {
            try store.remove(event, span: .thisEvent, commit: true)
            return true
        } catch {
            return false
        }
    }
}

/// Calendrier en memoire pour les tests : il permet de verifier qu'un
/// evenement EXTERNE n'est jamais modifie.
final class InMemoryCalendarStore: CalendarStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var events: [String: CalendarEventSnapshot] = [:]
    private var status: CalendarAuthorization
    var accessAnswer: CalendarAuthorization = .authorized
    private(set) var accessRequestCount = 0
    private var calendars: [CalendarDescriptor]

    init(
        status: CalendarAuthorization = .notDetermined,
        calendars: [CalendarDescriptor] = [CalendarDescriptor(id: "cal-1", title: "Perso", isWritable: true)]
    ) {
        self.status = status
        self.calendars = calendars
    }

    /// Insere un evenement que Muscu n'a PAS cree.
    @discardableResult
    func insertExternalEvent(
        identifier: String,
        calendarId: String = "cal-1",
        title: String,
        start: Date,
        end: Date,
        notes: String = ""
    ) -> CalendarEventSnapshot {
        let snapshot = CalendarEventSnapshot(
            identifier: identifier,
            calendarId: calendarId,
            title: title,
            startDate: start,
            endDate: end,
            notes: notes
        )
        lock.withLock { events[identifier] = snapshot }
        return snapshot
    }

    func authorizationStatus() -> CalendarAuthorization { lock.withLock { status } }

    func requestAccess() async -> CalendarAuthorization {
        lock.withLock {
            accessRequestCount += 1
            status = accessAnswer
            return status
        }
    }

    func writableCalendars() -> [CalendarDescriptor] { lock.withLock { calendars } }

    func event(identifier: String) -> CalendarEventSnapshot? {
        lock.withLock { events[identifier] }
    }

    func createEvent(in calendarId: String, title: String, start: Date, end: Date, notes: String) -> String? {
        lock.withLock {
            guard calendars.contains(where: { $0.id == calendarId && $0.isWritable }) else { return nil }
            let identifier = "event-\(events.count + 1)-\(UUID().uuidString.prefix(4))"
            events[identifier] = CalendarEventSnapshot(
                identifier: identifier,
                calendarId: calendarId,
                title: title,
                startDate: start,
                endDate: end,
                notes: notes
            )
            return identifier
        }
    }

    func updateEvent(identifier: String, title: String, start: Date, end: Date, notes: String) -> Bool {
        lock.withLock {
            guard var event = events[identifier] else { return false }
            event.title = title
            event.startDate = start
            event.endDate = end
            event.notes = notes
            events[identifier] = event
            return true
        }
    }

    func removeEvent(identifier: String) -> Bool {
        lock.withLock { events.removeValue(forKey: identifier) != nil }
    }
}
