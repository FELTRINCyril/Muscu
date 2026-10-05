import Foundation

/// Position exacte dans le deroule d'une seance. Entierement serialisable :
/// c'est elle qui est persistee pour reprendre une seance interrompue.
public struct WorkoutPosition: Codable, Equatable, Hashable, Sendable {
    /// Index du noeud courant dans `WorkoutPlan.nodes`.
    public var nodeIndex: Int
    /// Tour courant dans le groupe (0-based). Toujours 0 hors groupe.
    public var round: Int
    /// Exercice courant dans le groupe (0-based). Toujours 0 hors groupe.
    public var memberIndex: Int
    /// Serie courante de l'exercice (0-based). Pour un groupe, la serie vaut
    /// le tour : c'est `round` qui avance.
    public var setIndex: Int
    /// Palier d'un dropset, mini-serie d'un rest-pause ou d'un myo-reps.
    /// Zero = serie principale.
    public var subSetIndex: Int

    public init(nodeIndex: Int = 0, round: Int = 0, memberIndex: Int = 0, setIndex: Int = 0, subSetIndex: Int = 0) {
        self.nodeIndex = nodeIndex
        self.round = round
        self.memberIndex = memberIndex
        self.setIndex = setIndex
        self.subSetIndex = subSetIndex
    }

    public static let start = WorkoutPosition()
}

/// Pourquoi un repos est propose. Permet a l'interface d'expliquer le chrono
/// sans deviner, et de ne jamais proposer un repos apres la derniere serie.
public enum RestReason: String, Codable, Equatable, Sendable {
    case betweenSets
    case betweenExercisesInGroup
    case betweenRounds
    case betweenSubSets
    case stationTransition
}

/// Consigne de repos produite par la machine a etats.
public struct RestInstruction: Codable, Equatable, Sendable {
    public var seconds: Int
    public var reason: RestReason

    public init(seconds: Int, reason: RestReason) {
        self.seconds = seconds
        self.reason = reason
    }
}

/// Ce que l'interface doit afficher a la position courante.
public enum WorkoutStep: Equatable, Sendable {
    /// Saisie d'une serie (ou d'un palier / d'une mini-serie).
    case logSet(WorkoutSetTarget)
    /// Bloc chronometre : l'ecran dedie prend la main.
    case timedBlock(WorkoutExercisePlan)
    /// Toute la seance est terminee.
    case finished
}

/// Description de la serie attendue, telle que l'interface doit la presenter.
public struct WorkoutSetTarget: Equatable, Sendable {
    public var exercise: WorkoutExercisePlan
    public var groupId: UUID
    public var groupKind: WorkoutGroupKind
    /// Tour affiche (1-based) et total de tours du groupe.
    public var round: Int
    public var totalRounds: Int
    /// Position dans le groupe (1-based) et nombre d'exercices du groupe.
    public var memberPosition: Int
    public var totalMembers: Int
    /// Serie affichee (1-based) et total de series de cet exercice.
    public var setNumber: Int
    public var totalSets: Int
    /// Palier de dropset / mini-serie (0 = serie principale).
    public var subSetIndex: Int
    /// Repetitions visees, quand elles sont connues.
    public var targetRepsLower: Int
    public var targetRepsUpper: Int

    public var isSubSet: Bool { subSetIndex > 0 }

    public init(
        exercise: WorkoutExercisePlan,
        groupId: UUID,
        groupKind: WorkoutGroupKind,
        round: Int,
        totalRounds: Int,
        memberPosition: Int,
        totalMembers: Int,
        setNumber: Int,
        totalSets: Int,
        subSetIndex: Int,
        targetRepsLower: Int,
        targetRepsUpper: Int
    ) {
        self.exercise = exercise
        self.groupId = groupId
        self.groupKind = groupKind
        self.round = round
        self.totalRounds = totalRounds
        self.memberPosition = memberPosition
        self.totalMembers = totalMembers
        self.setNumber = setNumber
        self.totalSets = totalSets
        self.subSetIndex = subSetIndex
        self.targetRepsLower = targetRepsLower
        self.targetRepsUpper = targetRepsUpper
    }
}

/// Ce que l'utilisateur vient de faire, pour decider de la suite. Le moteur
/// ne decide jamais a la place de l'utilisateur : il recoit le resultat.
public struct WorkoutSetOutcome: Equatable, Sendable {
    public var reps: Int
    public var weightKilograms: Double
    /// L'utilisateur a decide d'arreter les mini-series (rest-pause, myo-reps).
    public var stopsSubSets: Bool

