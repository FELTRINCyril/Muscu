import Foundation
import SwiftData
import MuscuEngine

/// Recurrence hebdomadaire attachee a un programme, avec ses rappels.
///
/// Une seule entite porte la recurrence ET les rappels : les deux decrivent
/// le meme engagement (« je m'entraine tel jour a telle heure ») et les
/// separer obligerait a les tenir synchronises a la main.
@Model
final class PlanningSchedule {
    @Attribute(.unique) var id: UUID = UUID()
    var programId: UUID?
    var name: String = ""
    var isEnabled: Bool = true

    /// Jours de semaine, convention `Calendar` (1 = dimanche). Encode en JSON.
    var weekdaysData: Data?
    var startDate: Date = Date()
    var endDate: Date?
    /// Rangs de semaines mises en pause, encodes en JSON.
    var pausedWeekOffsetsData: Data?
    var hour: Int = 18
    var minute: Int = 0
    var placeId: UUID?

    // MARK: - Rappels

    var remindersEnabled: Bool = false
    var reminderLeadMinutes: Int = 60
    /// Heure du rappel « le jour même ». `nil` = rappel desactive.
    var reminderDayOfHour: Int?
    var reminderDayOfMinute: Int?
    var reminderComebackAfterDays: Int = 0
    var reminderSoundEnabled: Bool = true

    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        programId: UUID? = nil,
        name: String = "",
        isEnabled: Bool = true,
        weekdaysData: Data? = nil,
        startDate: Date = Date(),
        endDate: Date? = nil,
        pausedWeekOffsetsData: Data? = nil,
        hour: Int = 18,
        minute: Int = 0,
        placeId: UUID? = nil,
        remindersEnabled: Bool = false,
        reminderLeadMinutes: Int = 60,
        reminderDayOfHour: Int? = nil,
        reminderDayOfMinute: Int? = nil,
        reminderComebackAfterDays: Int = 0,
        reminderSoundEnabled: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.programId = programId
        self.name = name
        self.isEnabled = isEnabled
        self.weekdaysData = weekdaysData
        self.startDate = startDate
        self.endDate = endDate
        self.pausedWeekOffsetsData = pausedWeekOffsetsData
        self.hour = hour
        self.minute = minute
        self.placeId = placeId
        self.remindersEnabled = remindersEnabled
        self.reminderLeadMinutes = reminderLeadMinutes
        self.reminderDayOfHour = reminderDayOfHour
        self.reminderDayOfMinute = reminderDayOfMinute
        self.reminderComebackAfterDays = reminderComebackAfterDays
        self.reminderSoundEnabled = reminderSoundEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

extension PlanningSchedule {
    var weekdays: Set<Int> {
        get {
            guard let weekdaysData,
                  let values = try? JSONDecoder().decode([Int].self, from: weekdaysData) else { return [] }
            return Set(values)
        }
        set { weekdaysData = try? JSONEncoder().encode(newValue.sorted()) }
    }

    var pausedWeekOffsets: Set<Int> {
        get {
            guard let pausedWeekOffsetsData,
                  let values = try? JSONDecoder().decode([Int].self, from: pausedWeekOffsetsData) else { return [] }
            return Set(values)
        }
        set { pausedWeekOffsetsData = try? JSONEncoder().encode(newValue.sorted()) }
    }

    var timeOfDay: TimeOfDay {
        get { TimeOfDay(hour: hour, minute: minute) }
        set { hour = newValue.hour; minute = newValue.minute }
    }

    var recurrence: WeeklyRecurrence {
        WeeklyRecurrence(
            weekdays: weekdays,
            startDate: startDate,
            endDate: endDate,
            pausedWeekOffsets: pausedWeekOffsets,
            timeOfDay: timeOfDay
        )
    }

    var reminderSettings: ReminderSettings {
        var dayOf: TimeOfDay?
        if let reminderDayOfHour {
            dayOf = TimeOfDay(hour: reminderDayOfHour, minute: reminderDayOfMinute ?? 0)
        }
        return ReminderSettings(
            isEnabled: remindersEnabled,
            leadMinutes: reminderLeadMinutes,
            dayOfTime: dayOf,
            comebackAfterDays: reminderComebackAfterDays,
            isSoundEnabled: reminderSoundEnabled,
            allowedWeekdays: []
        )
    }

    var syncMetadata: SyncMetadata {
        SyncMetadata(identifier: id, createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt)
    }
}

/// Trace d'un rappel programme ou explicitement supprime.
///
/// Sans cette trace, un rappel supprime par l'utilisateur reapparaitrait au
/// lancement suivant, puisque la planification serait recalculee a
/// l'identique. C'est exactement le defaut que le critere d'acceptation
/// interdit.
@Model
final class NotificationRecord {
    @Attribute(.unique) var identifier: String = ""
    var workoutId: UUID?
    var kindRaw: String = ReminderKind.before.rawValue
    var fireDate: Date = Date()
    /// Date de suppression volontaire. Non nil = ne jamais reprogrammer.
    var dismissedAt: Date?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        identifier: String,
        workoutId: UUID? = nil,
        kindRaw: String = ReminderKind.before.rawValue,
        fireDate: Date = Date(),
        dismissedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.identifier = identifier
        self.workoutId = workoutId
        self.kindRaw = kindRaw
        self.fireDate = fireDate
        self.dismissedAt = dismissedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension NotificationRecord {
    var kind: ReminderKind {
        get { ReminderKind(rawValue: kindRaw) ?? .before }
        set { kindRaw = newValue.rawValue }
    }

    var isDismissed: Bool { dismissedAt != nil }
}

/// Lien vers un evenement de l'app Calendrier CREE PAR MUSCU.
///
/// Seuls les evenements enregistres ici sont modifies ou supprimes : un
/// evenement externe n'est jamais touche, meme s'il porte le meme titre a la
/// meme heure.
@Model
final class CalendarLink {
    @Attribute(.unique) var id: UUID = UUID()
    var scheduledWorkoutId: UUID = UUID()
    var eventIdentifier: String = ""
    var calendarIdentifier: String = ""
    var exportedAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        scheduledWorkoutId: UUID,
        eventIdentifier: String,
        calendarIdentifier: String,
        exportedAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.scheduledWorkoutId = scheduledWorkoutId
        self.eventIdentifier = eventIdentifier
        self.calendarIdentifier = calendarIdentifier
        self.exportedAt = exportedAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}
