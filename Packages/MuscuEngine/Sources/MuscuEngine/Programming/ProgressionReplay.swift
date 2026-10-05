import Foundation

/// Athlete simule pour rejouer une regle de progression. Deterministe : la
/// meme graine produit exactement le meme historique, d'une execution a
/// l'autre — un test qui echoue doit echouer a chaque fois.
public struct SimulatedAthlete: Equatable, Sendable {
    /// 1RM « reel » au depart, en kg.
    public var startingOneRepMax: Double
    /// Gain de force par semaine (0,005 = +0,5 %), jusqu'au plafond.
    public var weeklyGainFraction: Double
    /// 1RM reel maximal atteignable : au-dela, plateau.
    public var ceilingOneRepMax: Double
    /// Une seance sur `badDayEvery` est mauvaise (fatigue, sommeil) : trois
    /// repetitions de moins sur chaque serie. 0 = jamais.
    public var badDayEvery: Int
    /// Ecart aleatoire maximal, en repetitions, sur chaque serie.
    public var repetitionNoise: Int
    public var seed: UInt64

    public init(
        startingOneRepMax: Double = 100,
        weeklyGainFraction: Double = 0.006,
        ceilingOneRepMax: Double = 130,
        badDayEvery: Int = 7,
        repetitionNoise: Int = 1,
        seed: UInt64 = 42
    ) {
        self.startingOneRepMax = startingOneRepMax
        self.weeklyGainFraction = weeklyGainFraction
        self.ceilingOneRepMax = ceilingOneRepMax
        self.badDayEvery = badDayEvery
        self.repetitionNoise = repetitionNoise
        self.seed = seed
    }
}

/// Prescription rejouee.
public struct ProgressionReplayScenario: Equatable, Sendable {
    public var rule: ProgressionRule
    public var prescribedSets: Int
    public var repsLower: Int
    public var repsUpper: Int
    public var startingWeightKilograms: Double
    public var availableIncrementKilograms: Double
    public var weeks: Int
    public var sessionsPerWeek: Int
    public var startDate: Date

    public init(
        rule: ProgressionRule,
        prescribedSets: Int = 3,
        repsLower: Int = 8,
        repsUpper: Int = 12,
        startingWeightKilograms: Double = 60,
        availableIncrementKilograms: Double = 2.5,
        weeks: Int = 16,
        sessionsPerWeek: Int = 2,
        startDate: Date = Date(timeIntervalSince1970: 1_767_225_600)
    ) {
        self.rule = rule
        self.prescribedSets = prescribedSets
        self.repsLower = repsLower
        self.repsUpper = repsUpper
        self.startingWeightKilograms = startingWeightKilograms
        self.availableIncrementKilograms = availableIncrementKilograms
        self.weeks = weeks
        self.sessionsPerWeek = sessionsPerWeek
        self.startDate = startDate
    }
}

/// Une seance rejouee : ce qui etait prescrit, ce qui a ete fait, ce que le
/// moteur a propose ensuite.
public struct ProgressionReplayStep: Equatable, Sendable {
    public var date: Date
    public var weightKilograms: Double
    public var reps: [Int]
    /// Toutes les series au bas de la fourchette au moins.
    public var reachedTarget: Bool
    public var proposal: ProgressionOutcome
}

/// Resultat d'un rejeu : la trace et ses metriques.
public struct ProgressionReplayReport: Equatable, Sendable {
    public var steps: [ProgressionReplayStep]

    public var increaseCount: Int { steps.filter { if case .increaseLoad = $0.proposal { return true }; return false }.count }
    public var reductionCount: Int { steps.filter { if case .reduceLoad = $0.proposal { return true }; return false }.count }
    public var holdCount: Int { steps.filter { $0.proposal == .hold }.count }

    /// Part des seances suivies d'une hausse de charge.
    public var increaseRate: Double {
        steps.isEmpty ? 0 : Double(increaseCount) / Double(steps.count)
    }

    /// Plus forte hausse relative proposee (0,05 = +5 %).
    public var largestRelativeIncrease: Double {
        steps.compactMap { step -> Double? in
            guard case .increaseLoad(let from, let to) = step.proposal, from > 0 else { return nil }
            return (to - from) / from
        }.max() ?? 0
    }

    public var startingWeight: Double? { steps.first?.weightKilograms }
    public var finalWeight: Double? { steps.last?.weightKilograms }
}