    public init(reps: Int, weightKilograms: Double = 0, stopsSubSets: Bool = false) {
        self.reps = reps
        self.weightKilograms = weightKilograms
        self.stopsSubSets = stopsSubSets
    }
}

/// Machine a etats unique du deroule d'une seance. Pure et deterministe :
/// elle ne connait ni le stockage, ni les chronos reels, ni les vues. Elle
/// repond a deux questions seulement : « qu'affiche-t-on maintenant ? » et
/// « ou va-t-on apres ce resultat ? ».
public enum WorkoutStateMachine {
    // MARK: - Lecture

    /// Ramene une position eventuellement incoherente (programme modifie,
    /// donnee corrompue) dans les bornes du plan, sans jamais planter.
    public static func clamp(_ position: WorkoutPosition, in plan: WorkoutPlan) -> WorkoutPosition {
        var clamped = position
        clamped.nodeIndex = max(0, position.nodeIndex)
        guard clamped.nodeIndex < plan.nodes.count else {
            return WorkoutPosition(nodeIndex: plan.nodes.count)
        }
        let node = plan.nodes[clamped.nodeIndex]
        guard !node.exercises.isEmpty else {
            return advanceToNextNode(from: clamped, in: plan)
        }
        clamped.memberIndex = min(max(0, position.memberIndex), node.exercises.count - 1)
        clamped.round = min(max(0, position.round), max(0, node.effectiveRounds - 1))
        let exercise = node.exercises[clamped.memberIndex]
        // Dans un groupe, l'avancement se fait par tour : la serie affichee
        // suit le tour et n'a pas d'existence propre.
        clamped.setIndex = node.isGroup
            ? clamped.round
            : min(max(0, position.setIndex), max(0, exercise.slotCount - 1))
        clamped.subSetIndex = max(0, position.subSetIndex)
        return clamped
    }

    /// Etape a afficher a cette position.
    public static func step(at position: WorkoutPosition, in plan: WorkoutPlan) -> WorkoutStep {
        let position = clamp(position, in: plan)
        guard position.nodeIndex < plan.nodes.count else { return .finished }
        let node = plan.nodes[position.nodeIndex]
        guard position.memberIndex < node.exercises.count else { return .finished }
        let exercise = node.exercises[position.memberIndex]

        if exercise.format.isTimed {
            return .timedBlock(exercise)
        }

        return .logSet(
            WorkoutSetTarget(
                exercise: exercise,
                groupId: node.id,
                groupKind: node.kind,
                round: position.round + 1,
                totalRounds: node.effectiveRounds,
                memberPosition: position.memberIndex + 1,
                totalMembers: node.exercises.count,
                setNumber: position.setIndex + 1,
                totalSets: node.isGroup ? node.effectiveRounds : exercise.slotCount,
                subSetIndex: position.subSetIndex,
                targetRepsLower: targetRepsLower(for: exercise, at: position),
                targetRepsUpper: targetRepsUpper(for: exercise, at: position)
            )
        )
    }

    public static func isFinished(_ position: WorkoutPosition, in plan: WorkoutPlan) -> Bool {
        clamp(position, in: plan).nodeIndex >= plan.nodes.count
    }

    /// Progression globale en creneaux valides / total, pour une barre de
    /// progression honnete (les sous-series ne gonflent pas le total).
    public static func progress(at position: WorkoutPosition, in plan: WorkoutPlan) -> (completed: Int, total: Int) {
        let total = plan.nodes.reduce(0) { partial, node in
            partial + (node.isGroup ? node.effectiveRounds * node.exercises.count : (node.exercises.first?.slotCount ?? 0))
        }
        let clamped = clamp(position, in: plan)
        var completed = 0
        for (index, node) in plan.nodes.enumerated() {
            let nodeSlots = node.isGroup ? node.effectiveRounds * node.exercises.count : (node.exercises.first?.slotCount ?? 0)
            if index < clamped.nodeIndex {
                completed += nodeSlots
            } else if index == clamped.nodeIndex {
                completed += node.isGroup
                    ? clamped.round * node.exercises.count + clamped.memberIndex
                    : clamped.setIndex
            }
        }
        return (min(completed, total), total)
    }

    // MARK: - Avancement

