import Foundation

/// Agregation d'une semaine calendaire.
public struct WeeklySummary: Equatable, Sendable {
    /// Debut de la semaine, dans le calendrier fourni.
    public var weekStart: Date
    public var sessionCount: Int
    public var workingSetCount: Int
    public var hardSetCount: Int
    /// Series de travail sans effort declare : elles ne peuvent etre ni
    /// comptees comme difficiles, ni comme faciles.
    public var setsWithoutDeclaredEffort: Int
    public var totalReps: Int
    public var tonnage: MeasuredTotal
    public var durationSeconds: Int
    /// Series de travail par muscle principal.
    public var setsByMuscle: [String: Int]
    /// Series DIFFICILES par muscle principal.
    public var hardSetsByMuscle: [String: Int]

    public init(
        weekStart: Date,
        sessionCount: Int = 0,
        workingSetCount: Int = 0,
        hardSetCount: Int = 0,
        setsWithoutDeclaredEffort: Int = 0,
        totalReps: Int = 0,
        tonnage: MeasuredTotal = .zero,
        durationSeconds: Int = 0,
        setsByMuscle: [String: Int] = [:],
        hardSetsByMuscle: [String: Int] = [:]
    ) {
        self.weekStart = weekStart
        self.sessionCount = sessionCount
        self.workingSetCount = workingSetCount
        self.hardSetCount = hardSetCount
        self.setsWithoutDeclaredEffort = setsWithoutDeclaredEffort
        self.totalReps = totalReps
        self.tonnage = tonnage
        self.durationSeconds = durationSeconds
        self.setsByMuscle = setsByMuscle
        self.hardSetsByMuscle = hardSetsByMuscle
    }

    /// Densite de travail : tonnage par minute d'entrainement. `nil` quand la
    /// duree est inconnue ou le tonnage incomplet — jamais zero par defaut.
    public var workDensity: Double? {
        guard durationSeconds > 0, tonnage.isComplete, tonnage.value > 0 else { return nil }
        return tonnage.value / (Double(durationSeconds) / 60)
    }
}

/// Un point d'une serie temporelle, avec sa date.
public struct AnalyticsPoint: Equatable, Sendable {
    public var date: Date
    public var value: Double

    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

/// Indicateur suivi pour un exercice donne.
public enum ExerciseMetric: String, CaseIterable, Sendable {
    /// 1RM estime (Epley) sur les series eligibles. C'est une ESTIMATION.
    case estimatedOneRepMax
    /// Charge effective maximale reellement portee.
    case maxLoad
    /// Repetitions maximales sur une serie.
    case maxReps
    /// Tonnage de la seance pour cet exercice.
    case tonnage

    public var unitSymbol: String {
        switch self {
        case .estimatedOneRepMax, .maxLoad, .tonnage: return "kg"
        case .maxReps: return ""
        }
    }

    /// Formule a afficher a cote du graphique, pour que l'utilisateur sache
    /// ce qu'il regarde.
    public var formulaDescription: String {
        switch self {
        case .estimatedOneRepMax:
            return "1RM estimé (Epley : charge × (1 + répétitions ⁄ 30)), sur les séries de 1 à 12 répétitions portant une charge réelle."
        case .maxLoad:
            return "Charge effective la plus lourde : poids soulevé, ou poids de corps ± lest/assistance."
        case .maxReps:
            return "Nombre de répétitions le plus élevé sur une série de travail."
        case .tonnage:
            return "Tonnage : somme de charge effective × répétitions sur les séries de travail."
        }
    }
}

/// Ecart de volume entre muscles, par rapport a la mediane observee.
public struct ImbalanceFinding: Equatable, Sendable {
    public var muscle: String
    public var weeklySets: Int
    public var medianWeeklySets: Double
    /// Ecart relatif a la mediane (-0,6 = 60 % en dessous).
    public var relativeGap: Double
    public var isUnderworked: Bool
}

/// Adherence au planning sur une periode.
public struct AdherenceSummary: Equatable, Sendable {
    public var plannedCount: Int
    public var completedCount: Int
    /// `nil` quand rien n'etait planifie : l'adherence n'a alors aucun sens,
    /// et surtout ne vaut pas 0 %.
    public var ratio: Double? {
        guard plannedCount > 0 else { return nil }
        return Double(completedCount) / Double(plannedCount)
    }

