import Foundation

/// Erreurs du generateur de programme.
public enum GeneratorError: LocalizedError, Sendable {
    case noBlueprintAvailable
    case noSuitableExercises

    public var errorDescription: String? {
        switch self {
        case .noBlueprintAvailable:
            return "Aucun split n’est disponible pour ce nombre de jours."
        case .noSuitableExercises:
            return "Le matériel et les zones à éviter ne laissent aucun exercice sûr pour au moins une séance. Modifiez ces choix."
        }
    }
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
/// 4. Selection des exercices par slot (muscle + equipement autorise, tri deterministe par id).
/// 5. Ajout d'un slot isolation pour les muscles prioritaires deja travailles.
/// 6. Nommage du programme et des sessions.
public struct RuleBasedGenerator: ProgramGenerator, Sendable {
    let catalog: ExerciseCatalog

    public init(catalog: ExerciseCatalog) {
        self.catalog = catalog
    }

    public func generate(_ input: GeneratorInput) throws -> DraftProgram {
        let blueprints = try resolveBlueprints(input)
        let countRange = Self.experienceCountRange(input.experience, sessionMinutes: input.sessionMinutes)

        let sessions = blueprints.enumerated().map { index, blueprint in
            buildSession(blueprint: blueprint, input: input, countRange: countRange, sessionIndex: index)
        }
        guard sessions.allSatisfy({ !$0.exercises.isEmpty }) else {
            throw GeneratorError.noSuitableExercises
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

    private func buildSession(
        blueprint: SessionBlueprint,
        input: GeneratorInput,
        countRange: (min: Int, max: Int),
        sessionIndex: Int
    ) -> DraftSession {
        guard !blueprint.slots.isEmpty else {
            return DraftSession(name: blueprint.name, warmupEnabled: true, exercises: [])
        }

        var slots = blueprint.slots
        let durationLimit = Self.maximumExerciseCount(
            goal: input.goal,
            experience: input.experience,
            sessionMinutes: input.sessionMinutes
        )
        let targetCount = min(min(max(slots.count, countRange.min), countRange.max), durationLimit)

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
        for muscle in input.priorityMuscles
        where slots.count < durationLimit && blueprint.slots.contains(where: { $0.muscle == muscle }) {
            slots.append(MuscleSlot(muscle: muscle, compound: false))
        }

        // Calisthenics force l'equipement "au poids du corps" quel que soit le choix utilisateur.
        let equipmentForSelection: TrainingEquipment = (input.goal == .calisthenics) ? .bodyweight : input.equipment

        var used = Set<String>()
        var picks: [(muscle: String, exercise: CatalogExercise)] = []
        for (slotIndex, slot) in slots.enumerated() {
            guard let chosen = pickExercise(
                muscle: slot.muscle,
                preferCompound: slot.compound,
                equipment: equipmentForSelection,
                experience: input.experience,
                avoidAreas: input.avoidAreas,
                excluded: Set(input.excludedExerciseIds),
                inventory: input.inventory,
                used: used,
                rotation: sessionIndex + slotIndex
            ) else { continue }
            used.insert(chosen.id)
            picks.append((slot.muscle, chosen))
        }

        // Objectif "pullUpProgress" : garantir une traction dans chaque session de tirage (slot "lats").
        if input.goal == .pullUpProgress, blueprint.slots.contains(where: { $0.muscle == "lats" }) {
            let alreadyHasTraction = picks.contains { Self.isTractionExercise($0.exercise) }
            if !alreadyHasTraction, let pullUp = findPullUpExercise(
                experience: input.experience,
                avoidAreas: input.avoidAreas,
                excluded: Set(input.excludedExerciseIds)
            ) {
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
        experience: Experience,
        avoidAreas: [String],
        excluded: Set<String>,
        inventory: EquipmentInventory?,
        used: Set<String>,
        rotation: Int
    ) -> CatalogExercise? {
        let candidates = catalog.all
            .filter {
                isCandidate(
                    $0,
                    muscle: muscle,
                    equipment: equipment,
                    experience: experience,
                    avoidAreas: avoidAreas,
                    excluded: excluded,
                    inventory: inventory
                )
            }
            .sorted { Self.selectionScore($0, preferredCompound: preferCompound, experience: experience) < Self.selectionScore($1, preferredCompound: preferCompound, experience: experience) }
            .filter { !used.contains($0.id) }

        guard !candidates.isEmpty else { return nil }
        // La rotation reste deterministe, mais evite de recommencer chaque jour
        // par le meme premier exercice du catalogue.
        return candidates[rotation % candidates.count]
    }

    private func isCandidate(
        _ exercise: CatalogExercise,
        muscle: String,
        equipment: TrainingEquipment,
        experience: Experience,
        avoidAreas: [String],
        excluded: Set<String>,
        inventory: EquipmentInventory? = nil
    ) -> Bool {
        guard exercise.primaryMuscles.contains(muscle) else { return false }
        guard !excluded.contains(exercise.id) else { return false }
        // Le generateur produit des seances de musculation. Les formats
        // olympiques, strongman, cardio et plyometrie demandent une logique de
        // prescription specifique et ne doivent pas arriver par accident.
        guard exercise.category == "strength" || exercise.category == "powerlifting" else { return false }
        guard exercise.equipment != "foam roll" else { return false }
        guard Self.isEquipmentAllowed(exercise.equipment, for: equipment) else { return false }
        // L'inventaire du lieu RESTREINT, il n'elargit jamais : un materiel
        // present sur place mais exclu par le niveau d'equipement choisi
        // reste exclu.
        if let inventory, !inventory.allows(equipment: exercise.equipment) { return false }
        guard Self.isLevelAllowed(exercise.level, for: experience) else { return false }
        if avoidAreas.contains(where: { Self.exercise(exercise, stresses: $0) }) { return false }
        return true
    }

    static func isLevelAllowed(_ level: String, for experience: Experience) -> Bool {
        switch experience {
        case .beginner:
            return level == "beginner"
        case .intermediate:
            return level == "beginner" || level == "intermediate"
        case .advanced:
            return true
        }
    }

    /// Score stable: mecanisme attendu d'abord, puis niveau le plus proche et id.
    private static func selectionScore(
        _ exercise: CatalogExercise,
        preferredCompound: Bool,
        experience: Experience
    ) -> String {
        let mechanic = preferredCompound ? "compound" : "isolation"
        let mechanicRank = exercise.mechanic == mechanic ? "0" : "1"
        let desiredLevel: String
        switch experience {
        case .beginner: desiredLevel = "beginner"
        case .intermediate: desiredLevel = "intermediate"
        case .advanced: desiredLevel = "expert"
        }
        let levelRank = exercise.level == desiredLevel ? "0" : "1"
        return "\(mechanicRank)-\(levelRank)-\(exercise.id)"
    }

    /// Filtre prudent, non medical. Les zones articulaires ne sont pas des
    /// muscles dans free-exercise-db; on les relie donc a des familles de
    /// mouvements conservatrices plutot que de les ignorer silencieusement.
    static func exercise(_ exercise: CatalogExercise, stresses rawArea: String) -> Bool {
        let area = normalizedText(rawArea)
        let muscles = Set((exercise.primaryMuscles + exercise.secondaryMuscles).map(normalizedText))
        let name = normalizedText("\(exercise.name) \(exercise.nameFr)")

        switch area {
        case "knees", "genoux":
            let lowerBody: Set<String> = ["quadriceps", "hamstrings", "glutes", "calves", "adductors", "abductors"]
            return !muscles.isDisjoint(with: lowerBody)
        case "wrists", "poignets":
            let gripOrPress: Set<String> = ["forearms", "biceps", "triceps", "chest", "shoulders", "lats", "middle back"]
            return !muscles.isDisjoint(with: gripOrPress)
        case "shoulders", "epaules":
            let shoulderChain: Set<String> = ["shoulders", "chest", "triceps"]
            return !muscles.isDisjoint(with: shoulderChain)
        case "lower back", "lombaires":
            let posteriorChain: Set<String> = ["lower back", "hamstrings", "glutes"]
            return !muscles.isDisjoint(with: posteriorChain) || name.contains("deadlift") || name.contains("souleve de terre")
        case "neck", "cou":
            return muscles.contains("neck") || name.contains("neck") || name.contains("cou")
        default:
            return muscles.contains(area)
        }
    }

    static func isEquipmentAllowed(_ equipment: String?, for training: TrainingEquipment) -> Bool {
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

    private func findPullUpExercise(experience: Experience, avoidAreas: [String], excluded: Set<String> = []) -> CatalogExercise? {
        catalog.all
            .filter { exercise in
                exercise.primaryMuscles.contains("lats")
                    && !excluded.contains(exercise.id)
                    && exercise.category == "strength"
                    && exercise.equipment != "foam roll"
                    && Self.isEquipmentAllowed(exercise.equipment, for: .bodyweight)
                    && Self.isLevelAllowed(exercise.level, for: experience)
                    && !avoidAreas.contains(where: { Self.exercise(exercise, stresses: $0) })
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
        let supportsExternalLoad = Self.supportsOneRepMax(exercise)
        let reps = Self.repsRange(for: goal, isCompound: isCompoundMechanic)
        return DraftExercise(
            exerciseId: exercise.id,
            displayName: exercise.nameFr,
            sets: Self.sets(for: goal, experience: experience),
            repsLower: reps.lower,
            repsUpper: reps.upper,
            restSeconds: Self.restSeconds(for: goal),
            percentOneRepMax: Self.percentOneRepMax(
                goal: goal,
                isCompound: isCompoundMechanic,
                supportsExternalLoad: supportsExternalLoad
            )
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

    private static func percentOneRepMax(goal: Goal, isCompound: Bool, supportsExternalLoad: Bool) -> Double? {
        guard goal == .strength, isCompound, supportsExternalLoad else { return nil }
        return 80.0
    }

    private static func supportsOneRepMax(_ exercise: CatalogExercise) -> Bool {
        guard let equipment = exercise.equipment else { return false }
        return ["barbell", "dumbbell", "e-z curl bar", "machine", "cable", "kettlebells"].contains(equipment)
    }

    /// Budget simple mais reel: cinq minutes d'echauffement puis le temps de
    /// travail et de repos de chaque serie classique generee.
    private static func maximumExerciseCount(goal: Goal, experience: Experience, sessionMinutes: Int) -> Int {
        let series = sets(for: goal, experience: experience)
        let secondsPerExercise = series * (45 + restSeconds(for: goal))
        let available = max(1, sessionMinutes * 60 - 5 * 60)
        return max(1, available / max(1, secondsPerExercise))
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
