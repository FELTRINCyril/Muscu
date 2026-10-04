import Foundation

/// Nature de la charge d'une serie. Determine comment la valeur `weight`
/// stockee doit etre interpretee pour le tonnage, l'estimation de 1RM et
/// la detection de records.
///
/// - `external` : la charge soulevee (barre, halteres, machine, cable).
/// - `bodyweight` : aucun lest ; la charge deplacee est le poids de corps.
/// - `weighted` : poids de corps + lest. `weight` stocke le LEST SEUL.
/// - `assisted` : poids de corps - assistance. `weight` stocke l'ASSISTANCE.
/// - `unknown` : donnee historique anterieure au typage explicite.
public enum LoadKind: String, Codable, CaseIterable, Sendable {
    case external
    case bodyweight
    case weighted
    case assisted
    case unknown

    /// Un record de charge maximale (1RM estime) n'a de sens que pour une
    /// charge reellement portee par l'athlete. Une serie assistee reduit la
    /// charge : elle ne doit jamais produire un record de charge.
    public var allowsLoadRecord: Bool {
        switch self {
        case .external, .weighted: return true
        case .bodyweight, .assisted, .unknown: return false
        }
    }

    /// Un record de repetitions non qualifie n'a de sens que lorsque la
    /// charge est constante et connue : le poids de corps.
    ///
    /// Une serie ASSISTEE ou LESTEE peut battre un record de repetitions,
    /// mais seulement a assistance ou a lest egal : ce record doit porter une
    /// cle de configuration (cf. `requiresConfigurationForRecord`), sinon
    /// huit tractions avec 30 kg d'aide ecraseraient huit tractions strictes.
    public var allowsRepsRecord: Bool {
        switch self {
        case .bodyweight: return true
        case .external, .weighted, .assisted, .unknown: return false
        }
    }

    /// La performance n'est comparable qu'a configuration identique (lest ou
    /// assistance de meme valeur).
    public var requiresConfigurationForRecord: Bool {
        switch self {
        case .weighted, .assisted: return true
        case .external, .bodyweight, .unknown: return false
        }
    }
}

/// Convention pour les exercices unilateraux : la valeur stockee concerne
/// un cote, ou les deux cumules. Stockee explicitement afin qu'aucune vue
/// n'ait a deviner.
public enum SideConvention: String, Codable, CaseIterable, Sendable {
    case bilateral
    case perSide
    case combined

    /// Facteur applique au tonnage quand la serie est saisie par cote.
    public var tonnageFactor: Double {
        switch self {
        case .bilateral, .combined: return 1
        case .perSide: return 2
        }
    }
}

/// Description minimale et pure d'une serie realisee, utilisee par toutes
/// les analyses partagees (tonnage, 1RM estime, records). L'app convertit
/// ses modeles SwiftData vers ce type plutot que de dupliquer les formules.
public struct SetMetricsInput: Equatable, Sendable {
    public var weightKilograms: Double
    public var reps: Int
    public var loadKind: LoadKind
    public var side: SideConvention
    public var isWarmup: Bool
    /// Poids de corps connu au moment de la serie, en kg. Necessaire pour
    /// le tonnage des formats `bodyweight`, `weighted` et `assisted`.
    public var bodyweightKilograms: Double?
    public var durationSeconds: Int?
    public var distanceMeters: Double?
    /// Plafond de repetitions au-dela duquel une serie n'estime plus de 1RM
    /// (reglage utilisateur, borne par `OneRepMaxEstimation`).
    public var maximumRepsForOneRepMax: Int

    public init(
        weightKilograms: Double,
        reps: Int,
        loadKind: LoadKind,
        side: SideConvention = .bilateral,
        isWarmup: Bool = false,
        bodyweightKilograms: Double? = nil,
        durationSeconds: Int? = nil,
        distanceMeters: Double? = nil,
        maximumRepsForOneRepMax: Int = OneRepMaxEstimation.defaultMaximumReps
    ) {
        self.weightKilograms = weightKilograms
        self.reps = reps
        self.loadKind = loadKind
        self.side = side
        self.isWarmup = isWarmup
        self.bodyweightKilograms = bodyweightKilograms
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.maximumRepsForOneRepMax = OneRepMaxEstimation.clamped(maximumRepsForOneRepMax)
    }
}

/// Reglage du plafond de repetitions pour le 1RM estime.
///
/// La formule d'Epley se degrade vite au-dela d'une douzaine de
/// repetitions : une serie de 20 surestime nettement le maximum. Douze est
/// le comportement historique ; un utilisateur prudent peut descendre a 5,
/// un pratiquant d'endurance de force monter un peu.
public enum OneRepMaxEstimation {
    public static let defaultMaximumReps = 12
    public static let allowedMaximumReps = 1...20

    public static func clamped(_ value: Int) -> Int {
        min(max(value, allowedMaximumReps.lowerBound), allowedMaximumReps.upperBound)
    }
}

