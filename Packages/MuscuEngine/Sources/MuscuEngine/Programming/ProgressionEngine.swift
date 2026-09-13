import Foundation

/// Une serie realisee, telle que le moteur de progression a besoin de la lire.
public struct ExposureSet: Equatable, Sendable {
    public var weightKilograms: Double
    public var reps: Int
    public var effort: EffortRating?
    public var loadKind: LoadKind
    public var isWorkingSet: Bool
    public var durationSeconds: Int?

    public init(
        weightKilograms: Double,
        reps: Int,
        effort: EffortRating? = nil,
        loadKind: LoadKind = .external,
        isWorkingSet: Bool = true,
        durationSeconds: Int? = nil
    ) {
        self.weightKilograms = weightKilograms
        self.reps = reps
        self.effort = effort
        self.loadKind = loadKind
        self.isWorkingSet = isWorkingSet
        self.durationSeconds = durationSeconds
    }
}

/// Une exposition = une seance ou cet exercice a ete travaille.
public struct ExerciseExposure: Equatable, Sendable {
    public var date: Date
    public var sets: [ExposureSet]

    public init(date: Date, sets: [ExposureSet]) {
        self.date = date
        self.sets = sets
    }

    public var workingSets: [ExposureSet] { sets.filter(\.isWorkingSet) }
}

/// Tout ce dont la regle a besoin pour decider, sans rien connaitre du stockage.
public struct ProgressionContext: Equatable, Sendable {
    public var rule: ProgressionRule
    public var prescribedSets: Int
    public var repsLower: Int
    public var repsUpper: Int
    /// Charge actuellement prescrite, si elle est connue.
    public var currentWeightKilograms: Double?
    /// Plus petit increment de chargement dont dispose reellement l'athlete.
    public var availableIncrementKilograms: Double
    public var loadKind: LoadKind
    /// Expositions de la plus RECENTE a la plus ancienne.
    public var exposures: [ExerciseExposure]
    /// Effort cible declare sur la prescription, s'il y en a un.
    public var targetEffort: EffortRating?

    public init(
        rule: ProgressionRule,
        prescribedSets: Int,
        repsLower: Int,
        repsUpper: Int,
        currentWeightKilograms: Double? = nil,
        availableIncrementKilograms: Double = 2.5,
        loadKind: LoadKind = .external,
        exposures: [ExerciseExposure] = [],
        targetEffort: EffortRating? = nil
    ) {
        self.rule = rule
        self.prescribedSets = prescribedSets
        self.repsLower = repsLower
        self.repsUpper = repsUpper
        self.currentWeightKilograms = currentWeightKilograms
        self.availableIncrementKilograms = availableIncrementKilograms
        self.loadKind = loadKind
        self.exposures = exposures
        self.targetEffort = targetEffort
    }
}

/// Ce que la regle propose. Une proposition n'est JAMAIS appliquee seule :
/// l'appelant la presente, l'utilisateur confirme ou refuse.
public enum ProgressionOutcome: Equatable, Sendable {
    case increaseLoad(from: Double, to: Double)
    case reduceLoad(from: Double, to: Double)
    case increaseReps(from: Int, to: Int)
    case increaseSets(from: Int, to: Int)
    case increasePercent(from: Double, to: Double)
    case adjustTime(workDeltaSeconds: Int, restDeltaSeconds: Int)
    /// Conserver la prescription telle quelle.
    case hold
    /// Pas assez d'historique comparable pour decider quoi que ce soit.
    case notEnoughData
}

/// Facteur identifiable ayant conduit a la proposition. Chaque facteur doit
/// pouvoir etre relie a une performance reelle : « toutes les series ont
/// atteint 12 répétitions », jamais « tu progresses bien ».
public struct ProgressionFactor: Equatable, Sendable {
    public var text: String

    public init(_ text: String) {
        self.text = text
    }
}

public struct ProgressionProposal: Equatable, Sendable {
    public var outcome: ProgressionOutcome
    public var factors: [ProgressionFactor]

    public init(outcome: ProgressionOutcome, factors: [ProgressionFactor]) {
        self.outcome = outcome
        self.factors = factors
    }

    public var changesAnything: Bool {
        switch outcome {
        case .hold, .notEnoughData: return false
        default: return true
        }
    }
}

