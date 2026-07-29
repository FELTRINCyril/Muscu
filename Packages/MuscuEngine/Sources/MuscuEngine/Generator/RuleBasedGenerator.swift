import Foundation

/// Erreurs du generateur de programme.
public enum GeneratorError: Error, Sendable {
    case noBlueprintAvailable
}

/// Contrat commun au generateur local base sur des regles et a un futur generateur IA.
public protocol ProgramGenerator {
    func generate(_ input: GeneratorInput) throws -> DraftProgram
}

/// Generateur de programme base sur des regles deterministes (pas d'IA).
///
/// Algorithme (voir spec) :
/// 1. Choix du split (blueprint de sessions) selon la preference ou le split recommande.
/// 2. Parametres par objectif (sets/reps/repos/%1RM).
/// 3. Volume par experience et duree de seance.
/// 4. Selection des exercices par slot (muscle + equipement autorise) : priorite a la
///    liste blanche StapleExercises (tri par rang puis id), repli catalogue complet
///    (tri deterministe par id) si aucun classique ne matche.
/// 5. Ajout d'un slot isolation pour les muscles prioritaires deja travailles.
/// 6. Nommage du programme et des sessions.
public struct RuleBasedGenerator: ProgramGenerator {
    private let catalog: ExerciseCatalog

    public init(catalog: ExerciseCatalog) {
        self.catalog = catalog
    }

    public func generate(_ input: GeneratorInput) throws -> DraftProgram {
        let blueprints = try resolveBlueprints(input)
        let countRange = Self.experienceCountRange(input.experience, sessionMinutes: input.sessionMinutes)

        let sessions = blueprints.map { blueprint in
            buildSession(blueprint: blueprint, input: input, countRange: countRange)
        }

        return DraftProgram(
            name: Self.programName(goal: input.goal, daysPerWeek: input.daysPerWeek),
            notes: "",
            sessions: sessions
        )
    }

    // MARK: - Etape 1 : split

    private func resolveBlueprints(_ input: GeneratorInput) throws -> [SessionBlueprint] {
        if input.splitPreference == .auto {
            guard let first = SplitTemplates.recommended(daysPerWeek: input.daysPerWeek).first else {
                throw GeneratorError.noBlueprintAvailable
            }
            return first.sessions
        }
        if let blueprint = SplitTemplates.blueprint(for: input.splitPreference, daysPerWeek: input.daysPerWeek) {
            return blueprint
        }
        // Fallback auto si la preference demandee n'existe pas pour ce nombre de jours.
        guard let fallback = SplitTemplates.recommended(daysPerWeek: input.daysPerWeek).first else {
            throw GeneratorError.noBlueprintAvailable
        }
        return fallback.sessions
    }

    // MARK: - Etape 3 : volume par experience et duree de seance

    private static func experienceCountRange(_ experience: Experience, sessionMinutes: Int) -> (min: Int, max: Int) {
        var range: (min: Int, max: Int)
        switch experience {
        case .beginner:
            range = (3, 5)
        case .intermediate:
            range = (5, 6)
        case .advanced:
            range = (6, 7)
        }
        switch sessionMinutes {
        case 45:
            range = (max(1, range.min - 2), max(1, range.max - 2))
        case 90:
            range = (range.min + 1, range.max + 1)
        default:
            break
        }
        return range
    }

    // MARK: - Etapes 3-5 : construction d'une session

