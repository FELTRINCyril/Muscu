import Foundation

/// Statistiques d'un exercice sur une periode : force relative, intensite
/// moyenne et charge moyenne.
///
/// Idee reprise de Skulpt (GPL-3.0) : idee seulement, aucune ligne de code.
/// Aucun niveau « novice / avance / elite » n'est affiche : sans table de
/// reference sourcee, ce serait un jugement invente.
public struct ExerciseStatistics: Equatable, Sendable {
    /// Meilleur 1RM estime de la periode, et sa date.
    public var bestEstimatedOneRepMax: AnalyticsPoint?
    /// Poids de corps retenu pour la force relative (celui connu a la date
    /// du meilleur 1RM). `nil` = inconnu a cette date.
    public var bodyweightAtBest: Double?
    /// 1RM estime / poids de corps. `nil` si l'un des deux manque.
    public var relativeStrength: Double? {
        guard let best = bestEstimatedOneRepMax?.value, let bodyweight = bodyweightAtBest, bodyweight > 0 else { return nil }
        return best / bodyweight
    }

    /// Intensite moyenne des series de travail : charge / 1RM estime de
    /// reference, de 0 a 1 (et parfois un peu plus : une serie peut depasser
    /// l'estimation). `nil` sans serie mesurable.
    public var averageIntensity: Double?
    /// Series de travail ayant servi au calcul de l'intensite.
    public var intensitySetCount: Int
    /// Charge effective moyenne des series de travail chargees, en kg.
    public var averageLoad: Double?
    public var loadSetCount: Int
    /// Series de travail dont la charge effective est inconnue (poids de
    /// corps manquant) : exclues des moyennes, et annoncees.
    public var unknownLoadSets: Int

    public init(
        bestEstimatedOneRepMax: AnalyticsPoint? = nil,
        bodyweightAtBest: Double? = nil,
        averageIntensity: Double? = nil,
        intensitySetCount: Int = 0,
        averageLoad: Double? = nil,
        loadSetCount: Int = 0,
        unknownLoadSets: Int = 0
    ) {
        self.bestEstimatedOneRepMax = bestEstimatedOneRepMax
        self.bodyweightAtBest = bodyweightAtBest
        self.averageIntensity = averageIntensity
        self.intensitySetCount = intensitySetCount
        self.averageLoad = averageLoad
        self.loadSetCount = loadSetCount
        self.unknownLoadSets = unknownLoadSets
    }

    /// Calcule les statistiques de `exerciseId` sur `period`.
    ///
    /// - Parameters:
    ///   - history: TOUTES les seances, pour la reference d'intensite : le
    ///     1RM de reference d'une serie est le meilleur estime JUSQU'A sa
    ///     seance incluse — jamais une performance future.
    ///   - bodyweights: poids de corps dates (mesures, poids fige sur une
    ///     seance). Le poids retenu est le dernier connu a la date, jamais une
    ///     valeur posterieure.
    public static func compute(
        exerciseId: String,
        history: [AnalyticsSession],
        period: DateInterval,
        bodyweights: [AnalyticsPoint]
    ) -> ExerciseStatistics {
        let ordered = history.sorted { $0.date < $1.date }
        var runningBest: Double?
        var best: AnalyticsPoint?
        var intensities: [Double] = []
        var loads: [Double] = []
        var unknown = 0

        for session in ordered where session.date < period.end {
            let sets = session.workingSets.filter { $0.exerciseId == exerciseId }
            guard !sets.isEmpty else { continue }

            let sessionBest = sets.compactMap { SetMetrics.estimatedOneRepMax($0.metrics) }.max()
            if let sessionBest {
                runningBest = max(runningBest ?? 0, sessionBest)
            }

            guard StrengthDashboard.isWithin(session.date, period) else { continue }

            if let sessionBest, sessionBest > (best?.value ?? 0) {
                best = AnalyticsPoint(date: session.date, value: sessionBest)
            }

            for set in sets {
                guard SetMetrics.allowsLoadRecord(set.metrics) else { continue }
                guard let load = SetMetrics.effectiveLoad(set.metrics) else {
                    unknown += 1
                    continue
                }
                guard load > 0 else { continue }
                loads.append(load)
                if let reference = runningBest, reference > 0 {
                    intensities.append(load / reference)
                }
            }
        }

        return ExerciseStatistics(
            bestEstimatedOneRepMax: best,
            bodyweightAtBest: best.flatMap { bodyweight(at: $0.date, in: bodyweights) },
            averageIntensity: intensities.isEmpty ? nil : intensities.reduce(0, +) / Double(intensities.count),
            intensitySetCount: intensities.count,
            averageLoad: loads.isEmpty ? nil : loads.reduce(0, +) / Double(loads.count),
            loadSetCount: loads.count,
            unknownLoadSets: unknown
        )
    }

    /// Dernier poids de corps connu a `date` (mesure du jour comprise).
    public static func bodyweight(at date: Date, in points: [AnalyticsPoint]) -> Double? {
        points
            .filter { $0.date <= date && $0.value > 0 }
            .max { $0.date < $1.date }?
            .value
    }
}