/// Evalue une regle de progression contre l'historique reel.
///
/// Trois principes :
/// 1. rien n'est propose sans performance identifiable (`notEnoughData`) ;
/// 2. chaque proposition porte ses facteurs, affichables tels quels ;
/// 3. le moteur ne modifie rien : il repond, l'appelant decide.
public enum ProgressionEngine {
    /// Reduction appliquee quand plusieurs seances consecutives echouent.
    /// Volontairement modeste : il s'agit de relancer la progression, pas de
    /// diagnostiquer quoi que ce soit.
    public static let deloadFraction = 0.1

    public static func propose(_ context: ProgressionContext) -> ProgressionProposal {
        guard context.rule.isValid else {
            return ProgressionProposal(
                outcome: .notEnoughData,
                factors: [ProgressionFactor("La règle de progression est incomplète.")]
            )
        }

        switch context.rule {
        case .none:
            return ProgressionProposal(outcome: .hold, factors: [ProgressionFactor("Aucune progression automatique n’est configurée.")])

        case .doubleProgression(let increment, let requiredSuccesses):
            return doubleProgression(context, increment: increment, requiredSuccesses: requiredSuccesses)

        case .linearLoad(let increment, let requiredSuccesses):
            return linearLoad(context, increment: increment, requiredSuccesses: requiredSuccesses)

        case .repsProgression(let step, let maximum):
            return repsProgression(context, step: step, maximum: maximum)

        case .setsProgression(let step, let maximum):
            return setsProgression(context, step: step, maximum: maximum)

        case .percentOneRepMax(let percent, let percentStep):
            return percentProgression(context, percent: percent, step: percentStep)

        case .effortTarget(let targetRepsInReserve, let increment):
            return effortTarget(context, targetRepsInReserve: targetRepsInReserve, increment: increment)

        case .assistedOrWeighted(let increment, let targetReps):
            return assistedOrWeighted(context, increment: increment, targetReps: targetReps)

        case .timeProgression(let workStep, let restStep):
            return timeProgression(context, workStep: workStep, restStep: restStep)
        }
    }

    // MARK: - Regles

    /// Double progression : monter en repetitions dans la fourchette, puis
    /// ajouter un increment et revenir au bas de la fourchette.
    private static func doubleProgression(
        _ context: ProgressionContext,
        increment: Double,
        requiredSuccesses: Int
    ) -> ProgressionProposal {
        guard let last = context.exposures.first else { return noData() }
        guard let currentWeight = referenceWeight(context) else {
            return ProgressionProposal(
                outcome: .notEnoughData,
                factors: [ProgressionFactor("Aucune charge connue pour cet exercice.")]
            )
        }

        let successes = consecutiveExposures(context) { reachedTopOfRange($0, context: context) }
        if successes >= requiredSuccesses {
            let target = roundedLoad(currentWeight + increment, context: context)
            return ProgressionProposal(
                outcome: .increaseLoad(from: currentWeight, to: target),
                factors: [
                    ProgressionFactor("\(successes) séance(s) d’affilée avec toutes les séries à \(context.repsUpper) répétitions."),
                    effortFactor(last, context: context),
                    ProgressionFactor("Retour au bas de la fourchette (\(context.repsLower) répétitions) à la nouvelle charge."),
                ].compactMap { $0 }
            )
        }

        let failures = consecutiveExposures(context) { !reachedBottomOfRange($0, context: context) }
        if failures >= ProgressionRule.failuresBeforeDeload {
            let target = roundedLoad(currentWeight * (1 - deloadFraction), context: context)
            return ProgressionProposal(
                outcome: .reduceLoad(from: currentWeight, to: target),
                factors: [
                    ProgressionFactor("\(failures) séances d’affilée sous \(context.repsLower) répétitions."),
                    ProgressionFactor("Réduction de \(Int(deloadFraction * 100)) % pour repartir sur une charge tenable."),
                ]
            )
        }

        return ProgressionProposal(
            outcome: .hold,
            factors: [
                ProgressionFactor("La fourchette \(context.repsLower)-\(context.repsUpper) n’est pas encore complète à cette charge."),
            ]
        )
    }

