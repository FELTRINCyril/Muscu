import Foundation

/// Sens d'une evolution, avec une zone neutre : une variation de 0,3 % n'est
/// ni une hausse ni une baisse, c'est du bruit de mesure.
public enum StrengthTrend: String, Equatable, Sendable {
    case up
    case down
    case stable

    public var symbol: String {
        switch self {
        case .up: return "↑"
        case .down: return "↓"
        case .stable: return "="
        }
    }
}

/// Exercice designe par son identifiant et son nom affiche.
public struct NamedExercise: Equatable, Hashable, Sendable {
    public var exerciseId: String
    public var displayName: String

    public init(exerciseId: String, displayName: String) {
        self.exerciseId = exerciseId
        self.displayName = displayName
    }
}

/// Indice de force : somme des meilleurs 1RM ESTIMES des exercices
/// principaux sur une periode.
public struct StrengthIndex: Equatable, Sendable {
    public struct Contribution: Equatable, Sendable {
        public var exerciseId: String
        public var displayName: String
        /// Meilleur 1RM estime de la periode, en kg.
        public var bestEstimatedOneRepMax: Double
    }

    /// Somme des contributions, en kg. `nil` quand aucun exercice principal
    /// n'a de 1RM estimable sur la periode — ce n'est pas un indice de 0.
    public var value: Double?
    public var contributions: [Contribution]
    /// Exercices principaux SANS 1RM estimable sur la periode (poids du corps
    /// inconnu, series trop longues, exercice non pratique) : exclus de la
    /// somme, et annonces comme tels.
    public var excluded: [NamedExercise]
    /// Meme somme sur la periode precedente, limitee aux exercices presents
    /// dans les DEUX periodes. `nil` sans periode precedente comparable.
    public var previousComparableValue: Double?
    /// Somme actuelle sur ces memes exercices communs.
    public var currentComparableValue: Double?
    /// Variation relative (0,05 = +5 %). `nil` si non comparable.
    public var relativeChange: Double?
    public var trend: StrengthTrend?

    /// Indice sans periode analysable (aucune seance).
    public static let unavailable = StrengthIndex(value: nil, contributions: [], excluded: [])
}

/// Une ligne de la carte « Records du mois » : meilleure charge de la
/// periode rapportee au record historique de l'exercice.
public struct PeriodRecordEntry: Equatable, Sendable {
    public var exerciseId: String
    public var displayName: String
    /// Meilleure charge effective de la periode, en kg.
    public var periodBest: Double
    /// Meilleure charge effective de tout l'historique (periode comprise).
    public var allTimeBest: Double
    /// Meilleure charge AVANT la periode. `nil` = exercice nouveau.
    public var previousBest: Double?
    public var achievedAt: Date

    /// Record battu pendant la periode : strictement au-dessus de tout ce
    /// qui precede. Un premier essai n'est pas un record — il n'y avait rien
    /// a battre.
    public var isNewRecord: Bool {
        guard let previousBest else { return false }
        return periodBest > previousBest + RecordRevision.tolerance
    }

    /// Part du record historique atteinte pendant la periode, de 0 a 1.
    public var ratioToRecord: Double {
        allTimeBest > 0 ? min(1, periodBest / allTimeBest) : 0
    }
}

/// Cartes du tableau de bord « Indice de force » et « Records du mois ».
/// Inspire de `ProgressDashboardViewModel` d'UpLift (MIT), recalcule en kg
/// avec les regles de `SetMetrics` (1RM eligible, charge reellement portee).
public enum StrengthDashboard {
    /// En dessous de cette variation relative, la tendance est « stable ».
    public static let trendThreshold = 0.01
    /// Nombre d'exercices principaux retenus pour l'indice.
    public static let mainExerciseCount = 5