    private func buildSession(blueprint: SessionBlueprint, input: GeneratorInput, countRange: (min: Int, max: Int)) -> DraftSession {
        guard !blueprint.slots.isEmpty else {
            return DraftSession(name: blueprint.name, warmupEnabled: true, exercises: [])
        }

        var slots = blueprint.slots
        let targetCount = min(max(slots.count, countRange.min), countRange.max)

        if slots.count > targetCount {
            slots = Array(slots.prefix(targetCount))
        } else if slots.count < targetCount {
            var cursor = 0
            while slots.count < targetCount {
                let base = blueprint.slots[cursor % blueprint.slots.count]
                slots.append(MuscleSlot(muscle: base.muscle, compound: false))
                cursor += 1
            }
        }

        // Etape 5 : muscles prioritaires deja travailles -> slot isolation supplementaire en fin de session.
        for muscle in input.priorityMuscles where blueprint.slots.contains(where: { $0.muscle == muscle }) {
            slots.append(MuscleSlot(muscle: muscle, compound: false))
        }

        // Calisthenics force l'equipement "au poids du corps" quel que soit le choix utilisateur.
        let equipmentForSelection: TrainingEquipment = (input.goal == .calisthenics) ? .bodyweight : input.equipment

        var used = Set<String>()
        var picks: [(muscle: String, exercise: CatalogExercise)] = []
        for slot in slots {
            guard let chosen = pickExercise(
                muscle: slot.muscle,
                preferCompound: slot.compound,
                equipment: equipmentForSelection,
                avoidAreas: input.avoidAreas,
                variation: input.variation,
                used: used
            ) else { continue }
            used.insert(chosen.id)
            picks.append((slot.muscle, chosen))
        }

        // Objectif "pullUpProgress" : garantir une traction dans chaque session de tirage (slot "lats").
        if input.goal == .pullUpProgress, blueprint.slots.contains(where: { $0.muscle == "lats" }) {
            let alreadyHasTraction = picks.contains { Self.isTractionExercise($0.exercise) }
            if !alreadyHasTraction, let pullUp = findPullUpExercise(avoidAreas: input.avoidAreas) {
                if let latsIndex = picks.firstIndex(where: { $0.muscle == "lats" }) {
                    picks[latsIndex] = ("lats", pullUp)
                } else {
                    picks.append(("lats", pullUp))
                }
            }
        }

        let exercises = picks.map { makeDraftExercise($0.exercise, goal: input.goal, experience: input.experience) }
        return DraftSession(name: blueprint.name, warmupEnabled: true, exercises: exercises)
    }

    // MARK: - Etape 4 : selection d'exercices (deterministe : tri par id)

    private func pickExercise(
        muscle: String,
        preferCompound: Bool,
        equipment: TrainingEquipment,
        avoidAreas: [String],
        variation: Int,
        used: Set<String>
    ) -> CatalogExercise? {
        let candidates = catalog.all
            .filter { isCandidate($0, muscle: muscle, equipment: equipment, avoidAreas: avoidAreas) }

        // Priorite a la liste blanche des classiques, tries par (rang, id) :
        // le rang departage au sein d'un groupe, l'id departage entre groupes.
        let staples = candidates
            .compactMap { exercise -> (exercise: CatalogExercise, staple: StapleExercise)? in
                guard let staple = StapleExercises.staple(for: exercise.id) else { return nil }
                return (exercise, staple)
            }
            .sorted {
                if $0.staple.rank != $1.staple.rank { return $0.staple.rank < $1.staple.rank }
                return $0.exercise.id < $1.exercise.id
            }
            .map(\.exercise)

        let preferredMechanic = preferCompound ? "compound" : "isolation"
        let preferred = staples.filter { $0.mechanic == preferredMechanic && !used.contains($0.id) }
        if !preferred.isEmpty {
            return preferred[variation % preferred.count]
        }
        if let anyStaple = staples.first(where: { !used.contains($0.id) }) {
            return anyStaple
        }

        // Repli : aucun classique ne convient (muscle non couvert, equipement
        // restreint...) -> comportement historique sur le catalogue complet.
        let fallback = candidates.sorted { $0.id < $1.id }
        if let match = fallback.first(where: { $0.mechanic == preferredMechanic && !used.contains($0.id) }) {
            return match
        }
        return fallback.first { !used.contains($0.id) }
    }

    // Visible pour les tests uniquement (le package est importe @testable).
    func pickExerciseForTesting(
        muscle: String, preferCompound: Bool, equipment: TrainingEquipment,
        avoidAreas: [String], used: Set<String>, variation: Int = 0
    ) -> CatalogExercise? {
        pickExercise(muscle: muscle, preferCompound: preferCompound,
                     equipment: equipment, avoidAreas: avoidAreas, variation: variation, used: used)
    }

    private func isCandidate(_ exercise: CatalogExercise, muscle: String, equipment: TrainingEquipment, avoidAreas: [String]) -> Bool {
        guard exercise.primaryMuscles.contains(muscle) else { return false }
        guard exercise.category != "stretching" else { return false }
        guard exercise.equipment != "foam roll" else { return false }
        guard Self.isEquipmentAllowed(exercise.equipment, for: equipment) else { return false }
        if avoidAreas.contains(where: { exercise.primaryMuscles.contains($0) }) { return false }
        return true
    }