    /// Increment fixe de charge des que la seance est reussie.
    private static func linearLoad(
        _ context: ProgressionContext,
        increment: Double,
        requiredSuccesses: Int
    ) -> ProgressionProposal {
        guard !context.exposures.isEmpty else { return noData() }
        guard let currentWeight = referenceWeight(context) else {
            return ProgressionProposal(
                outcome: .notEnoughData,
                factors: [ProgressionFactor("Aucune charge connue pour cet exercice.")]
            )
        }

        let successes = consecutiveExposures(context) { reachedBottomOfRange($0, context: context) }
        if successes >= requiredSuccesses {
            let target = roundedLoad(currentWeight + increment, context: context)
            return ProgressionProposal(
                outcome: .increaseLoad(from: currentWeight, to: target),
                factors: [ProgressionFactor("\(successes) séance(s) d’affilée avec toutes les séries à au moins \(context.repsLower) répétitions.")]
            )
        }

        let failures = consecutiveExposures(context) { !reachedBottomOfRange($0, context: context) }
        if failures >= ProgressionRule.failuresBeforeDeload {
            let target = roundedLoad(currentWeight * (1 - deloadFraction), context: context)
            return ProgressionProposal(
                outcome: .reduceLoad(from: currentWeight, to: target),
                factors: [ProgressionFactor("\(failures) séances d’affilée sous l’objectif de répétitions.")]
            )
        }

        return ProgressionProposal(
            outcome: .hold,
            factors: [ProgressionFactor("Objectif de répétitions non atteint sur toutes les séries.")]
        )
    }

    private static func repsProgression(
        _ context: ProgressionContext,
        step: Int,
        maximum: Int
    ) -> ProgressionProposal {
        guard let last = context.exposures.first, !last.workingSets.isEmpty else { return noData() }
        guard reachedBottomOfRange(last, context: context) else {
            return ProgressionProposal(
                outcome: .hold,
                factors: [ProgressionFactor("L’objectif de \(context.repsLower) répétitions n’est pas atteint sur toutes les séries.")]
            )
        }
        let next = min(maximum, context.repsUpper + step)
        guard next > context.repsUpper else {
            return ProgressionProposal(
                outcome: .hold,
                factors: [ProgressionFactor("Le plafond de \(maximum) répétitions est atteint.")]
            )
        }
        return ProgressionProposal(
            outcome: .increaseReps(from: context.repsUpper, to: next),
            factors: [ProgressionFactor("Toutes les séries ont atteint \(context.repsLower) répétitions ou plus.")]
        )
    }

    private static func setsProgression(
        _ context: ProgressionContext,
        step: Int,
        maximum: Int
    ) -> ProgressionProposal {
        guard let last = context.exposures.first, !last.workingSets.isEmpty else { return noData() }
        guard last.workingSets.count >= context.prescribedSets,
              reachedBottomOfRange(last, context: context) else {
            return ProgressionProposal(
                outcome: .hold,
                factors: [ProgressionFactor("Les \(context.prescribedSets) séries prévues n’ont pas toutes atteint l’objectif.")]
            )
        }
        let next = min(maximum, context.prescribedSets + step)
        guard next > context.prescribedSets else {
            return ProgressionProposal(
                outcome: .hold,
                factors: [ProgressionFactor("Le plafond de \(maximum) séries est atteint.")]
            )
        }
        return ProgressionProposal(
            outcome: .increaseSets(from: context.prescribedSets, to: next),
            factors: [ProgressionFactor("Séance complète réussie : une série supplémentaire est proposée.")]
        )
    }

    private static func percentProgression(
        _ context: ProgressionContext,
        percent: Double,
        step: Double
    ) -> ProgressionProposal {
        guard let last = context.exposures.first, !last.workingSets.isEmpty else { return noData() }
        guard reachedBottomOfRange(last, context: context) else {
            return ProgressionProposal(
                outcome: .hold,
                factors: [ProgressionFactor("Le nombre de répétitions prévu au pourcentage actuel n’a pas été atteint.")]
            )
        }
        guard step > 0 else {
            return ProgressionProposal(outcome: .hold, factors: [ProgressionFactor("Aucun palier de pourcentage n’est configuré.")])
        }
        let next = min(100, percent + step)
        guard next > percent else {
            return ProgressionProposal(outcome: .hold, factors: [ProgressionFactor("Le pourcentage maximal est atteint.")])
        }
        return ProgressionProposal(
            outcome: .increasePercent(from: percent, to: next),
            factors: [ProgressionFactor("Séance réussie à \(Int(percent)) % du 1RM estimé.")]
        )
    }