public enum SetMetrics {
    /// Charge effectivement deplacee par la serie, en kg.
    ///
    /// Retourne `nil` quand le poids de corps est necessaire mais inconnu :
    /// les vues doivent alors afficher « donnee manquante » plutot que zero.
    public static func effectiveLoad(_ input: SetMetricsInput) -> Double? {
        guard input.weightKilograms.isFinite else { return nil }
        switch input.loadKind {
        case .external, .unknown:
            return input.weightKilograms
        case .bodyweight:
            return input.bodyweightKilograms
        case .weighted:
            guard let bodyweight = input.bodyweightKilograms else { return nil }
            return bodyweight + input.weightKilograms
        case .assisted:
            guard let bodyweight = input.bodyweightKilograms else { return nil }
            return max(0, bodyweight - input.weightKilograms)
        }
    }

    /// Charge pertinente pour la PROGRESSION de charge : le lest seul pour
    /// une traction lestee, l'assistance pour une traction assistee.
    public static func progressionLoad(_ input: SetMetricsInput) -> Double {
        switch input.loadKind {
        case .external, .weighted, .assisted, .unknown:
            return input.weightKilograms
        case .bodyweight:
            return 0
        }
    }

    /// Tonnage d'une serie : charge effective x repetitions, corrigee par
    /// la convention unilaterale. `nil` si la charge effective est inconnue.
    public static func tonnage(_ input: SetMetricsInput) -> Double? {
        guard input.reps > 0, let load = effectiveLoad(input) else { return nil }
        return load * Double(input.reps) * input.side.tonnageFactor
    }

    /// Une serie peut-elle porter un record de CHARGE ?
    ///
    /// Les series anterieures au typage explicite (`unknown`) sont lues par
    /// leur charge : une charge saisie signifie une charge portee. Sans cette
    /// lecture, tout l'historique d'avant le typage perdrait ses records.
    public static func allowsLoadRecord(_ input: SetMetricsInput) -> Bool {
        switch input.loadKind {
        case .external, .weighted: return true
        case .unknown: return input.weightKilograms > 0
        case .bodyweight, .assisted: return false
        }
    }

    /// Une serie est eligible a l'estimation de 1RM si elle est une serie
    /// de travail portant une charge reelle, entre 1 et le plafond de
    /// repetitions regle (12 par defaut).
    public static func isEligibleForOneRepMax(_ input: SetMetricsInput) -> Bool {
        let maximum = OneRepMaxEstimation.clamped(input.maximumRepsForOneRepMax)
        guard !input.isWarmup, allowsLoadRecord(input), (1...maximum).contains(input.reps) else {
            return false
        }
        guard let load = effectiveLoad(input), load > 0 else { return false }
        return true
    }

    /// 1RM estime (Epley) pour une serie eligible, sinon `nil`.
    /// Il s'agit d'une ESTIMATION : les vues doivent l'indiquer.
    public static func estimatedOneRepMax(_ input: SetMetricsInput) -> Double? {
        guard isEligibleForOneRepMax(input), let load = effectiveLoad(input) else { return nil }
        return OneRepMax.epley(weight: load, reps: input.reps)
    }

    /// Duree sous tension a partir d'un tempo, quand il est renseigne.
    public static func timeUnderTension(_ input: SetMetricsInput, tempo: Tempo?) -> Int? {
        if let duration = input.durationSeconds, duration > 0 { return duration }
        guard let tempo, input.reps > 0 else { return nil }
        return tempo.secondsPerRep * input.reps
    }

    /// Une serie peut-elle produire un record de repetitions NON qualifie ?
    ///
    /// Les series anterieures au typage explicite (`unknown`) sans charge
    /// saisie sont traitees comme du poids de corps : c'est la seule lecture
    /// possible d'une serie a zero kilo, et elle preserve les records deja
    /// detectes par les versions precedentes.
    public static func allowsRepetitionRecord(_ input: SetMetricsInput) -> Bool {
        guard !input.isWarmup, input.reps > 0 else { return false }
        switch input.loadKind {
        case .bodyweight: return true
        case .unknown: return input.weightKilograms == 0
        case .external, .weighted, .assisted: return false
        }
    }

    /// Cle de configuration d'un record dependant du lest ou de
    /// l'assistance, par exemple `assisted:30.0` ou `weighted:20.0`. Vide
    /// quand la performance est comparable sans qualification.
    ///
    /// Le format est volontairement fixe et independant de la locale : cette
    /// cle est persistee et comparee telle quelle.
    public static func recordConfigurationKey(_ input: SetMetricsInput) -> String {
        guard input.loadKind.requiresConfigurationForRecord else { return "" }
        let rounded = Units.roundedForDisplay(input.weightKilograms)
        return input.loadKind.rawValue + ":" + String(format: "%.1f", rounded)
    }

    /// Tonnage total d'un ensemble de series ; les series dont la charge
    /// effective est inconnue sont comptees separement afin de distinguer
    /// « zero » de « donnee manquante ».
    public static func totalTonnage(_ inputs: [SetMetricsInput]) -> (total: Double, unknownSets: Int) {
        var total: Double = 0
        var unknown = 0
        for input in inputs where !input.isWarmup {
            if let value = tonnage(input) {
                total += value
            } else if input.reps > 0 {
                unknown += 1
            }
        }
        return (total, unknown)
    }
}
