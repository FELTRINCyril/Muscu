import Foundation

/// Construit un plan pluri-semaines date a partir d'un programme genere et
/// d'une periodisation.
///
/// Entierement deterministe : le meme `PlanGeneratorInput` (profil, dates,
/// jours disponibles) produit toujours exactement le meme plan.
public struct PlanGenerator: Sendable {
    private let generator: RuleBasedGenerator
    private let calendar: Calendar

    public init(catalog: ExerciseCatalog, calendar: Calendar = PlanGenerator.defaultCalendar) {
        self.generator = RuleBasedGenerator(catalog: catalog)
        self.calendar = calendar
    }

    /// Calendrier de reference : semaine demarrant le lundi, fuseau fixe.
    /// Un plan ne doit pas changer selon les reglages regionaux de l'appareil.
    public static var defaultCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    public func generate(_ input: PlanGeneratorInput) throws -> DraftPlan {
        let program = try generator.generate(input.base)
        let plannedWeeks = Periodization.weeks(
            PeriodizationInput(
                totalWeeks: input.totalWeeks,
                style: input.style,
                deloadEveryWeeks: input.deloadEveryWeeks,
                goal: input.base.goal,
                experience: input.base.experience
            )
        )

        let weekdays = resolvedWeekdays(input: input, sessionCount: program.sessions.count)
        let firstWeekStart = startOfWeek(for: input.startDate)

        let weeks = plannedWeeks.map { planned -> DraftPlanWeek in
            let weekStart = calendar.date(byAdding: .weekOfYear, value: planned.number - 1, to: firstWeekStart) ?? firstWeekStart
            let workouts = program.sessions.enumerated().compactMap { index, session -> DraftScheduledWorkout? in
                guard index < weekdays.count else { return nil }
                guard let date = date(weekStart: weekStart, weekday: weekdays[index]) else { return nil }
                return DraftScheduledWorkout(sessionIndex: index, displayName: session.name, date: date)
            }
            return DraftPlanWeek(
                number: planned.number,
                blockRaw: planned.block.rawValue,
                startDate: weekStart,
                volumeMultiplier: planned.volumeMultiplier,
                intensityMultiplier: planned.intensityMultiplier,
                rationale: planned.rationale,
                workouts: workouts
            )
        }

        let volume = Self.weeklySetsByMuscle(program: program, catalog: generator.catalog)
        return DraftPlan(
            name: program.name,
            program: program,
            weeks: weeks,
            weeklySetsByMuscle: volume,
            rationale: Self.rationale(input: input, program: program, weeks: weeks, volume: volume)
        )
    }

    // MARK: - Dates

    /// Jours de la semaine reellement utilises : ceux declares par l'athlete
    /// s'il y en a assez, sinon une repartition automatique qui espace les
    /// seances le plus possible.
    private func resolvedWeekdays(input: PlanGeneratorInput, sessionCount: Int) -> [Int] {
        let declared = input.availableWeekdays.filter { (1...7).contains($0) }.sorted()
        if declared.count >= sessionCount { return Array(declared.prefix(sessionCount)) }
        if !declared.isEmpty {
            // Moins de jours declares que de seances : on reutilise les jours
            // disponibles dans l'ordre plutot que d'inventer des jours que
            // l'athlete a explicitement exclus.
            return (0..<sessionCount).map { declared[$0 % declared.count] }
        }
        return Self.spreadWeekdays(count: sessionCount)
    }

    /// Repartition par defaut, du lundi au dimanche, en espacant les seances.
    static func spreadWeekdays(count: Int) -> [Int] {
        // Convention Calendar : 2 = lundi ... 1 = dimanche.
        let week = [2, 3, 4, 5, 6, 7, 1]
        guard count > 0 else { return [] }
        guard count < week.count else { return Array(week.prefix(count)) }
        let step = Double(week.count) / Double(count)
        return (0..<count).map { week[min(week.count - 1, Int((Double($0) * step).rounded(.down)))] }
    }

    private func startOfWeek(for date: Date) -> Date {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    private func date(weekStart: Date, weekday: Int) -> Date? {
        // `weekStart` est un lundi ; on avance jusqu'au jour vise.
        let startWeekday = calendar.component(.weekday, from: weekStart)
        var offset = weekday - startWeekday
        if offset < 0 { offset += 7 }
        return calendar.date(byAdding: .day, value: offset, to: weekStart)
    }

    // MARK: - Volume

    /// Series de travail hebdomadaires par muscle principal. Sert a la fois
    /// a expliquer le plan et a le valider.
    public static func weeklySetsByMuscle(program: DraftProgram, catalog: ExerciseCatalog) -> [String: Int] {
        var result: [String: Int] = [:]
        for session in program.sessions {
            for exercise in session.exercises {
                let muscles = catalog.exercise(id: exercise.exerciseId)?.primaryMuscles ?? []
                for muscle in muscles {
                    result[muscle, default: 0] += max(0, exercise.sets)
                }
            }
        }
        return result
    }

    // MARK: - Explications

    private static func rationale(
        input: PlanGeneratorInput,
        program: DraftProgram,
        weeks: [DraftPlanWeek],
        volume: [String: Int]
    ) -> [String] {
        var lines: [String] = []
        lines.append("\(program.sessions.count) séances par semaine, réparties sur \(weeks.count) semaines.")

        let deloads = weeks.filter(\.isDeload)
        if deloads.isEmpty {
            lines.append("Aucune semaine de décharge : le volume reste constant sur tout le plan.")
        } else {
            let numbers = deloads.map { String($0.number) }.joined(separator: ", ")
            lines.append("Décharge en semaine \(numbers) : le volume y est réduit de moitié.")
        }

        switch input.style {
        case .linear:
            lines.append("Périodisation linéaire : le volume monte d'abord, puis l'intensité prend le relais.")
        case .undulating:
            lines.append("Périodisation ondulatoire : les semaines volume et intensité alternent.")
        case .flat:
            lines.append("Toutes les semaines sont identiques, hors décharge.")
        }

        let topMuscles = volume.sorted { ($0.value, $0.key) > ($1.value, $1.key) }.prefix(3)
        if !topMuscles.isEmpty {
            let text = topMuscles.map { "\(FrenchLabels.muscle($0.key)) \($0.value) séries" }.joined(separator: ", ")
            lines.append("Volume hebdomadaire le plus élevé : \(text).")
        }

        if !input.base.priorityMuscles.isEmpty {
            let names = input.base.priorityMuscles.map(FrenchLabels.muscle).joined(separator: ", ")
            lines.append("Muscles prioritaires renforcés : \(names).")
        }
        if !input.base.avoidAreas.isEmpty {
            let names = input.base.avoidAreas.joined(separator: ", ")
            lines.append("Zones à ménager exclues de la sélection : \(names). Ce filtrage n'est pas un avis médical.")
        }
        return lines
    }
}