    /// Position suivante apres le resultat d'une serie, et le repos a lancer.
    ///
    /// Aucun repos n'est propose lorsque la seance est terminee : un chrono
    /// qui tourne sur un ecran de fin n'a aucun sens.
    public static func advance(
        from position: WorkoutPosition,
        in plan: WorkoutPlan,
        outcome: WorkoutSetOutcome
    ) -> (position: WorkoutPosition, rest: RestInstruction?) {
        let position = clamp(position, in: plan)
        guard position.nodeIndex < plan.nodes.count else {
            return (WorkoutPosition(nodeIndex: plan.nodes.count), nil)
        }
        let node = plan.nodes[position.nodeIndex]
        guard position.memberIndex < node.exercises.count else {
            return (advanceToNextNode(from: position, in: plan), nil)
        }
        let exercise = node.exercises[position.memberIndex]

        // 1. Sous-series (dropset, rest-pause, myo-reps) : elles prolongent la
        //    serie courante avant tout autre avancement.
        if let next = nextSubSet(for: exercise, at: position, outcome: outcome) {
            return next
        }

        // 2. Groupe : passer a l'exercice suivant du tour, puis au tour suivant.
        if node.isGroup {
            return advanceWithinGroup(node: node, position: position, in: plan)
        }

        // 3. Exercice seul : serie suivante, puis noeud suivant.
        if position.setIndex + 1 < exercise.slotCount {
            var next = position
            next.setIndex += 1
            next.subSetIndex = 0
            return (next, restAfterSet(exercise: exercise, at: position, outcome: outcome))
        }

        let next = advanceToNextNode(from: position, in: plan)
        let isFinished = next.nodeIndex >= plan.nodes.count
        return (next, isFinished ? nil : restAfterSet(exercise: exercise, at: position, outcome: outcome))
    }

    /// Avancement force, sans resultat : « passer l'exercice ». Le repos n'est
    /// jamais declenche, puisque rien n'a ete fait.
    public static func skipExercise(from position: WorkoutPosition, in plan: WorkoutPlan) -> WorkoutPosition {
        let position = clamp(position, in: plan)
        guard position.nodeIndex < plan.nodes.count else { return position }
        let node = plan.nodes[position.nodeIndex]

        // Dans un groupe, passer un exercice ne casse pas le groupe : on
        // reprend au suivant du meme tour.
        if node.isGroup, position.memberIndex + 1 < node.exercises.count {
            var next = position
            next.memberIndex += 1
            next.subSetIndex = 0
            return next
        }
        if node.isGroup, position.round + 1 < node.effectiveRounds {
            return WorkoutPosition(nodeIndex: position.nodeIndex, round: position.round + 1, setIndex: position.round + 1)
        }
        return advanceToNextNode(from: position, in: plan)
    }

    // MARK: - Prive

    private static func advanceWithinGroup(
        node: WorkoutNode,
        position: WorkoutPosition,
        in plan: WorkoutPlan
    ) -> (position: WorkoutPosition, rest: RestInstruction?) {
        if position.memberIndex + 1 < node.exercises.count {
            var next = position
            next.memberIndex += 1
            next.subSetIndex = 0
            // Repos court entre deux exercices enchaines : zero est valide.
            let seconds = max(node.restBetweenExercisesSeconds, node.transitionSeconds)
            let reason: RestReason = node.transitionSeconds > node.restBetweenExercisesSeconds
                ? .stationTransition
                : .betweenExercisesInGroup
            return (next, seconds > 0 ? RestInstruction(seconds: seconds, reason: reason) : nil)
        }

        if position.round + 1 < node.effectiveRounds {
            let next = WorkoutPosition(
                nodeIndex: position.nodeIndex,
                round: position.round + 1,
                memberIndex: 0,
                setIndex: position.round + 1
            )
            let seconds = node.restBetweenRoundsSeconds
            return (next, seconds > 0 ? RestInstruction(seconds: seconds, reason: .betweenRounds) : nil)
        }

        let next = advanceToNextNode(from: position, in: plan)
        let isFinished = next.nodeIndex >= plan.nodes.count
        let seconds = node.restBetweenRoundsSeconds
        return (next, isFinished || seconds <= 0 ? nil : RestInstruction(seconds: seconds, reason: .betweenRounds))
    }

