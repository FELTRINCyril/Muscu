import Foundation

/// Record battu pendant la seance, pour une celebration immediate.
///
/// La celebration n'ecrit RIEN : la detection de fin de seance
/// (`RecordDetection`, `PersonalBestUpdater` cote application) reste la
/// source de verite. Les regles d'eligibilite sont celles de `SetMetrics`,
/// et seuls les records NON qualifies (cle de configuration vide) sont
/// consideres : une traction lestee ne se compare qu'a lest egal, ce
/// qu'une celebration en direct n'a pas a trancher.
public enum LiveRecord {
    public enum Kind: Equatable, Sendable {
        /// 1RM estime (kg), nouvelle et ancienne valeur.
        case estimatedOneRepMax(new: Double, previous: Double)
        /// Charge reellement portee (kg).
        case maxLoad(new: Double, previous: Double)
    }

    /// Meilleures valeurs connues AVANT la seance, en kg. `nil` = aucune.
    public struct Baseline: Equatable, Sendable {
        public var bestEstimatedOneRepMax: Double?
        public var bestLoad: Double?

        public init(bestEstimatedOneRepMax: Double? = nil, bestLoad: Double? = nil) {
            self.bestEstimatedOneRepMax = bestEstimatedOneRepMax
            self.bestLoad = bestLoad
        }
    }

    /// Ecart minimal pour parler de record : un arrondi n'en est pas un.
    static let tolerance = 0.001

    /// Record battu par cette serie par rapport a la reference, s'il y en a
    /// un. Sans reference (premiere fois sur l'exercice), rien n'est
    /// celebre : tout serait un « record ». Le 1RM estime prime sur la
    /// charge quand les deux sont battus.
    public static func improvement(of input: SetMetricsInput, over baseline: Baseline) -> Kind? {
        if let estimate = SetMetrics.estimatedOneRepMax(input),
           let previous = baseline.bestEstimatedOneRepMax, previous > 0,
           estimate > previous + tolerance {
            return .estimatedOneRepMax(new: estimate, previous: previous)
        }
        if SetMetrics.allowsLoadRecord(input), !input.isWarmup, input.reps > 0,
           let load = SetMetrics.effectiveLoad(input), load > 0,
           let previous = baseline.bestLoad, previous > 0,
           load > previous + tolerance {
            return .maxLoad(new: load, previous: previous)
        }
        return nil
    }

    /// Celebration a declencher pour la serie qui vient d'etre validee : une
    /// seule fois par exercice et par seance. Sans etat a memoriser : si une
    /// serie anterieure de la seance battait deja la reference, la fete a
    /// deja eu lieu — y compris apres une reprise de seance.
    public static func celebration(
        for current: SetMetricsInput,
        earlierThisSession: [SetMetricsInput],
        baseline: Baseline
    ) -> Kind? {
        guard let kind = improvement(of: current, over: baseline) else { return nil }
        let alreadyCelebrated = earlierThisSession.contains { improvement(of: $0, over: baseline) != nil }
        return alreadyCelebrated ? nil : kind
    }
}

/// Calculateur de 1RM rapide : charge × repetitions -> 1RM estime, et
/// tableau des pourcentages usuels arrondis au palier chargeable. Distinct
/// du test de 1RM guide (`OneRepMaxTest`), qui mesure un vrai maximum.
public enum OneRepMaxCalculator {
    public struct Row: Equatable, Sendable, Identifiable {
        public var percent: Int
        /// Charge exacte (kg), avant arrondi.
        public var exactKilograms: Double
        /// Charge arrondie au palier le plus proche (kg).
        public var roundedKilograms: Double
        public var id: Int { percent }
    }

    public static let percentages = Array(stride(from: 95, through: 50, by: -5))

    /// 1RM estime (Epley, formule du moteur). Les repetitions sont bornees
    /// au plafond regle : au-dela, la formule n'est plus credible et le
    /// calculateur le dit en renvoyant `nil`.
    public static func estimate(
        weightKilograms: Double,
        reps: Int,
        maximumReps: Int = OneRepMaxEstimation.defaultMaximumReps
    ) -> Double? {
        guard weightKilograms.isFinite, weightKilograms > 0, reps >= 1,
              reps <= OneRepMaxEstimation.clamped(maximumReps) else { return nil }
        return OneRepMax.epley(weight: weightKilograms, reps: reps)
    }

    /// Tableau 95 % -> 50 %, arrondi au palier le plus proche (kg). Un pas
    /// invalide laisse la charge exacte.
    public static func table(oneRepMaxKilograms: Double, stepKilograms: Double) -> [Row] {
        guard oneRepMaxKilograms.isFinite, oneRepMaxKilograms > 0 else { return [] }
        return percentages.map { percent in
            let exact = oneRepMaxKilograms * Double(percent) / 100
            let rounded = stepKilograms.isFinite && stepKilograms > 0
                ? (exact / stepKilograms).rounded() * stepKilograms
                : exact
            return Row(percent: percent, exactKilograms: exact, roundedKilograms: rounded)
        }
    }
}

/// Bips des dernieres secondes du repos.
public enum RestBeeps {
    /// Nombre de bips avant le son de fin.
    public static let count = 3

    /// Instants des bips encore a venir : 3, 2 et 1 seconde avant la fin.
    /// Un bip deja passe n'est jamais rejoue (repos prolonge, reprise).
    public static func times(endDate: Date, now: Date) -> [Date] {
        (1...count).reversed()
            .map { endDate.addingTimeInterval(-Double($0)) }
            .filter { $0 > now }
    }
}
