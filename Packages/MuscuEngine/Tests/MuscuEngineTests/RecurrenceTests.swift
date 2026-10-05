import Foundation
import Testing
@testable import MuscuEngine

private func parisCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    calendar.locale = Locale(identifier: "fr_FR")
    return calendar
}

private func date(_ string: String, in calendar: Calendar) -> Date {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    return formatter.date(from: string)!
}

@Suite("Récurrence hebdomadaire")
struct RecurrenceTests {
    @Test("Les jours choisis sont les seuls produits")
    func onlySelectedWeekdays() {
        let calendar = parisCalendar()
        // 2 = lundi, 5 = jeudi.
        let recurrence = WeeklyRecurrence(
            weekdays: [2, 5],
            startDate: date("2026-01-05 00:00", in: calendar),
            endDate: date("2026-01-18 23:59", in: calendar),
            timeOfDay: TimeOfDay(hour: 18, minute: 30)
        )

        let occurrences = RecurrenceExpander.occurrences(of: recurrence, calendar: calendar)

        #expect(occurrences.count == 4)
        #expect(occurrences.allSatisfy { [2, 5].contains($0.weekday) })
        #expect(occurrences.allSatisfy { calendar.component(.hour, from: $0.date) == 18 })
        #expect(occurrences.allSatisfy { calendar.component(.minute, from: $0.date) == 30 })
    }

    @Test("Une récurrence sans jour ne produit rien")
    func emptyWeekdaysProducesNothing() {
        let calendar = parisCalendar()
        let recurrence = WeeklyRecurrence(weekdays: [], startDate: date("2026-01-05 00:00", in: calendar))
        #expect(RecurrenceExpander.occurrences(of: recurrence, calendar: calendar).isEmpty)
    }

    @Test("Le passage à l'heure d'été garde l'heure locale")
    func daylightSavingKeepsLocalTime() {
        let calendar = parisCalendar()
        // En 2026, la France passe à l'heure d'été le dimanche 29 mars.
        let recurrence = WeeklyRecurrence(
            weekdays: [7], // samedi
            startDate: date("2026-03-21 00:00", in: calendar),
            endDate: date("2026-04-12 23:59", in: calendar),
            timeOfDay: TimeOfDay(hour: 9, minute: 0)
        )

        let occurrences = RecurrenceExpander.occurrences(of: recurrence, calendar: calendar)

        #expect(occurrences.count == 4)
        // Toutes à 9 h locales, de part et d'autre du changement d'heure.
        #expect(occurrences.allSatisfy { calendar.component(.hour, from: $0.date) == 9 })
        // Le changement d'heure a lieu le dimanche 29 mars : l'écart réel
        // entre le samedi 28 et le samedi 4 avril est de 167 heures, pas
        // 168. C'est justement ce qu'un calcul en secondes raterait.
        let beforeChange = occurrences[1].date.timeIntervalSince(occurrences[0].date) / 3600
        let acrossChange = occurrences[2].date.timeIntervalSince(occurrences[1].date) / 3600
        #expect(beforeChange == 168)
        #expect(acrossChange == 167)
    }

    @Test("Les semaines de pause sont sautées sans décaler les suivantes")
    func pausedWeeksAreSkipped() {
        let calendar = parisCalendar()
        let recurrence = WeeklyRecurrence(
            weekdays: [2],
            startDate: date("2026-01-05 00:00", in: calendar),
            endDate: date("2026-02-02 23:59", in: calendar),
            pausedWeekOffsets: [1],
            timeOfDay: TimeOfDay(hour: 12, minute: 0)
        )

        let occurrences = RecurrenceExpander.occurrences(of: recurrence, calendar: calendar)
        let days = occurrences.map { calendar.component(.day, from: $0.date) }

        #expect(days == [5, 19, 26, 2])
        #expect(occurrences.map(\.weekOffset) == [0, 2, 3, 4])
    }

    @Test("Une récurrence ouverte reste bornée par la limite demandée")
    func openEndedRecurrenceIsBounded() {
        let calendar = parisCalendar()
        let recurrence = WeeklyRecurrence(
            weekdays: [2, 4, 6],
            startDate: date("2026-01-05 00:00", in: calendar),
            timeOfDay: TimeOfDay(hour: 7, minute: 15)
        )

        let occurrences = RecurrenceExpander.occurrences(of: recurrence, calendar: calendar, limit: 10)
        #expect(occurrences.count == 10)
    }

    @Test("Le même calendrier dans un autre fuseau donne la même heure locale")
    func otherTimeZoneKeepsLocalTime() {
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!

        let recurrence = WeeklyRecurrence(
            weekdays: [3],
            startDate: date("2026-01-05 00:00", in: tokyo),
            endDate: date("2026-01-31 23:59", in: tokyo),
            timeOfDay: TimeOfDay(hour: 20, minute: 0)
        )

        let occurrences = RecurrenceExpander.occurrences(of: recurrence, calendar: tokyo)
        #expect(!occurrences.isEmpty)
        #expect(occurrences.allSatisfy { tokyo.component(.hour, from: $0.date) == 20 })
    }

    @Test("Une heure hors bornes est ramenée dans la journée")
    func timeOfDayIsClamped() {
        let time = TimeOfDay(hour: 99, minute: -5)
        #expect(time.hour == 23)
        #expect(time.minute == 0)
    }
}