    /// Saute les noeuds vides pour ne jamais s'arreter sur un groupe sans
    /// exercice (possible apres une suppression).
    private static func advanceToNextNode(from position: WorkoutPosition, in plan: WorkoutPlan) -> WorkoutPosition {
        var index = position.nodeIndex + 1
        while index < plan.nodes.count, plan.nodes[index].exercises.isEmpty {
            index += 1
        }
        return WorkoutPosition(nodeIndex: index)
    }

    /// Sous-serie suivante d'un dropset, rest-pause ou myo-reps, ou `nil` si
    /// la serie principale est terminee.
    private static func nextSubSet(
        for exercise: WorkoutExercisePlan,
        at position: WorkoutPosition,
        outcome: WorkoutSetOutcome
    ) -> (position: WorkoutPosition, rest: RestInstruction?)? {
        switch exercise.format {
        case .dropset:
            guard let dropset = exercise.dropset, dropset.isValid else { return nil }
            guard position.subSetIndex < dropset.drops.count else { return nil }
            var next = position
            next.subSetIndex += 1
            let rest = dropset.restSeconds > 0
                ? RestInstruction(seconds: dropset.restSeconds, reason: .betweenSubSets)
                : nil
            return (next, rest)

        case .restPause:
            guard let plan = exercise.restPause, plan.isValid else { return nil }
            // L'utilisateur peut arreter, et le seuil de repetitions arrete
            // aussi la serie : ni l'un ni l'autre n'est un echec.
            guard !outcome.stopsSubSets,
                  position.subSetIndex < plan.maximumMiniSets,
                  position.subSetIndex == 0 || outcome.reps >= plan.minimumReps else { return nil }
            var next = position
            next.subSetIndex += 1
            let rest = plan.microRestSeconds > 0
                ? RestInstruction(seconds: plan.microRestSeconds, reason: .betweenSubSets)
                : nil
            return (next, rest)

        case .myoReps:
            guard let plan = exercise.myoReps, plan.isValid else { return nil }
            guard !outcome.stopsSubSets, position.subSetIndex < plan.maximumMiniSets else { return nil }
            // Une mini-serie qui n'atteint plus la cible met fin au bloc.
            if position.subSetIndex > 0, outcome.reps < plan.miniSetReps { return nil }
            var next = position
            next.subSetIndex += 1
            let rest = plan.restSeconds > 0
                ? RestInstruction(seconds: plan.restSeconds, reason: .betweenSubSets)
                : nil
            return (next, rest)

        case .classic, .pyramid, .intervals, .emom, .amrap, .forTime:
            return nil
        }
    }

    private static func restAfterSet(
        exercise: WorkoutExercisePlan,
        at position: WorkoutPosition,
        outcome: WorkoutSetOutcome
    ) -> RestInstruction? {
        let seconds: Int
        switch exercise.format {
        case .pyramid:
            // Meme calcul que l'apercu du deroule et de l'editeur : le repos
            // annonce est celui qui est lance. Aucun repos apres le dernier
            // palier, meme si un exercice suit (decision 0019).
            seconds = exercise.pyramidRest(afterStep: position.setIndex, repsDone: outcome.reps) ?? 0
        case .classic, .dropset, .restPause, .myoReps:
            seconds = exercise.restSeconds
        case .intervals, .emom, .amrap, .forTime:
            // Les formats chronometres gerent eux-memes leurs segments.
            seconds = 0
        }
        return seconds > 0 ? RestInstruction(seconds: seconds, reason: .betweenSets) : nil
    }

    private static func targetRepsLower(for exercise: WorkoutExercisePlan, at position: WorkoutPosition) -> Int {
        switch exercise.format {
        case .pyramid:
            guard position.setIndex < exercise.pyramidReps.count else { return exercise.repsLower }
            return exercise.pyramidReps[position.setIndex]
        case .myoReps:
            guard let plan = exercise.myoReps else { return exercise.repsLower }
            return position.subSetIndex == 0 ? plan.activationRepsLower : plan.miniSetReps
        default:
            return exercise.repsLower
        }
    }

    private static func targetRepsUpper(for exercise: WorkoutExercisePlan, at position: WorkoutPosition) -> Int {
        switch exercise.format {
        case .pyramid:
            guard position.setIndex < exercise.pyramidReps.count else { return exercise.repsUpper }
            return exercise.pyramidReps[position.setIndex]
        case .myoReps:
            guard let plan = exercise.myoReps else { return exercise.repsUpper }
            return position.subSetIndex == 0 ? plan.activationRepsUpper : plan.miniSetReps
        default:
            return exercise.repsUpper
        }
    }
}
