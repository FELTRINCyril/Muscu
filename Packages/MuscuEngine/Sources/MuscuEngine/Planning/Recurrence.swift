import Foundation

/// Heure de la journee, independante d'un fuseau : une seance prevue a 18 h 30
/// reste a 18 h 30 apres un changement d'heure ou de fuseau. C'est
/// l'INSTANT qui bouge, pas l'heure affichee.
public struct TimeOfDay: Codable, Hashable, Sendable, Comparable {
    public let hour: Int
    public let minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }

    public var minutesFromMidnight: Int { hour * 60 + minute }

    public static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        lhs.minutesFromMidnight < rhs.minutesFromMidnight
    }
}

/// Recurrence hebdomadaire : des jours de semaine, une plage de dates et des
/// semaines de pause.
///
/// Les jours suivent la convention `Calendar.component(.weekday)` : 1 =
/// dimanche ... 7 = samedi. Un `Calendar` explicite porte le fuseau, donc les
/// tests peuvent rejouer un changement d'heure sans toucher a l'appareil.
public struct WeeklyRecurrence: Codable, Hashable, Sendable {
    /// Jours retenus. Un ensemble vide ne produit aucune occurrence : on ne
    /// devine jamais un jour par defaut.
    public let weekdays: Set<Int>
    public let startDate: Date
    /// Derniere date incluse. `nil` = recurrence ouverte.
    public let endDate: Date?
    /// Semaines sautees, comptees depuis la semaine de `startDate` (0 =
    /// premiere semaine). Une semaine de pause ne decale pas les suivantes.
    public let pausedWeekOffsets: Set<Int>
    public let timeOfDay: TimeOfDay

    public init(
        weekdays: Set<Int>,
        startDate: Date,
        endDate: Date? = nil,
        pausedWeekOffsets: Set<Int> = [],
        timeOfDay: TimeOfDay = TimeOfDay(hour: 18, minute: 0)
    ) {
        self.weekdays = weekdays.filter { (1...7).contains($0) }
        self.startDate = startDate
        self.endDate = endDate
        self.pausedWeekOffsets = pausedWeekOffsets
        self.timeOfDay = timeOfDay
    }

    public var isValid: Bool {
        guard !weekdays.isEmpty else { return false }
        if let endDate { return endDate >= startDate }
        return true
    }
}

/// Une occurrence datee produite par une recurrence.
public struct RecurrenceOccurrence: Hashable, Sendable {
    public let date: Date
    /// Rang de la semaine depuis le debut, 0-base. Sert a relier une
    /// occurrence a une semaine de plan.
    public let weekOffset: Int
    public let weekday: Int

    public init(date: Date, weekOffset: Int, weekday: Int) {
        self.date = date
        self.weekOffset = weekOffset
        self.weekday = weekday
    }
}

public enum RecurrenceExpander {
    /// Developpe la recurrence en dates concretes.
    ///
    /// L'iteration avance JOUR PAR JOUR avec le calendrier, puis pose l'heure
    /// voulue : ajouter 86 400 secondes serait faux lors d'un changement
    /// d'heure, ou l'heure locale decale d'une heure. Le resultat est trie et
    /// borne par `limit` pour qu'une recurrence ouverte reste finie.
    public static func occurrences(
        of recurrence: WeeklyRecurrence,
        calendar: Calendar,
        limit: Int = 260,
        until horizon: Date? = nil
    ) -> [RecurrenceOccurrence] {
        guard recurrence.isValid, limit > 0 else { return [] }

        let firstDay = calendar.startOfDay(for: recurrence.startDate)
        // Debut de la semaine calendaire contenant le premier jour : le rang
        // de semaine doit suivre les SEMAINES du calendrier, sinon une
        // recurrence demarree un jeudi ferait basculer sa « semaine 1 » en
        // plein milieu de la suivante.
        let weekStart = startOfWeek(for: firstDay, calendar: calendar)
        let hardStop = earliest(recurrence.endDate, horizon)

        var results: [RecurrenceOccurrence] = []
        var cursor = firstDay
        var guardCounter = 0
        let maximumDays = limit * 7 + 14

        while results.count < limit, guardCounter < maximumDays {
            guardCounter += 1
            defer { cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor.addingTimeInterval(86_400) }

            if let hardStop, cursor > calendar.startOfDay(for: hardStop) { break }

            let weekday = calendar.component(.weekday, from: cursor)
            guard recurrence.weekdays.contains(weekday) else { continue }

            let offset = weekOffset(from: weekStart, to: cursor, calendar: calendar)
            guard !recurrence.pausedWeekOffsets.contains(offset) else { continue }

            guard let moment = calendar.date(
                bySettingHour: recurrence.timeOfDay.hour,
                minute: recurrence.timeOfDay.minute,
                second: 0,
                of: cursor
            ) else { continue }

            if moment < recurrence.startDate { continue }
            if let end = recurrence.endDate, moment > end { break }
            if let horizon, moment > horizon { break }

            results.append(RecurrenceOccurrence(date: moment, weekOffset: offset, weekday: weekday))
        }

        return results
    }

    private static func earliest(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case let (left?, right?): return min(left, right)
        case let (left?, nil): return left
        case let (nil, right?): return right
        case (nil, nil): return nil
        }
    }

    public static func startOfWeek(for date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    static func weekOffset(from weekStart: Date, to date: Date, calendar: Calendar) -> Int {
        let target = startOfWeek(for: date, calendar: calendar)
        return calendar.dateComponents([.weekOfYear], from: weekStart, to: target).weekOfYear ?? 0
    }
}