    private static func isEquipmentAllowed(_ equipment: String?, for training: TrainingEquipment) -> Bool {
        switch training {
        case .fullGym:
            return true
        case .homeGym:
            guard let equipment else { return true }
            return ["dumbbell", "body only", "bands", "kettlebells", "exercise ball", "medicine ball"].contains(equipment)
        case .bodyweight:
            guard let equipment else { return true }
            return ["body only", "bands"].contains(equipment)
        }
    }

    // MARK: - pullUpProgress : recherche d'une traction

    private func findPullUpExercise(avoidAreas: [String]) -> CatalogExercise? {
        catalog.all
            .filter { exercise in
                exercise.primaryMuscles.contains("lats")
                    && exercise.category != "stretching"
                    && exercise.equipment != "foam roll"
                    && Self.isEquipmentAllowed(exercise.equipment, for: .bodyweight)
                    && !avoidAreas.contains(where: { exercise.primaryMuscles.contains($0) })
                    && Self.isTractionExercise(exercise)
            }
            .sorted { $0.id < $1.id }
            .first
    }

    private static func isTractionExercise(_ exercise: CatalogExercise) -> Bool {
        for raw in [exercise.name, exercise.nameFr] {
            let normalized = normalizedText(raw)
            if normalized.contains("traction")
                || normalized.contains("pull-up")
                || normalized.contains("pullup")
                || normalized.contains("pull up") {
                return true
            }
        }
        return false
    }

    private static func normalizedText(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
    }

    // MARK: - Etape 2 : parametres par objectif

    private func makeDraftExercise(_ exercise: CatalogExercise, goal: Goal, experience: Experience) -> DraftExercise {
        let isCompoundMechanic = exercise.mechanic == "compound"
        let reps = Self.repsRange(for: goal, isCompound: isCompoundMechanic)
        return DraftExercise(
            exerciseId: exercise.id,
            displayName: exercise.nameFr,
            sets: Self.sets(for: goal, experience: experience),
            repsLower: reps.lower,
            repsUpper: reps.upper,
            restSeconds: Self.restSeconds(for: goal),
            percentOneRepMax: Self.percentOneRepMax(goal: goal, isCompound: isCompoundMechanic)
        )
    }

    private static func repsRange(for goal: Goal, isCompound: Bool) -> (lower: Int, upper: Int) {
        switch goal {
        case .hypertrophy, .pullUpProgress:
            return isCompound ? (6, 12) : (8, 12)
        case .strength:
            return (3, 6)
        case .fatLoss, .endurance:
            return (12, 20)
        case .calisthenics:
            return (5, 12)
        }
    }

    private static func restSeconds(for goal: Goal) -> Int {
        switch goal {
        case .hypertrophy, .pullUpProgress, .calisthenics:
            return 90
        case .strength:
            return 180
        case .fatLoss, .endurance:
            return 45
        }
    }

    private static func sets(for goal: Goal, experience: Experience) -> Int {
        switch goal {
        case .hypertrophy, .pullUpProgress:
            switch experience {
            case .beginner: return 3
            case .intermediate: return 3
            case .advanced: return 4
            }
        case .strength:
            switch experience {
            case .beginner: return 3
            case .intermediate: return 4
            case .advanced: return 5
            }
        case .fatLoss, .endurance, .calisthenics:
            return 3
        }
    }

    private static func percentOneRepMax(goal: Goal, isCompound: Bool) -> Double? {
        guard goal == .strength, isCompound else { return nil }
        return 80.0
    }

    // MARK: - Etape 6 : nommage

    private static func goalLabelFr(_ goal: Goal) -> String {
        switch goal {
        case .hypertrophy: return "Prise de masse"
        case .strength: return "Force"
        case .fatLoss: return "Perte de poids"
        case .endurance: return "Endurance"
        case .pullUpProgress: return "Progression tractions"
        case .calisthenics: return "Calisthenics"
        }
    }

    private static func programName(goal: Goal, daysPerWeek: Int) -> String {
        "Programme \(goalLabelFr(goal)) \(daysPerWeek)j/semaine"
    }
}