    /// Cible d'effort : la charge suit le RIR reellement declare.
    private static func effortTarget(
        _ context: ProgressionContext,
        targetRepsInReserve: Int,
        increment: Double
    ) -> ProgressionProposal {
        guard let last = context.exposures.first else { return noData() }
        let declared = last.workingSets.compactMap { $0.effort?.repsInReserve }
        guard !declared.isEmpty else {
            return ProgressionProposal(
                outcome: .notEnoughData,
                factors: [ProgressionFactor("Aucun effort (RPE/RIR) n’a été saisi sur la dernière séance.")]
            )
        }
        guard let currentWeight = referenceWeight(context) else {
            return ProgressionProposal(outcome: .notEnoughData, factors: [ProgressionFactor("Aucune charge connue pour cet exercice.")])
        }

        let average = Double(declared.reduce(0, +)) / Double(declared.count)
        if average > Double(targetRepsInReserve) + 0.5 {
            let target = roundedLoad(currentWeight + increment, context: context)
            return ProgressionProposal(
                outcome: .increaseLoad(from: currentWeight, to: target),
                factors: [ProgressionFactor("RIR moyen déclaré de \(formatted(average)), au-dessus de la cible de \(targetRepsInReserve).")]
            )
        }
        if average < Double(targetRepsInReserve) - 0.5 {
            let target = roundedLoad(currentWeight - increment, context: context)
            return ProgressionProposal(
                outcome: .reduceLoad(from: currentWeight, to: target),
                factors: [ProgressionFactor("RIR moyen déclaré de \(formatted(average)), en dessous de la cible de \(targetRepsInReserve).")]
            )
        }
        return ProgressionProposal(
            outcome: .hold,
            factors: [ProgressionFactor("RIR moyen déclaré de \(formatted(average)), conforme à la cible.")]
        )
    }

    /// Tractions lestees ou assistees : le lest monte, l'assistance descend.
    private static func assistedOrWeighted(
        _ context: ProgressionContext,
        increment: Double,
        targetReps: Int
    ) -> ProgressionProposal {
        guard let last = context.exposures.first, !last.workingSets.isEmpty else { return noData() }
        let reachedTarget = last.workingSets.allSatisfy { $0.reps >= targetReps }
        guard reachedTarget else {
            return ProgressionProposal(
                outcome: .hold,
                factors: [ProgressionFactor("Objectif de \(targetReps) répétitions non atteint sur toutes les séries.")]
            )
        }
        let currentWeight = referenceWeight(context) ?? last.workingSets.map(\.weightKilograms).min() ?? 0

        switch context.loadKind {
        case .assisted:
            let target = max(0, roundedLoad(currentWeight - increment, context: context))
            return ProgressionProposal(
                outcome: .reduceLoad(from: currentWeight, to: target),
                factors: [
                    ProgressionFactor("Toutes les séries ont atteint \(targetReps) répétitions."),
                    ProgressionFactor("L’assistance diminue : l’effort augmente."),
                ]
            )
        case .weighted, .bodyweight:
            let target = roundedLoad(currentWeight + increment, context: context)
            return ProgressionProposal(
                outcome: .increaseLoad(from: currentWeight, to: target),
                factors: [
                    ProgressionFactor("Toutes les séries ont atteint \(targetReps) répétitions."),
                    ProgressionFactor("Le lest augmente de \(formatted(increment)) kg."),
                ]
            )
        case .external, .unknown:
            let target = roundedLoad(currentWeight + increment, context: context)
            return ProgressionProposal(
                outcome: .increaseLoad(from: currentWeight, to: target),
                factors: [ProgressionFactor("Toutes les séries ont atteint \(targetReps) répétitions.")]
            )
        }
    }