    public init(plannedCount: Int, completedCount: Int) {
        self.plannedCount = plannedCount
        self.completedCount = completedCount
    }
}

/// Comparaison de deux periodes (par exemple deux blocs).
public struct PeriodComparison: Equatable, Sendable {
    public var previous: WeeklySummary
    public var current: WeeklySummary
    public var tonnageChange: Double?
    public var hardSetChange: Double?

    /// Enonce factuel, sans causalite : « +12 % de tonnage », jamais
    /// « tu progresses grace a X ».
    public var summaryText: String
}

/// Toutes les agregations d'entrainement, en un seul endroit.
///
/// Deux ecrans qui affichent le meme indicateur doivent appeler la meme
/// fonction ici : c'est ce qui garantit qu'ils affichent la meme valeur.
/// Les formules de charge viennent de `SetMetrics`, jamais recalculees.
public enum TrainingAnalytics {
    /// Une serie est « difficile » a partir de ce nombre de repetitions en
    /// reserve (2 RIR ou moins).
    public static let hardSetRepsInReserveThreshold = 2

    /// En dessous de cette part de la mediane, un muscle est signale comme
    /// sous-travaille.
    public static let defaultImbalanceThreshold = 0.5

    /// Calendrier de reference des agregations : semaine au lundi. Le fuseau
    /// est celui fourni par l'appelant, car une semaine « du lundi » depend
    /// du lieu de vie de l'utilisateur, pas d'une convention serveur.
    public static func calendar(timeZone: TimeZone = .current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = timeZone
        return calendar
    }

    // MARK: - Semaines

    /// Resume par semaine calendaire, de la plus ancienne a la plus recente.
    /// Les semaines SANS seance ne sont pas inventees ici : voir
    /// `filled(weeks:from:to:calendar:)` quand un graphique a besoin d'une
    /// continuite temporelle.
    public static func weeklySummaries(
        sessions: [AnalyticsSession],
        calendar: Calendar = TrainingAnalytics.calendar()
    ) -> [WeeklySummary] {
        let grouped = Dictionary(grouping: sessions) { startOfWeek(for: $0.date, calendar: calendar) }
        return grouped.keys.sorted().map { weekStart in
            summary(weekStart: weekStart, sessions: grouped[weekStart] ?? [])
        }
    }

