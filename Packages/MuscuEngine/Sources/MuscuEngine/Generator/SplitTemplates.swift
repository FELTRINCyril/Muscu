import Foundation

/// Un slot d'exercice dans une session type : un groupe musculaire cible,
/// avec l'indication qu'il doit etre travaille en premier par un mouvement polyarticulaire.
public struct MuscleSlot: Sendable {
    public let muscle: String        // cle EN du catalogue ("chest", "lats"...)
    public let compound: Bool        // true = polyarticulaire en premier

    public init(muscle: String, compound: Bool) {
        self.muscle = muscle
        self.compound = compound
    }
}

/// Une session type (nom + slots musculaires a remplir par le generateur).
public struct SessionBlueprint: Sendable {
    public let name: String
    public let slots: [MuscleSlot]

    public init(name: String, slots: [MuscleSlot]) {
        self.name = name
        self.slots = slots
    }
}

public enum SplitTemplates {

    // MARK: - Sessions de base (donnees statiques, cf. tableau de la spec)

    private static let fullBody = SessionBlueprint(name: "Full Body", slots: [
        MuscleSlot(muscle: "quadriceps", compound: true),
        MuscleSlot(muscle: "chest", compound: true),
        MuscleSlot(muscle: "lats", compound: true),
        MuscleSlot(muscle: "shoulders", compound: false),
        MuscleSlot(muscle: "hamstrings", compound: false),
        MuscleSlot(muscle: "biceps", compound: false),
        MuscleSlot(muscle: "triceps", compound: false),
        MuscleSlot(muscle: "abdominals", compound: false),
    ])

    private static let push = SessionBlueprint(name: "Push", slots: [
        MuscleSlot(muscle: "chest", compound: true),
        MuscleSlot(muscle: "chest", compound: true),
        MuscleSlot(muscle: "shoulders", compound: true),
        MuscleSlot(muscle: "triceps", compound: false),
        MuscleSlot(muscle: "triceps", compound: false),
        MuscleSlot(muscle: "chest", compound: false),
    ])

    private static let pull = SessionBlueprint(name: "Pull", slots: [
        MuscleSlot(muscle: "lats", compound: true),
        MuscleSlot(muscle: "lats", compound: true),
        MuscleSlot(muscle: "middle back", compound: false),
        MuscleSlot(muscle: "biceps", compound: false),
        MuscleSlot(muscle: "biceps", compound: false),
        MuscleSlot(muscle: "forearms", compound: false),
    ])

    private static let legs = SessionBlueprint(name: "Legs", slots: [
        MuscleSlot(muscle: "quadriceps", compound: true),
        MuscleSlot(muscle: "quadriceps", compound: true),
        MuscleSlot(muscle: "hamstrings", compound: true),
        MuscleSlot(muscle: "glutes", compound: false),
        MuscleSlot(muscle: "calves", compound: false),
        MuscleSlot(muscle: "abdominals", compound: false),
    ])

    private static let upper = SessionBlueprint(name: "Upper", slots: [
        MuscleSlot(muscle: "chest", compound: true),
        MuscleSlot(muscle: "lats", compound: true),
        MuscleSlot(muscle: "shoulders", compound: false),
        MuscleSlot(muscle: "biceps", compound: false),
        MuscleSlot(muscle: "triceps", compound: false),
    ])

    private static let lower = SessionBlueprint(name: "Lower", slots: [
        MuscleSlot(muscle: "quadriceps", compound: true),
        MuscleSlot(muscle: "hamstrings", compound: true),
        MuscleSlot(muscle: "glutes", compound: false),
        MuscleSlot(muscle: "calves", compound: false),
        MuscleSlot(muscle: "abdominals", compound: false),
    ])

    private static let arnoldChestBack = SessionBlueprint(name: "Chest/Back", slots: [
        MuscleSlot(muscle: "chest", compound: true),
        MuscleSlot(muscle: "lats", compound: true),
        MuscleSlot(muscle: "chest", compound: false),
        MuscleSlot(muscle: "middle back", compound: false),
    ])

    private static let arnoldShouldersArms = SessionBlueprint(name: "Shoulders/Arms", slots: [
        MuscleSlot(muscle: "shoulders", compound: true),
        MuscleSlot(muscle: "biceps", compound: false),
        MuscleSlot(muscle: "triceps", compound: false),
        MuscleSlot(muscle: "forearms", compound: false),
    ])

    private static let arnoldLegs = legs

    // MARK: - Assemblage par nombre de jours (cf. tableau de la spec)

    /// Splits recommandes par nombre de jours (tableau de la spec).
    public static func recommended(daysPerWeek: Int) -> [(preference: SplitPreference, name: String, sessions: [SessionBlueprint])] {
        switch daysPerWeek {
        case 2:
            return [
                (.fullBody, "Full Body x2", [fullBody, fullBody]),
            ]
        case 3:
            return [
                (.fullBody, "Full Body x3", [fullBody, fullBody, fullBody]),
                (.upperLower, "Upper/Lower/Full Body", [upper, lower, fullBody]),
                (.ppl, "Push/Pull/Legs", [push, pull, legs]),
            ]
        case 4:
            return [
                (.upperLower, "Upper/Lower x2", [upper, lower, upper, lower]),
                (.pushPullUpperLower, "Push/Pull/Upper/Lower", [push, pull, upper, lower]),
            ]
        case 5:
            return [
                (.pplul, "Push/Pull/Legs/Upper/Lower", [push, pull, legs, upper, lower]),
                (.ulppl, "Upper/Lower/Push/Pull/Legs", [upper, lower, push, pull, legs]),
                (.arnold, "Arnold + Push/Pull", [arnoldChestBack, arnoldShouldersArms, arnoldLegs, push, pull]),
            ]
        case 6:
            return [
                (.ppl, "Push/Pull/Legs x2", [push, pull, legs, push, pull, legs]),
                (.arnold, "Arnold x2", [arnoldChestBack, arnoldShouldersArms, arnoldLegs, arnoldChestBack, arnoldShouldersArms, arnoldLegs]),
            ]
        default:
            // 7j non recommande : l'UI proposera 6j + repos.
            return []
        }
    }

    /// Blueprint pour une preference et un nombre de jours donnes, si presente dans `recommended`.
    public static func blueprint(for preference: SplitPreference, daysPerWeek: Int) -> [SessionBlueprint]? {
        recommended(daysPerWeek: daysPerWeek).first { $0.preference == preference }?.sessions
    }
}