/// Rejoue `ProgressionEngine` sur un historique synthetique de plusieurs
/// semaines, comme si chaque proposition etait acceptee. Outil de
/// developpement : il ne sert qu'aux tests, pour verifier des invariants sur
/// la duree plutot que sur une seule decision.
///
/// Inspire de `ReplayEngine.swift` du « progression lab » d'UpLift (MIT),
/// recrit en kg autour du moteur de Muscu, avec un athlete simule.
public enum ProgressionReplay {
    public static func run(_ scenario: ProgressionReplayScenario, athlete: SimulatedAthlete) -> ProgressionReplayReport {
        var generator = SeededGenerator(seed: athlete.seed)
        var weight = scenario.startingWeightKilograms
        var exposures: [ExerciseExposure] = []
        var steps: [ProgressionReplayStep] = []
        let sessionCount = max(0, scenario.weeks * scenario.sessionsPerWeek)
        let spacing = 7.0 / Double(max(1, scenario.sessionsPerWeek)) * 86_400

        for index in 0..<sessionCount {
            let date = scenario.startDate.addingTimeInterval(Double(index) * spacing)
            let weeksElapsed = Double(index) / Double(max(1, scenario.sessionsPerWeek))
            let trueMax = min(
                athlete.ceilingOneRepMax,
                athlete.startingOneRepMax * pow(1 + athlete.weeklyGainFraction, weeksElapsed)
            )
            let isBadDay = athlete.badDayEvery > 0 && (index + 1) % athlete.badDayEvery == 0

            var reps: [Int] = []
            for setIndex in 0..<scenario.prescribedSets {
                // Epley inverse : repetitions possibles a cette charge, moins
                // la fatigue des series precedentes.
                let capacity = weight > 0 ? 30 * (trueMax / weight - 1) : Double(scenario.repsUpper)
                var performed = Int(capacity.rounded(.down)) - setIndex
                if athlete.repetitionNoise > 0 {
                    performed += Int.random(in: -athlete.repetitionNoise...athlete.repetitionNoise, using: &generator)
                }
                if isBadDay { performed -= 3 }
                // Personne ne depasse volontairement le haut de la fourchette.
                reps.append(min(scenario.repsUpper, max(0, performed)))
            }

            let exposure = ExerciseExposure(
                date: date,
                sets: reps.map { ExposureSet(weightKilograms: weight, reps: $0) }
            )
            exposures.insert(exposure, at: 0)

            let proposal = ProgressionEngine.propose(ProgressionContext(
                rule: scenario.rule,
                prescribedSets: scenario.prescribedSets,
                repsLower: scenario.repsLower,
                repsUpper: scenario.repsUpper,
                currentWeightKilograms: weight,
                availableIncrementKilograms: scenario.availableIncrementKilograms,
                exposures: exposures
            ))

            steps.append(ProgressionReplayStep(
                date: date,
                weightKilograms: weight,
                reps: reps,
                reachedTarget: reps.count >= scenario.prescribedSets && reps.allSatisfy { $0 >= scenario.repsLower },
                proposal: proposal.outcome
            ))

            switch proposal.outcome {
            case .increaseLoad(_, let target), .reduceLoad(_, let target):
                weight = target
            default:
                break
            }
        }

        return ProgressionReplayReport(steps: steps)
    }

    /// Invariant viole par un rejeu.
    public struct Violation: Equatable, Sendable, CustomStringConvertible {
        public var stepIndex: Int
        public var message: String

        public var description: String { "seance \(stepIndex + 1) : \(message)" }
    }

    /// Verifie les invariants de securite d'une trace :
    /// - aucune hausse superieure a `maximumRelativeIncrease` (au-dessus de
    ///   `smallLoadThreshold` kg : sur une petite charge, le plus petit
    ///   increment disponible est forcement un gros pourcentage) ;
    /// - aucune hausse juste apres une seance ratee ;
    /// - apres `ProgressionRule.failuresBeforeDeload` seances ratees
    ///   d'affilee, une decharge est proposee, d'environ
    ///   `ProgressionEngine.deloadFraction` ;
    /// - la charge reste finie et strictement positive.
    public static func violations(
        in report: ProgressionReplayReport,
        maximumRelativeIncrease: Double = 0.1,
        smallLoadThreshold: Double = 25,
        incrementKilograms: Double = 2.5
    ) -> [Violation] {
        var found: [Violation] = []
        var consecutiveFailures = 0

        for (index, step) in report.steps.enumerated() {
            if !step.weightKilograms.isFinite || step.weightKilograms <= 0 {
                found.append(Violation(stepIndex: index, message: "charge invalide (\(step.weightKilograms) kg)"))
            }
            consecutiveFailures = step.reachedTarget ? 0 : consecutiveFailures + 1

            switch step.proposal {
            case .increaseLoad(let from, let to):
                if !step.reachedTarget {
                    found.append(Violation(stepIndex: index, message: "hausse proposée après une séance ratée"))
                }
                if from >= smallLoadThreshold, from > 0, (to - from) / from > maximumRelativeIncrease + 1e-9 {
                    found.append(Violation(stepIndex: index, message: "hausse de \(Int(((to - from) / from * 100).rounded())) % (\(from) → \(to) kg)"))
                }
            case .reduceLoad(let from, let to):
                let expected = from * (1 - ProgressionEngine.deloadFraction)
                if abs(to - expected) > incrementKilograms / 2 + 1e-9 {
                    found.append(Violation(stepIndex: index, message: "décharge de \(from) à \(to) kg, attendue vers \(expected) kg"))
                }
            default:
                if consecutiveFailures >= ProgressionRule.failuresBeforeDeload {
                    found.append(Violation(stepIndex: index, message: "\(consecutiveFailures) séances ratées d’affilée sans décharge"))
                }
            }
        }
        return found
    }
}

/// Generateur pseudo-aleatoire a graine (SplitMix64) : deterministe et
/// identique sur toutes les plateformes, contrairement au generateur
/// systeme.
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