    /// Formats chronometres : allonger le travail ou raccourcir le repos.
    private static func timeProgression(
        _ context: ProgressionContext,
        workStep: Int,
        restStep: Int
    ) -> ProgressionProposal {
        guard let last = context.exposures.first, !last.workingSets.isEmpty else { return noData() }
        return ProgressionProposal(
            outcome: .adjustTime(workDeltaSeconds: workStep, restDeltaSeconds: restStep),
            factors: [
                ProgressionFactor("Bloc précédent terminé le \(shortDate(last.date))."),
                ProgressionFactor(timeFactorText(workStep: workStep, restStep: restStep)),
            ]
        )
    }

    // MARK: - Lecture de l'historique

    private static func noData() -> ProgressionProposal {
        ProgressionProposal(
            outcome: .notEnoughData,
            factors: [ProgressionFactor("Aucune séance passée avec cet exercice.")]
        )
    }

    /// Charge de reference : la prescription si elle existe, sinon la charge
    /// la plus lourde reellement utilisee lors de la derniere exposition.
    private static func referenceWeight(_ context: ProgressionContext) -> Double? {
        if let current = context.currentWeightKilograms, current > 0 { return current }
        guard let last = context.exposures.first else { return nil }
        let working = last.workingSets
        guard !working.isEmpty else { return nil }
        switch context.loadKind {
        case .assisted:
            // Moins d'assistance = plus dur : la reference est la plus FAIBLE.
            return working.map(\.weightKilograms).min()
        case .external, .weighted, .bodyweight, .unknown:
            return working.map(\.weightKilograms).max()
        }
    }

    /// Nombre d'expositions consecutives, en partant de la plus recente,
    /// satisfaisant la condition.
    private static func consecutiveExposures(
        _ context: ProgressionContext,
        where condition: (ExerciseExposure) -> Bool
    ) -> Int {
        var count = 0
        for exposure in context.exposures {
            guard !exposure.workingSets.isEmpty, condition(exposure) else { break }
            count += 1
        }
        return count
    }

    /// Toutes les series de travail atteignent le HAUT de la fourchette, et
    /// l'effort declare respecte la cible quand elle existe.
    private static func reachedTopOfRange(_ exposure: ExerciseExposure, context: ProgressionContext) -> Bool {
        let working = exposure.workingSets
        guard working.count >= max(1, context.prescribedSets) else { return false }
        guard working.allSatisfy({ $0.reps >= context.repsUpper }) else { return false }
        guard let target = context.targetEffort?.repsInReserve else { return true }
        // Un effort declare PLUS FAIBLE que la cible signifie une serie plus
        // dure que prevu : la charge ne doit pas monter dans ce cas.
        let declared = working.compactMap { $0.effort?.repsInReserve }
        guard !declared.isEmpty else { return true }
        return declared.allSatisfy { $0 >= target }
    }

    private static func reachedBottomOfRange(_ exposure: ExerciseExposure, context: ProgressionContext) -> Bool {
        let working = exposure.workingSets
        guard working.count >= max(1, context.prescribedSets) else { return false }
        return working.allSatisfy { $0.reps >= context.repsLower }
    }

    private static func effortFactor(_ exposure: ExerciseExposure, context: ProgressionContext) -> ProgressionFactor? {
        let declared = exposure.workingSets.compactMap { $0.effort?.repsInReserve }
        guard !declared.isEmpty else { return nil }
        let average = Double(declared.reduce(0, +)) / Double(declared.count)
        return ProgressionFactor("RIR moyen déclaré de \(formatted(average)) sur la dernière séance.")
    }

    /// Arrondi a un palier de chargement reellement disponible.
    private static func roundedLoad(_ value: Double, context: ProgressionContext) -> Double {
        let increment = context.availableIncrementKilograms > 0 ? context.availableIncrementKilograms : 2.5
        guard value > 0 else { return 0 }
        return Units.roundedForDisplay((value / increment).rounded() * increment)
    }

    private static func timeFactorText(workStep: Int, restStep: Int) -> String {
        var parts: [String] = []
        if workStep > 0 { parts.append("travail +\(workStep) s") }
        if workStep < 0 { parts.append("travail \(workStep) s") }
        if restStep < 0 { parts.append("repos \(restStep) s") }
        if restStep > 0 { parts.append("repos +\(restStep) s") }
        return parts.isEmpty ? "Aucun ajustement configuré." : parts.joined(separator: ", ") + "."
    }

    private static func formatted(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    private static func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