    /// Exercices principaux : ceux qui ont un 1RM estimable le plus souvent
    /// (nombre de seances) sur l'ensemble des seances fournies. Departage par
    /// nom pour un ordre stable.
    public static func mainExercises(
        sessions: [AnalyticsSession],
        limit: Int = mainExerciseCount
    ) -> [NamedExercise] {
        var sessionCounts: [String: Int] = [:]
        var names: [String: String] = [:]
        for session in sessions {
            var counted: Set<String> = []
            for set in session.workingSets where SetMetrics.isEligibleForOneRepMax(set.metrics) {
                names[set.exerciseId] = set.displayName
                if counted.insert(set.exerciseId).inserted {
                    sessionCounts[set.exerciseId, default: 0] += 1
                }
            }
        }
        return sessionCounts
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return (names[lhs.key] ?? lhs.key).localizedStandardCompare(names[rhs.key] ?? rhs.key) == .orderedAscending
            }
            .prefix(max(0, limit))
            .map { NamedExercise(exerciseId: $0.key, displayName: names[$0.key] ?? $0.key) }
    }

    /// Indice de force sur `period`, compare a `previousPeriod`.
    ///
    /// - Parameters:
    ///   - main: exercices principaux (voir `mainExercises`).
    ///   - sessions: historique (toutes periodes confondues).
    public static func strengthIndex(
        main: [NamedExercise],
        sessions: [AnalyticsSession],
        period: DateInterval,
        previousPeriod: DateInterval?
    ) -> StrengthIndex {
        let current = bestEstimatedOneRepMax(sessions: sessions, in: period)
        let previous = previousPeriod.map { bestEstimatedOneRepMax(sessions: sessions, in: $0) }

        var contributions: [StrengthIndex.Contribution] = []
        var excluded: [NamedExercise] = []
        for exercise in main {
            if let best = current[exercise.exerciseId] {
                contributions.append(.init(
                    exerciseId: exercise.exerciseId,
                    displayName: exercise.displayName,
                    bestEstimatedOneRepMax: best
                ))
            } else {
                excluded.append(exercise)
            }
        }

        let value = contributions.isEmpty ? nil : contributions.reduce(0) { $0 + $1.bestEstimatedOneRepMax }

        var previousComparable: Double?
        var currentComparable: Double?
        if let previous {
            let common = contributions.filter { previous[$0.exerciseId] != nil }
            if !common.isEmpty {
                currentComparable = common.reduce(0) { $0 + $1.bestEstimatedOneRepMax }
                previousComparable = common.reduce(0) { $0 + (previous[$1.exerciseId] ?? 0) }
            }
        }

        var change: Double?
        var trend: StrengthTrend?
        if let previousComparable, let currentComparable, previousComparable > 0 {
            let relative = (currentComparable - previousComparable) / previousComparable
            change = relative
            trend = Self.trend(for: relative)
        }

        return StrengthIndex(
            value: value,
            contributions: contributions,
            excluded: excluded,
            previousComparableValue: previousComparable,
            currentComparableValue: currentComparable,
            relativeChange: change,
            trend: trend
        )
    }

    /// Tendance d'une variation relative, avec la zone neutre de ±1 %.
    public static func trend(for relativeChange: Double) -> StrengthTrend {
        if relativeChange >= trendThreshold { return .up }
        if relativeChange <= -trendThreshold { return .down }
        return .stable
    }

    /// Meilleur 1RM estime par exercice, sur les seances de l'intervalle.
    public static func bestEstimatedOneRepMax(sessions: [AnalyticsSession], in interval: DateInterval) -> [String: Double] {
        var result: [String: Double] = [:]
        for session in sessions where isWithin(session.date, interval) {
            for set in session.workingSets {
                guard let estimate = SetMetrics.estimatedOneRepMax(set.metrics) else { continue }
                result[set.exerciseId] = max(result[set.exerciseId] ?? 0, estimate)
            }
        }
        return result
    }

    /// Lignes de la carte « Records du mois » : chaque exercice charge
    /// pratique sur la periode, records battus d'abord, puis par part du
    /// record atteinte.
    ///
    /// Seules les series de travail dont la charge est reellement portee et
    /// connue comptent (`SetMetrics.allowsLoadRecord`) : une serie assistee
    /// ou au poids du corps inconnu n'a pas de charge comparable.
    public static func periodRecords(sessions: [AnalyticsSession], period: DateInterval) -> [PeriodRecordEntry] {
        struct Best { var value: Double; var date: Date }
        var inPeriod: [String: Best] = [:]
        var before: [String: Double] = [:]
        var allTime: [String: Double] = [:]
        var names: [String: String] = [:]

        for session in sessions where session.date < period.end {
            for set in session.workingSets {
                guard SetMetrics.allowsLoadRecord(set.metrics),
                      let load = SetMetrics.effectiveLoad(set.metrics), load > 0 else { continue }
                allTime[set.exerciseId] = max(allTime[set.exerciseId] ?? 0, load)
                if isWithin(session.date, period) {
                    names[set.exerciseId] = set.displayName
                    if let current = inPeriod[set.exerciseId], current.value >= load { continue }
                    inPeriod[set.exerciseId] = Best(value: load, date: session.date)
                } else {
                    before[set.exerciseId] = max(before[set.exerciseId] ?? 0, load)
                }
            }
        }

        return inPeriod.map { exerciseId, best in
            PeriodRecordEntry(
                exerciseId: exerciseId,
                displayName: names[exerciseId] ?? exerciseId,
                periodBest: best.value,
                allTimeBest: allTime[exerciseId] ?? best.value,
                previousBest: before[exerciseId],
                achievedAt: best.date
            )
        }
        .sorted { lhs, rhs in
            if lhs.isNewRecord != rhs.isNewRecord { return lhs.isNewRecord }
            if lhs.ratioToRecord != rhs.ratioToRecord { return lhs.ratioToRecord > rhs.ratioToRecord }
            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }
    }

    /// Intervalle semi-ouvert [debut, fin[ : une seance a minuit pile
    /// appartient a une seule periode, jamais aux deux.
    public static func isWithin(_ date: Date, _ interval: DateInterval) -> Bool {
        date >= interval.start && date < interval.end
    }

    /// Mois calendaire contenant `date`.
    public static func month(containing date: Date, calendar: Calendar) -> DateInterval {
        calendar.dateInterval(of: .month, for: date) ?? DateInterval(start: date, duration: 0)
    }
}