    /// Complete une suite de semaines avec les semaines vides intermediaires,
    /// pour qu'un graphique ne laisse pas croire a une continuite inexistante.
    public static func filled(
        weeks: [WeeklySummary],
        calendar: Calendar = TrainingAnalytics.calendar()
    ) -> [WeeklySummary] {
        guard let first = weeks.first, let last = weeks.last, weeks.count > 1 else { return weeks }
        var result: [WeeklySummary] = []
        var cursor = first.weekStart
        let byStart = Dictionary(weeks.map { ($0.weekStart, $0) }, uniquingKeysWith: { first, _ in first })
        var guardCounter = 0
        while cursor <= last.weekStart, guardCounter < 1_000 {
            guardCounter += 1
            result.append(byStart[cursor] ?? WeeklySummary(weekStart: cursor))
            guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    static func summary(weekStart: Date, sessions: [AnalyticsSession]) -> WeeklySummary {
        var summary = WeeklySummary(weekStart: weekStart, sessionCount: sessions.count)
        var tonnage = MeasuredTotal.zero

        for session in sessions {
            summary.durationSeconds += max(0, session.durationSeconds)
            for set in session.workingSets {
                summary.workingSetCount += 1
                summary.totalReps += max(0, set.metrics.reps)
                if set.isHardSet { summary.hardSetCount += 1 }
                if !set.hasDeclaredEffort { summary.setsWithoutDeclaredEffort += 1 }

                if let value = SetMetrics.tonnage(set.metrics) {
                    tonnage = tonnage + MeasuredTotal(value: value)
                } else if set.metrics.reps > 0 {
                    tonnage = tonnage + MeasuredTotal(value: 0, unknownSets: 1)
                }

                for muscle in set.primaryMuscles {
                    summary.setsByMuscle[muscle, default: 0] += 1
                    if set.isHardSet { summary.hardSetsByMuscle[muscle, default: 0] += 1 }
                }
            }
        }
        summary.tonnage = tonnage
        return summary
    }

    public static func startOfWeek(for date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    // MARK: - Séries par exercice

    /// Suite temporelle d'un indicateur pour un exercice. Une seance sans
    /// valeur exploitable est ABSENTE de la suite, jamais representee par 0.
    public static func series(
        metric: ExerciseMetric,
        exerciseId: String,
        sessions: [AnalyticsSession]
    ) -> [AnalyticsPoint] {
        sessions
            .sorted { $0.date < $1.date }
            .compactMap { session in
                let sets = session.workingSets.filter { $0.exerciseId == exerciseId }
                guard !sets.isEmpty else { return nil }
                guard let value = value(of: metric, for: sets) else { return nil }
                return AnalyticsPoint(date: session.date, value: value)
            }
    }

    private static func value(of metric: ExerciseMetric, for sets: [AnalyticsSet]) -> Double? {
        switch metric {
        case .estimatedOneRepMax:
            return sets.compactMap { SetMetrics.estimatedOneRepMax($0.metrics) }.max()
        case .maxLoad:
            return sets.compactMap { set -> Double? in
                guard SetMetrics.allowsLoadRecord(set.metrics) else { return nil }
                return SetMetrics.effectiveLoad(set.metrics)
            }.max()
        case .maxReps:
            let reps = sets.map(\.metrics.reps).max() ?? 0
            return reps > 0 ? Double(reps) : nil
        case .tonnage:
            let values = sets.compactMap { SetMetrics.tonnage($0.metrics) }
            return values.isEmpty ? nil : values.reduce(0, +)
        }
    }

    /// Indicateurs reellement exploitables pour un exercice : inutile de
    /// proposer un 1RM estime sur un exercice au poids du corps.
    public static func availableMetrics(exerciseId: String, sessions: [AnalyticsSession]) -> [ExerciseMetric] {
        ExerciseMetric.allCases.filter { !series(metric: $0, exerciseId: exerciseId, sessions: sessions).isEmpty }
    }

    // MARK: - Fréquence et régularité

    /// Nombre de seances par semaine, semaines vides comprises.
    public static func sessionsPerWeek(
        sessions: [AnalyticsSession],
        calendar: Calendar = TrainingAnalytics.calendar()
    ) -> [AnalyticsPoint] {
        filled(weeks: weeklySummaries(sessions: sessions, calendar: calendar), calendar: calendar)
            .map { AnalyticsPoint(date: $0.weekStart, value: Double($0.sessionCount)) }
    }

    /// Nombre de semaines consecutives, en terminant par la plus recente,
    /// comportant au moins une seance.
    public static func currentWeeklyStreak(
        sessions: [AnalyticsSession],
        now: Date,
        calendar: Calendar = TrainingAnalytics.calendar()
    ) -> Int {
        let weeksWithSessions = Set(
            weeklySummaries(sessions: sessions, calendar: calendar)
                .filter { $0.sessionCount > 0 }
                .map(\.weekStart)
        )
        guard !weeksWithSessions.isEmpty else { return 0 }

        var streak = 0
        var cursor = startOfWeek(for: now, calendar: calendar)
        // La semaine en cours ne casse pas une serie tant qu'elle n'est pas
        // terminee : si elle est vide, on repart de la precedente.
        if !weeksWithSessions.contains(cursor) {
            guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) else { return 0 }
            cursor = previous
        }
        while weeksWithSessions.contains(cursor), streak < 1_000 {
            streak += 1
            guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    /// Nombre de seances par jour, pour un calendrier de chaleur.
    public static func sessionsPerDay(
        sessions: [AnalyticsSession],
        calendar: Calendar = TrainingAnalytics.calendar()
    ) -> [Date: Int] {
        Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.date) }
            .mapValues(\.count)
    }

    /// Adherence : seances realisees rapportees aux seances planifiees.
    public static func adherence(plannedCount: Int, completedCount: Int) -> AdherenceSummary {
        AdherenceSummary(plannedCount: max(0, plannedCount), completedCount: max(0, completedCount))
    }

    // MARK: - Répartition et déséquilibres

    /// Series de travail par muscle sur toute la periode fournie.
    public static func setsByMuscle(sessions: [AnalyticsSession]) -> [String: Int] {
        var result: [String: Int] = [:]
        for session in sessions {
            for set in session.workingSets {
                for muscle in set.primaryMuscles {
                    result[muscle, default: 0] += 1
                }
            }
        }
        return result
    }

    /// Muscles nettement en dessous de la mediane des muscles travailles.
    ///
    /// Purement descriptif : c'est un ecart de volume observe, pas un
    /// jugement sur la qualite du programme.
    public static func imbalances(
        weeklySetsByMuscle: [String: Int],
        threshold: Double = defaultImbalanceThreshold,
        minimumTrackedMuscles: Int = 3
    ) -> [ImbalanceFinding] {
        let values = weeklySetsByMuscle.values.map(Double.init).sorted()
        guard values.count >= minimumTrackedMuscles else { return [] }
        let median = values.count.isMultiple(of: 2)
            ? (values[values.count / 2 - 1] + values[values.count / 2]) / 2
            : values[values.count / 2]
        guard median > 0 else { return [] }

        return weeklySetsByMuscle
            .map { muscle, sets -> ImbalanceFinding in
                let gap = (Double(sets) - median) / median
                return ImbalanceFinding(
                    muscle: muscle,
                    weeklySets: sets,
                    medianWeeklySets: median,
                    relativeGap: gap,
                    isUnderworked: Double(sets) < median * threshold
                )
            }
            .filter(\.isUnderworked)
            .sorted { ($0.relativeGap, $0.muscle) < ($1.relativeGap, $1.muscle) }
    }

    // MARK: - Comparaison de périodes

    /// Compare deux periodes deja agregees. Les variations ne sont calculees
    /// que lorsque la valeur de reference est exploitable.
    public static func compare(previous: WeeklySummary, current: WeeklySummary) -> PeriodComparison {
        let tonnageChange: Double? = {
            guard previous.tonnage.isComplete, current.tonnage.isComplete, previous.tonnage.value > 0 else { return nil }
            return (current.tonnage.value - previous.tonnage.value) / previous.tonnage.value
        }()
        let hardSetChange: Double? = {
            guard previous.hardSetCount > 0 else { return nil }
            return Double(current.hardSetCount - previous.hardSetCount) / Double(previous.hardSetCount)
        }()

        var parts: [String] = []
        if let tonnageChange {
            parts.append("tonnage \(signedPercent(tonnageChange))")
        } else {
            parts.append("tonnage non comparable")
        }
        if let hardSetChange {
            parts.append("séries difficiles \(signedPercent(hardSetChange))")
        }
        parts.append("\(current.sessionCount) séance(s) contre \(previous.sessionCount)")

        return PeriodComparison(
            previous: previous,
            current: current,
            tonnageChange: tonnageChange,
            hardSetChange: hardSetChange,
            summaryText: parts.joined(separator: ", ") + "."
        )
    }

    /// Agrege plusieurs semaines en un seul resume, pour comparer des blocs.
    public static func merged(_ weeks: [WeeklySummary]) -> WeeklySummary {
        guard let first = weeks.min(by: { $0.weekStart < $1.weekStart }) else {
            return WeeklySummary(weekStart: Date(timeIntervalSince1970: 0))
        }
        var result = WeeklySummary(weekStart: first.weekStart)
        for week in weeks {
            result.sessionCount += week.sessionCount
            result.workingSetCount += week.workingSetCount
            result.hardSetCount += week.hardSetCount
            result.setsWithoutDeclaredEffort += week.setsWithoutDeclaredEffort
            result.totalReps += week.totalReps
            result.tonnage = result.tonnage + week.tonnage
            result.durationSeconds += week.durationSeconds
            for (muscle, sets) in week.setsByMuscle { result.setsByMuscle[muscle, default: 0] += sets }
            for (muscle, sets) in week.hardSetsByMuscle { result.hardSetsByMuscle[muscle, default: 0] += sets }
        }
        return result
    }

    private static func signedPercent(_ value: Double) -> String {
        let percent = Int((value * 100).rounded())
        return percent >= 0 ? "+\(percent) %" : "\(percent) %"
    }
}
