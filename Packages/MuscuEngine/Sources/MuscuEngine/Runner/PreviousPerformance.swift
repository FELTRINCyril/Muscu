import Foundation

/// Serie d'une seance passee, reduite a ce que la seance en direct affiche.
public struct HistoricalSet: Equatable, Sendable {
    public var weightKilograms: Double
    public var reps: Int
    /// Serie de TRAVAIL prescrite (ni echauffement, ni approche, ni back-off).
    public var isPrescribedWorkingSet: Bool
    public var orderIndex: Int
    public var roundIndex: Int
    public var setIndex: Int
    /// Palier de dropset, mini-serie : zero pour la serie principale.
    public var subSetIndex: Int
    public var sequenceIndex: Int

    public init(
        weightKilograms: Double,
        reps: Int,
        isPrescribedWorkingSet: Bool = true,
        orderIndex: Int = 0,
        roundIndex: Int = 0,
        setIndex: Int,
        subSetIndex: Int = 0,
        sequenceIndex: Int = 0
    ) {
        self.weightKilograms = weightKilograms
        self.reps = reps
        self.isPrescribedWorkingSet = isPrescribedWorkingSet
        self.orderIndex = orderIndex
        self.roundIndex = roundIndex
        self.setIndex = setIndex
        self.subSetIndex = subSetIndex
        self.sequenceIndex = sequenceIndex
    }
}

/// Valeur precedente PAR SERIE : ce qui a ete fait a la meme serie de
/// travail, sur le meme exercice, lors de la derniere seance comparable.
///
/// La reference est la derniere seance, pas le record : pour progresser,
/// on se compare a ce qu'on a fait la fois d'avant (idee reprise d'Ischys,
/// `domain/previous.ts`, MIT).
public enum PreviousPerformance {
    /// Series principales de travail, dans l'ordre ou elles ont ete
    /// prescrites. Les echauffements, approches, back-off et paliers de
    /// dropset ne decalent pas le rang : la 3e serie reste la 3e.
    public static func workingSets(_ sets: [HistoricalSet]) -> [HistoricalSet] {
        sets
            .filter { $0.isPrescribedWorkingSet && $0.subSetIndex == 0 && $0.reps > 0 }
            .sorted {
                ($0.orderIndex, $0.roundIndex, $0.setIndex, $0.sequenceIndex)
                    < ($1.orderIndex, $1.roundIndex, $1.setIndex, $1.sequenceIndex)
            }
    }

    /// Rang 0-based d'une serie de travail dans la seance en cours : tour
    /// puis serie. Un exercice seul n'a qu'un tour ; un superset n'a qu'une
    /// serie par tour.
    public static func workingRank(round: Int, setNumber: Int, totalSets: Int) -> Int {
        max(0, (max(1, round) - 1) * max(1, totalSets) + max(1, setNumber) - 1)
    }

    /// Serie de meme rang dans la seance passee, ou `nil` si elle n'en avait
    /// pas autant. `nil` n'est pas zero : rien n'est affiche.
    public static func reference(atWorkingRank rank: Int, in sets: [HistoricalSet]) -> HistoricalSet? {
        let working = workingSets(sets)
        guard rank >= 0, rank < working.count else { return nil }
        return working[rank]
    }
}

/// Bandeau des dernieres seances d'un exercice, en mise en forme pure.
///
/// Adapte d'UpLift (`PrevSessionsStripData.swift`, MIT, Daniel Kuhlwein) :
/// ordre chronologique (la plus recente a droite), series regroupees par
/// charge consecutive. Les libelles ne sont pas produits ici : le moteur
/// renvoie un `RelativeAge` que l'application traduit.
public enum PreviousSessionsStrip {
    public static let defaultLimit = 10

    public struct SetPair: Equatable, Sendable {
        public var weightKilograms: Double
        public var reps: Int

        public init(weightKilograms: Double, reps: Int) {
            self.weightKilograms = weightKilograms
            self.reps = reps
        }
    }

    public struct SessionSets: Equatable, Sendable {
        public var id: UUID
        public var date: Date
        /// Series de travail dans l'ordre de la seance.
        public var sets: [SetPair]

        public init(id: UUID, date: Date, sets: [SetPair]) {
            self.id = id
            self.date = date
            self.sets = sets
        }
    }

    /// Suite de series consecutives a la meme charge : « 20 kg × 15, 9 ».
    public struct Run: Equatable, Sendable {
        public var weightKilograms: Double
        public var reps: [Int]

        public init(weightKilograms: Double, reps: [Int]) {
            self.weightKilograms = weightKilograms
            self.reps = reps
        }
    }

    /// Anciennete d'une seance, a traduire par l'application.
    public enum RelativeAge: Equatable, Sendable {
        case today
        case yesterday
        case days(Int)
        case weeks(Int)
        case months(Int)
    }

    public struct Entry: Equatable, Sendable, Identifiable {
        public var id: UUID
        public var date: Date
        public var age: RelativeAge
        public var runs: [Run]
    }

    /// Entrees de la plus ancienne a la plus recente, limitees aux `limit`
    /// seances les plus recentes ayant au moins une serie.
    public static func entries(
        from sessions: [SessionSets],
        now: Date,
        calendar: Calendar = .current,
        limit: Int = defaultLimit
    ) -> [Entry] {
        sessions
            .filter { !$0.sets.isEmpty }
            .sorted { $0.date < $1.date }
            .suffix(max(0, limit))
            .map { session in
                Entry(
                    id: session.id,
                    date: session.date,
                    age: relativeAge(of: session.date, now: now, calendar: calendar),
                    runs: runs(for: session.sets)
                )
            }
    }

    /// Une suite par serie de charges consecutives identiques, ordre conserve.
    public static func runs(for sets: [SetPair]) -> [Run] {
        var result: [Run] = []
        for set in sets where set.reps > 0 {
            if let last = result.last, abs(last.weightKilograms - set.weightKilograms) < 0.000_1 {
                result[result.count - 1].reps.append(set.reps)
            } else {
                result.append(Run(weightKilograms: set.weightKilograms, reps: [set.reps]))
            }
        }
        return result
    }

    /// Aujourd'hui / hier / N jours / N semaines (jusqu'a 8) / N mois, en
    /// jours calendaires : une seance d'hier soir est « hier » ce matin.
    public static func relativeAge(of date: Date, now: Date, calendar: Calendar = .current) -> RelativeAge {
        let start = calendar.startOfDay(for: date)
        let end = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        switch days {
        case ..<1: return .today
        case 1: return .yesterday
        case 2...6: return .days(days)
        case 7...55: return .weeks(days / 7)
        default: return .months(max(1, days / 30))
        }
    }
}
