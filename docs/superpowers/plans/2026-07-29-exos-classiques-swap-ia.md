# Exos classiques, swap d'alternatives, generation IA - Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Le generateur et les templates choisissent des exercices classiques de salle, chaque exercice peut etre remplace par une alternative en un tap, et la generation IA fonctionne de bout en bout (Claude, ChatGPT, Gemini, endpoint compatible OpenAI).

**Architecture:** Table curee `StapleExercises` dans MuscuEngine (groupes de mouvement + rangs) utilisee par le generateur (selection), par `ExerciseAlternatives` (swap) et par le prompt IA (liste blanche). La logique IA (prompt, parsing, validation, retry) vit dans MuscuEngine avec un client HTTP injectable ; l'app fournit l'implementation `URLSession` et l'UI.

**Tech Stack:** Swift 6 / SwiftUI / SwiftData, package SPM MuscuEngine (tests `swift test`), projet genere par xcodegen.

## Global Constraints

- Code, commentaires, identifiants : ASCII pur, sans accents. Chaines UI affichees : francais AVEC accents.
- Aucune cle API en dur nulle part.
- Les 46 tests unitaires MuscuEngine existants doivent rester verts a chaque commit : `cd Packages/MuscuEngine && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`.
- Build iOS : `xcodegen generate` puis `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Muscu.xcodeproj -scheme Muscu -destination 'platform=iOS Simulator,name=iPhone 17' build`.
- Le test `RuleBasedGeneratorTests.testDeterministicGenerationProducesIdenticalResults` doit rester vert : la generation reste deterministe a input egal.
- Messages de commit : convention du repo (`feat(app):`, `feat(engine):`, `fix:`...), jamais de Co-Authored-By.
- MuscuEngine ne doit pas dependre de l'app ni faire d'appel reseau direct (client HTTP injecte).

---

### Task 1: Table StapleExercises (exercices classiques cures)

**Files:**
- Create: `Packages/MuscuEngine/Sources/MuscuEngine/Generator/StapleExercises.swift`
- Test: `Packages/MuscuEngine/Tests/MuscuEngineTests/StapleExercisesTests.swift`

**Interfaces:**
- Produces: `MovementGroup` (enum String, CaseIterable), `StapleExercise { catalogId: String, group: MovementGroup, rank: Int }`, `StapleExercises.all: [StapleExercise]`, `StapleExercises.staple(for catalogId: String) -> StapleExercise?`, `StapleExercises.members(of group: MovementGroup) -> [StapleExercise]` (tries par rank croissant).

- [ ] **Step 1: Write the failing test**

```swift
// Packages/MuscuEngine/Tests/MuscuEngineTests/StapleExercisesTests.swift
import Testing
@testable import MuscuEngine

struct StapleExercisesTests {
    @Test func allCatalogIdsExistInCatalog() throws {
        let catalog = try ExerciseCatalog.load()
        let knownIds = Set(catalog.all.map(\.id))
        for staple in StapleExercises.all {
            #expect(knownIds.contains(staple.catalogId), "id inconnu du catalogue: \(staple.catalogId)")
        }
    }

    @Test func noDuplicateCatalogIds() {
        let ids = StapleExercises.all.map(\.catalogId)
        #expect(ids.count == Set(ids).count)
    }

    @Test func ranksAreUniqueAndContiguousWithinEachGroup() {
        for group in MovementGroup.allCases {
            let ranks = StapleExercises.members(of: group).map(\.rank)
            #expect(ranks == Array(1...ranks.count), "rangs invalides pour \(group)")
        }
    }

    @Test func lookupByIdWorks() {
        let staple = StapleExercises.staple(for: "Barbell_Bench_Press_-_Medium_Grip")
        #expect(staple?.group == .chestPressHorizontal)
        #expect(staple?.rank == 1)
        #expect(StapleExercises.staple(for: "Alternating_Floor_Press") == nil)
    }

    @Test func membersAreSortedByRank() {
        let members = StapleExercises.members(of: .squat)
        #expect(members.first?.catalogId == "Barbell_Squat")
        #expect(members.map(\.rank) == members.map(\.rank).sorted())
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Packages/MuscuEngine && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter StapleExercisesTests`
Expected: FAIL (compilation : `StapleExercises` introuvable)

- [ ] **Step 3: Write the implementation**

Creer `Packages/MuscuEngine/Sources/MuscuEngine/Generator/StapleExercises.swift`. La table complete (147 entrees, ids verifies contre exercises_fr.json) :

```swift
import Foundation

/// Groupe de mouvement : les exercices d'un meme groupe sont interchangeables
/// (utilise par le generateur pour la selection et par le swap d'alternatives).
public enum MovementGroup: String, CaseIterable, Sendable {
    case chestPressHorizontal, chestPressIncline, chestPressDecline, chestFly, chestDip, pushup
    case verticalPull, horizontalPull, pullover, deadlift, backExtension
    case shoulderPress, lateralRaise, frontRaise, rearDelt, facePull, shrug
    case bicepsCurl, hammerCurl, preacherCurl, tricepsExtension, tricepsDip, skullcrusher, kickback
    case squat, legPress, lunge, hipHinge, hipThrust, legExtension, legCurl
    case calfStanding, calfSeated, calfPress
    case crunch, legRaise, plank, rotation
}

/// Un exercice "classique de salle" : reference vers le catalogue + groupe + rang
/// de preference dans le groupe (1 = le plus classique).
public struct StapleExercise: Sendable {
    public let catalogId: String
    public let group: MovementGroup
    public let rank: Int
}

/// Liste blanche curee des exercices classiques. Le generateur et les templates
/// ne piochent QUE dans cette liste (repli catalogue complet si aucun candidat).
/// Chaque id est verifie par StapleExercisesTests contre exercises_fr.json.
public enum StapleExercises {
    public static let all: [StapleExercise] = [
        // Pecs - presses horizontales
        .init(catalogId: "Barbell_Bench_Press_-_Medium_Grip", group: .chestPressHorizontal, rank: 1),
        .init(catalogId: "Dumbbell_Bench_Press", group: .chestPressHorizontal, rank: 2),
        .init(catalogId: "Machine_Bench_Press", group: .chestPressHorizontal, rank: 3),
        .init(catalogId: "Smith_Machine_Bench_Press", group: .chestPressHorizontal, rank: 4),
        .init(catalogId: "Leverage_Chest_Press", group: .chestPressHorizontal, rank: 5),
        .init(catalogId: "Cable_Chest_Press", group: .chestPressHorizontal, rank: 6),
        // Pecs - presses inclinees
        .init(catalogId: "Barbell_Incline_Bench_Press_-_Medium_Grip", group: .chestPressIncline, rank: 1),
        .init(catalogId: "Incline_Dumbbell_Press", group: .chestPressIncline, rank: 2),
        .init(catalogId: "Smith_Machine_Incline_Bench_Press", group: .chestPressIncline, rank: 3),
        .init(catalogId: "Leverage_Incline_Chest_Press", group: .chestPressIncline, rank: 4),
        // Pecs - presses declinees
        .init(catalogId: "Decline_Barbell_Bench_Press", group: .chestPressDecline, rank: 1),
        .init(catalogId: "Decline_Dumbbell_Bench_Press", group: .chestPressDecline, rank: 2),
        .init(catalogId: "Smith_Machine_Decline_Press", group: .chestPressDecline, rank: 3),
        .init(catalogId: "Leverage_Decline_Chest_Press", group: .chestPressDecline, rank: 4),
        // Pecs - ecartes
        .init(catalogId: "Dumbbell_Flyes", group: .chestFly, rank: 1),
        .init(catalogId: "Butterfly", group: .chestFly, rank: 2),
        .init(catalogId: "Cable_Crossover", group: .chestFly, rank: 3),
        .init(catalogId: "Low_Cable_Crossover", group: .chestFly, rank: 4),
        .init(catalogId: "Incline_Dumbbell_Flyes", group: .chestFly, rank: 5),
        .init(catalogId: "Flat_Bench_Cable_Flyes", group: .chestFly, rank: 6),
        // Pecs - dips et pompes
        .init(catalogId: "Dips_-_Chest_Version", group: .chestDip, rank: 1),
        .init(catalogId: "Pushups", group: .pushup, rank: 1),
        .init(catalogId: "Push-Up_Wide", group: .pushup, rank: 2),
        .init(catalogId: "Incline_Push-Up", group: .pushup, rank: 3),
        .init(catalogId: "Decline_Push-Up", group: .pushup, rank: 4),
        // Dos - tirages verticaux
        .init(catalogId: "Pullups", group: .verticalPull, rank: 1),
        .init(catalogId: "Wide-Grip_Lat_Pulldown", group: .verticalPull, rank: 2),
        .init(catalogId: "Chin-Up", group: .verticalPull, rank: 3),
        .init(catalogId: "One_Arm_Lat_Pulldown", group: .verticalPull, rank: 4),
        .init(catalogId: "Close-Grip_Front_Lat_Pulldown", group: .verticalPull, rank: 5),
        .init(catalogId: "V-Bar_Pulldown", group: .verticalPull, rank: 6),
        .init(catalogId: "Underhand_Cable_Pulldowns", group: .verticalPull, rank: 7),
        // Dos - tirages horizontaux
        .init(catalogId: "Bent_Over_Barbell_Row", group: .horizontalPull, rank: 1),
        .init(catalogId: "One-Arm_Dumbbell_Row", group: .horizontalPull, rank: 2),
        .init(catalogId: "Seated_Cable_Rows", group: .horizontalPull, rank: 3),
        .init(catalogId: "T-Bar_Row_with_Handle", group: .horizontalPull, rank: 4),
        .init(catalogId: "Lying_T-Bar_Row", group: .horizontalPull, rank: 5),
        .init(catalogId: "Leverage_Iso_Row", group: .horizontalPull, rank: 6),
        .init(catalogId: "Smith_Machine_Bent_Over_Row", group: .horizontalPull, rank: 7),
        .init(catalogId: "Inverted_Row", group: .horizontalPull, rank: 8),
        // Dos - pullovers
        .init(catalogId: "Straight-Arm_Dumbbell_Pullover", group: .pullover, rank: 1),
        .init(catalogId: "Bent-Arm_Dumbbell_Pullover", group: .pullover, rank: 2),
        .init(catalogId: "Bent-Arm_Barbell_Pullover", group: .pullover, rank: 3),
        .init(catalogId: "Straight-Arm_Pulldown", group: .pullover, rank: 4),
        // Dos - souleve de terre et lombaires
        .init(catalogId: "Barbell_Deadlift", group: .deadlift, rank: 1),
        .init(catalogId: "Sumo_Deadlift", group: .deadlift, rank: 2),
        .init(catalogId: "Trap_Bar_Deadlift", group: .deadlift, rank: 3),
        .init(catalogId: "Hyperextensions_Back_Extensions", group: .backExtension, rank: 1),
        .init(catalogId: "Hyperextensions_With_No_Hyperextension_Bench", group: .backExtension, rank: 2),
        // Epaules - developpes
        .init(catalogId: "Standing_Military_Press", group: .shoulderPress, rank: 1),
        .init(catalogId: "Dumbbell_Shoulder_Press", group: .shoulderPress, rank: 2),
        .init(catalogId: "Seated_Barbell_Military_Press", group: .shoulderPress, rank: 3),
        .init(catalogId: "Arnold_Dumbbell_Press", group: .shoulderPress, rank: 4),
        .init(catalogId: "Machine_Shoulder_Military_Press", group: .shoulderPress, rank: 5),
        .init(catalogId: "Smith_Machine_Overhead_Shoulder_Press", group: .shoulderPress, rank: 6),
        .init(catalogId: "Leverage_Shoulder_Press", group: .shoulderPress, rank: 7),
        // Epaules - elevations et arriere
        .init(catalogId: "Side_Lateral_Raise", group: .lateralRaise, rank: 1),
        .init(catalogId: "Seated_Side_Lateral_Raise", group: .lateralRaise, rank: 2),
        .init(catalogId: "Cable_Seated_Lateral_Raise", group: .lateralRaise, rank: 3),
        .init(catalogId: "Front_Dumbbell_Raise", group: .frontRaise, rank: 1),
        .init(catalogId: "Front_Two-Dumbbell_Raise", group: .frontRaise, rank: 2),
        .init(catalogId: "Front_Cable_Raise", group: .frontRaise, rank: 3),
        .init(catalogId: "Front_Plate_Raise", group: .frontRaise, rank: 4),
        .init(catalogId: "Reverse_Flyes", group: .rearDelt, rank: 1),
        .init(catalogId: "Reverse_Machine_Flyes", group: .rearDelt, rank: 2),
        .init(catalogId: "Cable_Rear_Delt_Fly", group: .rearDelt, rank: 3),
        .init(catalogId: "Seated_Bent-Over_Rear_Delt_Raise", group: .rearDelt, rank: 4),
        .init(catalogId: "Face_Pull", group: .facePull, rank: 1),
        // Epaules - shrugs
        .init(catalogId: "Barbell_Shrug", group: .shrug, rank: 1),
        .init(catalogId: "Dumbbell_Shrug", group: .shrug, rank: 2),
        .init(catalogId: "Cable_Shrugs", group: .shrug, rank: 3),
        .init(catalogId: "Leverage_Shrug", group: .shrug, rank: 4),
        // Biceps
        .init(catalogId: "Barbell_Curl", group: .bicepsCurl, rank: 1),
        .init(catalogId: "EZ-Bar_Curl", group: .bicepsCurl, rank: 2),
        .init(catalogId: "Dumbbell_Alternate_Bicep_Curl", group: .bicepsCurl, rank: 3),
        .init(catalogId: "Dumbbell_Bicep_Curl", group: .bicepsCurl, rank: 4),
        .init(catalogId: "Standing_Biceps_Cable_Curl", group: .bicepsCurl, rank: 5),
        .init(catalogId: "Machine_Bicep_Curl", group: .bicepsCurl, rank: 6),
        .init(catalogId: "Concentration_Curls", group: .bicepsCurl, rank: 7),
        .init(catalogId: "Incline_Dumbbell_Curl", group: .bicepsCurl, rank: 8),
        .init(catalogId: "Hammer_Curls", group: .hammerCurl, rank: 1),
        .init(catalogId: "Cable_Hammer_Curls_-_Rope_Attachment", group: .hammerCurl, rank: 2),
        .init(catalogId: "Alternate_Hammer_Curl", group: .hammerCurl, rank: 3),
        .init(catalogId: "Preacher_Curl", group: .preacherCurl, rank: 1),
        .init(catalogId: "Machine_Preacher_Curls", group: .preacherCurl, rank: 2),
        .init(catalogId: "Two-Arm_Dumbbell_Preacher_Curl", group: .preacherCurl, rank: 3),
        .init(catalogId: "Cable_Preacher_Curl", group: .preacherCurl, rank: 4),
        // Triceps
        .init(catalogId: "Triceps_Pushdown", group: .tricepsExtension, rank: 1),
        .init(catalogId: "Triceps_Pushdown_-_Rope_Attachment", group: .tricepsExtension, rank: 2),
        .init(catalogId: "Triceps_Pushdown_-_V-Bar_Attachment", group: .tricepsExtension, rank: 3),
        .init(catalogId: "Cable_Rope_Overhead_Triceps_Extension", group: .tricepsExtension, rank: 4),
        .init(catalogId: "Standing_Dumbbell_Triceps_Extension", group: .tricepsExtension, rank: 5),
        .init(catalogId: "Machine_Triceps_Extension", group: .tricepsExtension, rank: 6),
        .init(catalogId: "Dips_-_Triceps_Version", group: .tricepsDip, rank: 1),
        .init(catalogId: "Bench_Dips", group: .tricepsDip, rank: 2),
        .init(catalogId: "Dip_Machine", group: .tricepsDip, rank: 3),
        .init(catalogId: "Parallel_Bar_Dip", group: .tricepsDip, rank: 4),
        .init(catalogId: "Lying_Triceps_Press", group: .skullcrusher, rank: 1),
        .init(catalogId: "EZ-Bar_Skullcrusher", group: .skullcrusher, rank: 2),
        .init(catalogId: "Tricep_Dumbbell_Kickback", group: .kickback, rank: 1),
        // Jambes - squats et presses
        .init(catalogId: "Barbell_Squat", group: .squat, rank: 1),
        .init(catalogId: "Barbell_Full_Squat", group: .squat, rank: 2),
        .init(catalogId: "Smith_Machine_Squat", group: .squat, rank: 3),
        .init(catalogId: "Front_Barbell_Squat", group: .squat, rank: 4),
        .init(catalogId: "Goblet_Squat", group: .squat, rank: 5),
        .init(catalogId: "Dumbbell_Squat", group: .squat, rank: 6),
        .init(catalogId: "Bodyweight_Squat", group: .squat, rank: 7),
        .init(catalogId: "Leg_Press", group: .legPress, rank: 1),
        .init(catalogId: "Hack_Squat", group: .legPress, rank: 2),
        // Jambes - fentes
        .init(catalogId: "Dumbbell_Lunges", group: .lunge, rank: 1),
        .init(catalogId: "Barbell_Lunge", group: .lunge, rank: 2),
        .init(catalogId: "Barbell_Walking_Lunge", group: .lunge, rank: 3),
        .init(catalogId: "Bodyweight_Walking_Lunge", group: .lunge, rank: 4),
        .init(catalogId: "Split_Squat_with_Dumbbells", group: .lunge, rank: 5),
        .init(catalogId: "Dumbbell_Rear_Lunge", group: .lunge, rank: 6),
        // Jambes - hinge et ischio
        .init(catalogId: "Romanian_Deadlift", group: .hipHinge, rank: 1),
        .init(catalogId: "Stiff-Legged_Barbell_Deadlift", group: .hipHinge, rank: 2),
        .init(catalogId: "Stiff-Legged_Dumbbell_Deadlift", group: .hipHinge, rank: 3),
        .init(catalogId: "Good_Morning", group: .hipHinge, rank: 4),
        .init(catalogId: "Barbell_Hip_Thrust", group: .hipThrust, rank: 1),
        .init(catalogId: "Barbell_Glute_Bridge", group: .hipThrust, rank: 2),
        .init(catalogId: "Leg_Extensions", group: .legExtension, rank: 1),
        .init(catalogId: "Lying_Leg_Curls", group: .legCurl, rank: 1),
        .init(catalogId: "Seated_Leg_Curl", group: .legCurl, rank: 2),
        .init(catalogId: "Standing_Leg_Curl", group: .legCurl, rank: 3),
        // Mollets
        .init(catalogId: "Standing_Calf_Raises", group: .calfStanding, rank: 1),
        .init(catalogId: "Standing_Barbell_Calf_Raise", group: .calfStanding, rank: 2),
        .init(catalogId: "Standing_Dumbbell_Calf_Raise", group: .calfStanding, rank: 3),
        .init(catalogId: "Smith_Machine_Calf_Raise", group: .calfStanding, rank: 4),
        .init(catalogId: "Seated_Calf_Raise", group: .calfSeated, rank: 1),
        .init(catalogId: "Barbell_Seated_Calf_Raise", group: .calfSeated, rank: 2),
        .init(catalogId: "Calf_Press_On_The_Leg_Press_Machine", group: .calfPress, rank: 1),
        .init(catalogId: "Calf_Press", group: .calfPress, rank: 2),
        // Abdos
        .init(catalogId: "Crunches", group: .crunch, rank: 1),
        .init(catalogId: "Cable_Crunch", group: .crunch, rank: 2),
        .init(catalogId: "Ab_Crunch_Machine", group: .crunch, rank: 3),
        .init(catalogId: "Decline_Crunch", group: .crunch, rank: 4),
        .init(catalogId: "Exercise_Ball_Crunch", group: .crunch, rank: 5),
        .init(catalogId: "Oblique_Crunches", group: .crunch, rank: 6),
        .init(catalogId: "Hanging_Leg_Raise", group: .legRaise, rank: 1),
        .init(catalogId: "Flat_Bench_Lying_Leg_Raise", group: .legRaise, rank: 2),
        .init(catalogId: "Leg_Pull-In", group: .legRaise, rank: 3),
        .init(catalogId: "Plank", group: .plank, rank: 1),
        .init(catalogId: "Side_Bridge", group: .plank, rank: 2),
        .init(catalogId: "Ab_Roller", group: .plank, rank: 3),
        .init(catalogId: "Russian_Twist", group: .rotation, rank: 1),
        .init(catalogId: "Cable_Russian_Twists", group: .rotation, rank: 2),
    ]

    private static let byId: [String: StapleExercise] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.catalogId, $0) }
    )

    public static func staple(for catalogId: String) -> StapleExercise? {
        byId[catalogId]
    }

    public static func members(of group: MovementGroup) -> [StapleExercise] {
        all.filter { $0.group == group }.sorted { $0.rank < $1.rank }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd Packages/MuscuEngine && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter StapleExercisesTests`
Expected: PASS (5 tests). Si `allCatalogIdsExistInCatalog` echoue, corriger l'id fautif en cherchant dans le JSON (`jq -r '.[].id' .../exercises_fr.json | grep -i <mot>`), ne jamais supprimer le test.

- [ ] **Step 5: Run the full engine suite and commit**

Run: `cd Packages/MuscuEngine && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
Expected: 51 tests PASS (46 existants + 5 nouveaux)

```bash
git add Packages/MuscuEngine
git commit -m "feat(engine): table StapleExercises des exercices classiques avec groupes de mouvement"
```

---

### Task 2: Le generateur pioche dans la liste blanche

**Files:**
- Modify: `Packages/MuscuEngine/Sources/MuscuEngine/Generator/RuleBasedGenerator.swift` (fonction `pickExercise`, lignes ~147-163)
- Test: `Packages/MuscuEngine/Tests/MuscuEngineTests/RuleBasedGeneratorTests.swift` (ajout de tests)

**Interfaces:**
- Consumes: `StapleExercises.staple(for:)` (Task 1).
- Produces: comportement `pickExercise` : candidats staples d'abord (tri par `(rank, id)`), repli catalogue complet (tri par id, comportement historique) si aucun staple ne matche.

- [ ] **Step 1: Write the failing tests**

Ajouter dans `RuleBasedGeneratorTests.swift` (respecter le style des tests existants du fichier - lire le fichier avant, il utilise `import Testing` et un catalogue charge via `ExerciseCatalog.load()`) :

```swift
@Test func generatorPicksOnlyStapleExercisesInFullGym() throws {
    let catalog = try ExerciseCatalog.load()
    let input = GeneratorInput(
        goal: .hypertrophy, experience: .intermediate, daysPerWeek: 3,
        sessionMinutes: 60, equipment: .fullGym, splitPreference: .ppl,
        priorityMuscles: [], avoidAreas: []
    )
    let draft = try RuleBasedGenerator(catalog: catalog).generate(input)
    for session in draft.sessions {
        for exercise in session.exercises {
            #expect(
                StapleExercises.staple(for: exercise.exerciseId) != nil,
                "exercice hors liste blanche: \(exercise.exerciseId)"
            )
        }
    }
}

@Test func generatorPrefersRankOneCompoundForChest() throws {
    let catalog = try ExerciseCatalog.load()
    let input = GeneratorInput(
        goal: .hypertrophy, experience: .intermediate, daysPerWeek: 3,
        sessionMinutes: 60, equipment: .fullGym, splitPreference: .ppl,
        priorityMuscles: [], avoidAreas: []
    )
    let draft = try RuleBasedGenerator(catalog: catalog).generate(input)
    let allIds = draft.sessions.flatMap { $0.exercises.map(\.exerciseId) }
    #expect(allIds.contains("Barbell_Bench_Press_-_Medium_Grip"),
            "le DC barre (rang 1) devrait etre choisi pour le slot pecs compound")
    #expect(!allIds.contains("Alternating_Floor_Press"))
}

@Test func generatorFallsBackToCatalogWhenNoStapleMatches() throws {
    // Muscle "neck" : aucun staple ne le cible -> le repli catalogue doit fournir un exercice.
    let catalog = try ExerciseCatalog.load()
    let generator = RuleBasedGenerator(catalog: catalog)
    let pick = generator.pickExerciseForTesting(
        muscle: "neck", preferCompound: false, equipment: .fullGym, avoidAreas: [], used: []
    )
    #expect(pick != nil)
    #expect(StapleExercises.staple(for: pick!.id) == nil)
}
```

Note : le 3e test necessite d'exposer la selection. Ajouter dans `RuleBasedGenerator` une facade de test :

```swift
// Visible pour les tests uniquement (le package est importe @testable).
func pickExerciseForTesting(
    muscle: String, preferCompound: Bool, equipment: TrainingEquipment,
    avoidAreas: [String], used: Set<String>
) -> CatalogExercise? {
    pickExercise(muscle: muscle, preferCompound: preferCompound,
                 equipment: equipment, avoidAreas: avoidAreas, used: used)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd Packages/MuscuEngine && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter RuleBasedGeneratorTests`
Expected: FAIL (`generatorPicksOnlyStapleExercisesInFullGym` et `generatorPrefersRankOneCompoundForChest` echouent : le tri alphabetique choisit des ids hors liste ; `generatorFallsBackToCatalogWhenNoStapleMatches` echoue en compilation tant que la facade n'existe pas)

- [ ] **Step 3: Modify pickExercise**

Remplacer le corps de `pickExercise` dans `RuleBasedGenerator.swift` :

```swift
private func pickExercise(
    muscle: String,
    preferCompound: Bool,
    equipment: TrainingEquipment,
    avoidAreas: [String],
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
    if let match = staples.first(where: { $0.mechanic == preferredMechanic && !used.contains($0.id) }) {
        return match
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
```

Ajouter aussi la facade `pickExerciseForTesting` (code du Step 1). Mettre a jour le commentaire de doc de l'algorithme en tete de fichier (etape 4 : "Selection dans la liste blanche StapleExercises, repli catalogue").

- [ ] **Step 4: Run the full engine suite**

Run: `cd Packages/MuscuEngine && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
Expected: PASS. Attention : des tests existants peuvent asserter sur des ids precis choisis par l'ancien tri (ex : bodyweight, avoidAreas, pullUpProgress). S'ils echouent, verifier que le nouveau choix est un classique coherent et adapter l'assertion du test A CE NOUVEAU choix (jamais affaiblir le test en supprimant l'assertion). `testDeterministicGenerationProducesIdenticalResults` doit passer sans modification.

- [ ] **Step 5: Commit**

```bash
git add Packages/MuscuEngine
git commit -m "feat(engine): le generateur pioche dans la liste blanche des classiques"
```

---

### Task 3: Regenerer fait tourner les alternatives (variation)

**Files:**
- Modify: `Packages/MuscuEngine/Sources/MuscuEngine/Generator/GeneratorInput.swift`
- Modify: `Packages/MuscuEngine/Sources/MuscuEngine/Generator/RuleBasedGenerator.swift`
- Modify: `App/Sources/Features/Programs/GeneratorWizardView.swift` (fonction `regenerate`, lignes ~283-286)
- Modify: `App/Sources/Features/Programs/TemplatePickerView.swift` (fonction `regenerate`, lignes ~82-85)
- Test: `Packages/MuscuEngine/Tests/MuscuEngineTests/RuleBasedGeneratorTests.swift`

**Interfaces:**
- Produces: `GeneratorInput.variation: Int` (defaut 0, Codable avec decodage retro-compatible), selection decalee de `variation` positions parmi les staples du mechanic prefere.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func variationRotatesExerciseChoices() throws {
    let catalog = try ExerciseCatalog.load()
    var input = GeneratorInput(
        goal: .hypertrophy, experience: .intermediate, daysPerWeek: 3,
        sessionMinutes: 60, equipment: .fullGym, splitPreference: .ppl,
        priorityMuscles: [], avoidAreas: []
    )
    let draft0 = try RuleBasedGenerator(catalog: catalog).generate(input)
    input.variation = 1
    let draft1 = try RuleBasedGenerator(catalog: catalog).generate(input)
    #expect(draft0 != draft1, "variation differente -> choix differents")

    let draft1bis = try RuleBasedGenerator(catalog: catalog).generate(input)
    #expect(draft1 == draft1bis, "meme variation -> resultat identique (determinisme)")
}

@Test func generatorInputDecodesWithoutVariationField() throws {
    // Retro-compatibilite : un JSON encode avant l'ajout du champ doit decoder (variation = 0).
    let json = """
    {"goal":"hypertrophy","experience":"intermediate","daysPerWeek":3,
     "sessionMinutes":60,"equipment":"fullGym","splitPreference":"auto",
     "priorityMuscles":[],"avoidAreas":[]}
    """.data(using: .utf8)!
    let input = try JSONDecoder().decode(GeneratorInput.self, from: json)
    #expect(input.variation == 0)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd Packages/MuscuEngine && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter RuleBasedGeneratorTests`
Expected: FAIL en compilation (`variation` n'existe pas)

- [ ] **Step 3: Implement**

Dans `GeneratorInput.swift`, ajouter la propriete avec decodage tolerant :

```swift
public var variation: Int  // increment a chaque "Regenerer" pour faire tourner les choix

// Dans init(...), ajouter le parametre avec defaut :
//   variation: Int = 0
// et l'affectation self.variation = variation.

// Decodage retro-compatible (les autres champs restent synthetises) :
public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    goal = try container.decode(Goal.self, forKey: .goal)
    experience = try container.decode(Experience.self, forKey: .experience)
    daysPerWeek = try container.decode(Int.self, forKey: .daysPerWeek)
    sessionMinutes = try container.decode(Int.self, forKey: .sessionMinutes)
    equipment = try container.decode(TrainingEquipment.self, forKey: .equipment)
    splitPreference = try container.decode(SplitPreference.self, forKey: .splitPreference)
    priorityMuscles = try container.decode([String].self, forKey: .priorityMuscles)
    avoidAreas = try container.decode([String].self, forKey: .avoidAreas)
    variation = try container.decodeIfPresent(Int.self, forKey: .variation) ?? 0
}
```

Dans `RuleBasedGenerator.swift` : `buildSession` passe `input.variation` a `pickExercise` (nouveau parametre `variation: Int`). Dans `pickExercise`, appliquer le decalage sur la liste des staples du mechanic prefere :

```swift
let preferred = staples.filter { $0.mechanic == preferredMechanic && !used.contains($0.id) }
if !preferred.isEmpty {
    return preferred[variation % preferred.count]
}
```

(le reste de la cascade - staples tous mechanics, repli catalogue - garde `first`, la variation ne s'applique qu'au choix principal). Mettre a jour `pickExerciseForTesting` avec le parametre `variation: Int = 0`.

Dans `GeneratorWizardView.swift` et `TemplatePickerView.swift`, `regenerate()` incremente la variation :

```swift
private func regenerate() -> DraftProgram? {
    guard var input = draftInput else { return nil }
    input.variation += 1
    draftInput = input
    return try? RuleBasedGenerator(catalog: catalogStore.catalog).generate(input)
}
```

- [ ] **Step 4: Run tests and build the app**

Run: `cd Packages/MuscuEngine && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
Expected: PASS
Run: `xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Muscu.xcodeproj -scheme Muscu -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -3`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add Packages/MuscuEngine App/Sources
git commit -m "feat(app): Regenerer fait tourner les alternatives (variation deterministe)"
```

---

### Task 4: ExerciseAlternatives (moteur du swap)

**Files:**
- Create: `Packages/MuscuEngine/Sources/MuscuEngine/Generator/ExerciseAlternatives.swift`
- Test: `Packages/MuscuEngine/Tests/MuscuEngineTests/ExerciseAlternativesTests.swift`

**Interfaces:**
- Consumes: `StapleExercises` (Task 1), `ExerciseCatalog`.
- Produces: `ExerciseAlternatives.alternatives(for exerciseId: String, in catalog: ExerciseCatalog) -> [CatalogExercise]`.

- [ ] **Step 1: Write the failing tests**

```swift
// Packages/MuscuEngine/Tests/MuscuEngineTests/ExerciseAlternativesTests.swift
import Testing
@testable import MuscuEngine

struct ExerciseAlternativesTests {
    @Test func stapleExerciseGetsItsMovementGroupSortedByRank() throws {
        let catalog = try ExerciseCatalog.load()
        let alternatives = ExerciseAlternatives.alternatives(for: "Barbell_Squat", in: catalog)
        let ids = alternatives.map(\.id)
        #expect(!ids.contains("Barbell_Squat"), "l'exercice courant est exclu")
        #expect(ids.first == "Barbell_Full_Squat", "rang 2 du groupe squat en premier")
        #expect(ids.contains("Smith_Machine_Squat"))
        #expect(ids.contains("Goblet_Squat"))
    }

    @Test func nonStapleExerciseFallsBackToSameMuscleAndMechanic() throws {
        let catalog = try ExerciseCatalog.load()
        // Alternating_Floor_Press : chest / compound, hors liste blanche.
        let alternatives = ExerciseAlternatives.alternatives(for: "Alternating_Floor_Press", in: catalog)
        #expect(!alternatives.isEmpty)
        for exercise in alternatives {
            #expect(exercise.primaryMuscles.contains("chest"))
            #expect(exercise.mechanic == "compound")
        }
        // Les staples du meme muscle arrivent en premier dans le repli.
        #expect(StapleExercises.staple(for: alternatives[0].id) != nil)
    }

    @Test func unknownExerciseIdReturnsEmpty() throws {
        let catalog = try ExerciseCatalog.load()
        #expect(ExerciseAlternatives.alternatives(for: "Id_Bidon_Inexistant", in: catalog).isEmpty)
    }

    @Test func resultIsCappedAtTwelve() throws {
        let catalog = try ExerciseCatalog.load()
        // Squat : gros groupe + gros repli potentiel -> verifie le plafond.
        let alternatives = ExerciseAlternatives.alternatives(for: "Crunches", in: catalog)
        #expect(alternatives.count <= 12)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd Packages/MuscuEngine && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ExerciseAlternativesTests`
Expected: FAIL (compilation)

- [ ] **Step 3: Implement**

```swift
// Packages/MuscuEngine/Sources/MuscuEngine/Generator/ExerciseAlternatives.swift
import Foundation

/// Alternatives pertinentes pour remplacer un exercice :
/// 1. Exercice de la liste blanche -> les autres membres de son groupe de
///    mouvement, tries par rang (squat barre -> presse, smith, front...).
/// 2. Sinon (exo perso, hors liste) -> repli catalogue : meme muscle principal
///    et meme mechanic, staples en tete puis tri alphabetique, plafonne a 12.
public enum ExerciseAlternatives {
    public static func alternatives(for exerciseId: String, in catalog: ExerciseCatalog) -> [CatalogExercise] {
        let byId = Dictionary(uniqueKeysWithValues: catalog.all.map { ($0.id, $0) })

        if let staple = StapleExercises.staple(for: exerciseId) {
            return StapleExercises.members(of: staple.group)
                .filter { $0.catalogId != exerciseId }
                .compactMap { byId[$0.catalogId] }
        }

        guard let current = byId[exerciseId],
              let muscle = current.primaryMuscles.first else {
            return []
        }

        let candidates = catalog.all.filter { exercise in
            exercise.id != exerciseId
                && exercise.primaryMuscles.contains(muscle)
                && exercise.mechanic == current.mechanic
                && exercise.category != "stretching"
        }
        let sorted = candidates.sorted { lhs, rhs in
            let lhsIsStaple = StapleExercises.staple(for: lhs.id) != nil
            let rhsIsStaple = StapleExercises.staple(for: rhs.id) != nil
            if lhsIsStaple != rhsIsStaple { return lhsIsStaple }
            return lhs.id < rhs.id
        }
        return Array(sorted.prefix(12))
    }
}
```

Note : les exercices perso (`CustomExercise`, id UUID) ne sont pas dans le catalogue -> le guard retourne `[]` et l'UI (Task 5) proposera directement le picker complet.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd Packages/MuscuEngine && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
Expected: PASS (toute la suite)

- [ ] **Step 5: Commit**

```bash
git add Packages/MuscuEngine
git commit -m "feat(engine): alternatives d'exercice par groupe de mouvement avec repli muscle"
```

---

### Task 5: Sheet de swap + swap dans l'apercu de generation

**Files:**
- Create: `App/Sources/Features/Programs/ExerciseSwapSheet.swift`
- Modify: `App/Sources/Features/Programs/DraftPreviewView.swift`

**Interfaces:**
- Consumes: `ExerciseAlternatives.alternatives(for:in:)` (Task 4), `ExercisePickerView(initialMuscleFilter:onPick:)` (existant), `CatalogStore` (`@Environment`, propriete `catalog`, methode `exercise(id:)`).
- Produces: `ExerciseSwapSheet(currentExerciseId: String, onSwap: @escaping (_ id: String, _ displayName: String) -> Void)` reutilisee en Task 6.

- [ ] **Step 1: Create ExerciseSwapSheet**

```swift
// App/Sources/Features/Programs/ExerciseSwapSheet.swift
import SwiftUI
import MuscuEngine

// Sheet compacte de remplacement d'un exercice par une alternative du meme
// groupe de mouvement (ou repli meme muscle), avec acces au picker complet.
// Utilisee par DraftPreviewView (brouillons) et SessionEditorView (programmes).
struct ExerciseSwapSheet: View {
    let currentExerciseId: String
    let onSwap: (_ id: String, _ displayName: String) -> Void

    @Environment(CatalogStore.self) private var catalogStore
    @Environment(\.dismiss) private var dismiss

    @State private var showingFullPicker = false

    private var alternatives: [CatalogExercise] {
        ExerciseAlternatives.alternatives(for: currentExerciseId, in: catalogStore.catalog)
    }

    private var currentPrimaryMuscle: String? {
        catalogStore.exercise(id: currentExerciseId)?.primaryMuscles.first
    }

    var body: some View {
        NavigationStack {
            List {
                if alternatives.isEmpty {
                    Text("Aucune alternative directe pour cet exercice.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Section("Alternatives") {
                        ForEach(alternatives, id: \.id) { exercise in
                            Button {
                                onSwap(exercise.id, exercise.nameFr)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(exercise.nameFr)
                                        .foregroundStyle(.primary)
                                    if let equipment = exercise.equipment {
                                        Text(FrenchLabels.equipment(equipment))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }

                Section {
                    Button {
                        showingFullPicker = true
                    } label: {
                        Label("Autre exercice...", systemImage: "magnifyingglass")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Remplacer par")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
            .sheet(isPresented: $showingFullPicker) {
                ExercisePickerView(initialMuscleFilter: currentPrimaryMuscle) { id, displayName in
                    onSwap(id, displayName)
                    dismiss()
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
```

Verifier avant d'ecrire : l'existence et la signature exacte de `FrenchLabels.equipment(_:)` (`grep -n "func equipment" Packages/MuscuEngine/Sources/MuscuEngine/Catalog/FrenchLabels.swift`). Si le label n'existe pas sous ce nom, utiliser la fonction equivalente du fichier ou afficher `exercise.equipment` brut.

- [ ] **Step 2: Wire the swap into DraftPreviewView**

Dans `DraftPreviewView.swift` :

1. Ajouter l'etat : `@State private var swapTarget: (session: Int, exercise: Int)?` - remplace par un type `Identifiable` pour `sheet(item:)` :

```swift
private struct SwapTarget: Identifiable {
    let sessionIndex: Int
    let exerciseIndex: Int
    let exerciseId: String
    var id: String { "\(sessionIndex)-\(exerciseIndex)" }
}
@State private var swapTarget: SwapTarget?
```

2. Dans le `ForEach` des exercices (ligne ~62), remplacer la row par une HStack avec bouton de swap :

```swift
ForEach(Array(session.exercises.enumerated()), id: \.offset) { exerciseIndex, exercise in
    HStack {
        DraftExerciseRow(exercise: exercise)
        Spacer()
        Button {
            swapTarget = SwapTarget(
                sessionIndex: index,
                exerciseIndex: exerciseIndex,
                exerciseId: exercise.exerciseId
            )
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(Theme.accent)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Remplacer \(exercise.displayName)")
    }
}
```

3. Ajouter la sheet apres `.safeAreaInset` :

```swift
.sheet(item: $swapTarget) { target in
    ExerciseSwapSheet(currentExerciseId: target.exerciseId) { newId, newName in
        currentDraft.sessions[target.sessionIndex].exercises[target.exerciseIndex].exerciseId = newId
        currentDraft.sessions[target.sessionIndex].exercises[target.exerciseIndex].displayName = newName
    }
}
```

(`currentDraft` est deja un `@State var DraftProgram`, struct mutable : l'UI se met a jour.)

- [ ] **Step 3: Build and verify manually in the simulator**

Run: `xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Muscu.xcodeproj -scheme Muscu -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -3`
Expected: BUILD SUCCEEDED
Verification manuelle (ou via harnais de screenshot temporaire, convention du repo) : Programmes -> + -> Depuis un modele -> choisir un split -> l'apercu montre l'icone de swap ; taper dessus ouvre la sheet avec les alternatives du groupe ; choisir une alternative remplace l'exercice dans l'apercu en conservant series/reps/repos.

- [ ] **Step 4: Commit**

```bash
git add App/Sources
git commit -m "feat(app): swap d'exercice par alternatives dans l'apercu de generation"
```

---

### Task 6: Swap dans l'editeur de seance + bouton Modifier sur l'apercu

**Files:**
- Modify: `App/Sources/Features/Programs/SessionEditorView.swift`
- Modify: `App/Sources/Features/Programs/DraftPreviewView.swift`
- Modify: `App/Sources/Features/Programs/ProgramsView.swift`
- Modify: `App/Sources/Features/Programs/TemplatePickerView.swift`
- Modify: `App/Sources/Features/Programs/GeneratorWizardView.swift`

**Interfaces:**
- Consumes: `ExerciseSwapSheet` (Task 5), `DraftProgram.toModel()` (existant, `App/Sources/Models/ActiveWorkout.swift:56`), `ProgramEditorView(program:)` (existant).
- Produces: `DraftPreviewView.onEdit: ((Program) -> Void)?` (nouveau parametre, nil par defaut), `TemplatePickerView.onEdit` et `GeneratorWizardView.onEdit` (propages), navigation programmatique dans `ProgramsView` via `NavigationPath`.

- [ ] **Step 1: Add swap to SessionEditorView**

Dans `SessionEditorView.swift` :

1. Etat : `@State private var swappingExercise: PrescribedExercise?`
2. Dans le `ForEach(sortedExercises)`, ajouter un `swipeAction` et une entree de menu contextuel sur chaque ligne :

```swift
.swipeActions(edge: .leading, allowsFullSwipe: false) {
    Button {
        swappingExercise = exercise
    } label: {
        Label("Remplacer", systemImage: "arrow.triangle.2.circlepath")
    }
    .tint(Theme.accent)
}
```

et dans le `.contextMenu` existant, avant le bouton Supprimer :

```swift
Button {
    swappingExercise = exercise
} label: {
    Label("Remplacer par...", systemImage: "arrow.triangle.2.circlepath")
}
```

3. Sheet (apres les sheets existantes) :

```swift
.sheet(item: $swappingExercise) { exercise in
    ExerciseSwapSheet(currentExerciseId: exercise.exerciseId) { newId, newName in
        exercise.exerciseId = newId
        exercise.displayName = newName
        try? modelContext.save()
    }
}
```

`PrescribedExercise` est un modele SwiftData : verifier que `exerciseId` et `displayName` sont des `var` (`grep -n "exerciseId\|displayName" App/Sources/Models/Program.swift`). Si `let`, les passer en `var`.

- [ ] **Step 2: Add the Modifier button to DraftPreviewView**

1. Nouveau parametre : `let onEdit: ((Program) -> Void)?` (ajouter dans l'`init` avec defaut `nil`, avant `onSaved` pour lisibilite).
2. Toolbar :

```swift
.toolbar {
    if onEdit != nil {
        ToolbarItem(placement: .primaryAction) {
            Button("Modifier") { saveAndEdit() }
        }
    }
}
```

3. Fonction :

```swift
// Enregistre le brouillon puis ouvre directement l'editeur complet du
// programme (via ProgramsView), au lieu d'obliger a enregistrer -> retrouver
// le programme dans la liste -> l'ouvrir.
private func saveAndEdit() {
    let program = currentDraft.toModel()
    modelContext.insert(program)
    try? modelContext.save()
    onSaved()
    onEdit?(program)
}
```

- [ ] **Step 3: Thread onEdit through the two flows and ProgramsView**

1. `TemplatePickerView` et `GeneratorWizardView` : ajouter `let onEdit: ((Program) -> Void)?` a cote de `onSaved`, le passer au `DraftPreviewView(...)` interne (parametre `onEdit:`).
2. `ProgramsView` : lire le fichier avant modification. Remplacer le `NavigationStack` par un `NavigationStack(path: $navigationPath)` avec `@State private var navigationPath = NavigationPath()` (le `navigationDestination(for: Program.self)` existant, ligne ~68, fonctionne tel quel avec le path). Aux deux points de presentation des sheets (`showingTemplatePicker`, `showingGeneratorWizard`), passer :

```swift
onEdit: { program in
    navigationPath.append(program)
}
```

(la sheet se ferme via `onSaved` avant l'append ; l'editeur s'ouvre pousse dans la pile de ProgramsView.)

- [ ] **Step 4: Build and verify manually**

Run: `xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Muscu.xcodeproj -scheme Muscu -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -3`
Expected: BUILD SUCCEEDED
Verifier : (a) apercu de generation -> "Modifier" enregistre et ouvre l'editeur du programme directement ; (b) editeur de seance -> swipe ou appui long sur un exercice -> "Remplacer" -> la prescription (series/reps/repos/format) est conservee, seul l'exercice change.

- [ ] **Step 5: Commit**

```bash
git add App/Sources
git commit -m "feat(app): swap dans l'editeur de seance et bouton Modifier sur l'apercu"
```

---

### Task 7: Modele de configuration IA multi-providers + ecran de reglages

**Files:**
- Create: `Packages/MuscuEngine/Sources/MuscuEngine/AI/AIProviderKind.swift`
- Modify: `App/Sources/Services/AIProviderConfig.swift`
- Modify: `App/Sources/Features/Settings/SettingsView.swift` (struct `AIProviderConfigView`, lignes ~259-292)
- Test: `Packages/MuscuEngine/Tests/MuscuEngineTests/AIProviderKindTests.swift`

**Interfaces:**
- Produces: `AIProviderKind` (enum `anthropic, openai, gemini, openAICompatible`, `String`, `Codable`, `CaseIterable`, `Sendable`) avec `displayName: String`, `defaultModel: String?`, `requiresBaseURL: Bool` ; `AIProviderConfig.selectedProvider: AIProviderKind`, `AIProviderConfig.apiKey(for:)`, `setApiKey(_:for:)`, `model(for:)`, `setModel(_:for:)`, `baseURL: String` (openAICompatible uniquement), `isConfigured: Bool`.

- [ ] **Step 1: Write the failing test (engine part)**

```swift
// Packages/MuscuEngine/Tests/MuscuEngineTests/AIProviderKindTests.swift
import Testing
@testable import MuscuEngine

struct AIProviderKindTests {
    @Test func fourProvidersExist() {
        #expect(AIProviderKind.allCases.count == 4)
    }

    @Test func defaultsAreCoherent() {
        #expect(AIProviderKind.anthropic.defaultModel == "claude-opus-5")
        #expect(AIProviderKind.anthropic.requiresBaseURL == false)
        #expect(AIProviderKind.openAICompatible.requiresBaseURL == true)
        #expect(AIProviderKind.openAICompatible.defaultModel == nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails, then implement AIProviderKind**

Run: `cd Packages/MuscuEngine && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AIProviderKindTests`
Expected: FAIL (compilation)

```swift
// Packages/MuscuEngine/Sources/MuscuEngine/AI/AIProviderKind.swift
import Foundation

/// Fournisseurs LLM supportes pour la generation de programme.
/// openAICompatible = n'importe quel endpoint au format OpenAI (Cursor, etc.).
public enum AIProviderKind: String, Codable, CaseIterable, Sendable {
    case anthropic
    case openai
    case gemini
    case openAICompatible

    public var displayName: String {
        switch self {
        case .anthropic: return "Claude (Anthropic)"
        case .openai: return "ChatGPT (OpenAI)"
        case .gemini: return "Gemini (Google)"
        case .openAICompatible: return "Compatible OpenAI (Cursor...)"
        }
    }

    /// Modele par defaut propose dans les reglages (nil = a saisir obligatoirement).
    public var defaultModel: String? {
        switch self {
        case .anthropic: return "claude-opus-5"
        case .openai: return nil
        case .gemini: return nil
        case .openAICompatible: return nil
        }
    }

    public var requiresBaseURL: Bool {
        self == .openAICompatible
    }
}
```

Run: `swift test --filter AIProviderKindTests` -> PASS

- [ ] **Step 3: Rework AIProviderConfig (app side)**

Remplacer le contenu de l'enum `AIProviderConfig` (garder `KeychainHelper` inchange) :

```swift
import Foundation
import Security
import MuscuEngine

// Configuration de la generation IA : provider selectionne, cle API par
// provider (Keychain), modele par provider et URL de base (UserDefaults).
enum AIProviderConfig {
    private static let providerKey = "aiProviderKind"
    private static let baseURLKey = "aiProviderBaseURL"

    static var selectedProvider: AIProviderKind {
        get {
            guard let raw = UserDefaults.standard.string(forKey: providerKey),
                  let kind = AIProviderKind(rawValue: raw) else { return .anthropic }
            return kind
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: providerKey) }
    }

    // URL de base, utilisee uniquement par openAICompatible (ex: https://api.exemple.com/v1).
    static var baseURL: String {
        get { UserDefaults.standard.string(forKey: baseURLKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: baseURLKey) }
    }

    static func model(for kind: AIProviderKind) -> String {
        UserDefaults.standard.string(forKey: "aiProviderModel.\(kind.rawValue)")
            ?? kind.defaultModel ?? ""
    }

    static func setModel(_ model: String, for kind: AIProviderKind) {
        UserDefaults.standard.set(model, forKey: "aiProviderModel.\(kind.rawValue)")
    }

    static func apiKey(for kind: AIProviderKind) -> String {
        KeychainHelper.read(account: "aiProviderApiKey.\(kind.rawValue)") ?? ""
    }

    static func setApiKey(_ key: String, for kind: AIProviderKind) {
        if key.isEmpty {
            KeychainHelper.delete(account: "aiProviderApiKey.\(kind.rawValue)")
        } else {
            KeychainHelper.save(account: "aiProviderApiKey.\(kind.rawValue)", value: key)
        }
    }

    /// Configure = cle + modele non vides pour le provider choisi,
    /// et URL de base valide si le provider l'exige.
    static var isConfigured: Bool {
        let kind = selectedProvider
        guard !apiKey(for: kind).isEmpty, !model(for: kind).isEmpty else { return false }
        if kind.requiresBaseURL {
            guard let url = URL(string: baseURL), url.scheme == "https" else { return false }
        }
        return true
    }

    /// Settings agreges pour le generateur IA (Task 8).
    static func currentSettings() -> AIProviderSettings? {
        guard isConfigured else { return nil }
        let kind = selectedProvider
        return AIProviderSettings(
            kind: kind,
            apiKey: apiKey(for: kind),
            model: model(for: kind),
            baseURL: kind.requiresBaseURL ? baseURL : nil
        )
    }
}
```

Note : `AIProviderSettings` est defini en Task 8 ; pour que cette task compile seule, definir des maintenant dans `AIProviderKind.swift` :

```swift
/// Parametres complets d'un appel LLM (agreges par l'app, consommes par le moteur).
public struct AIProviderSettings: Sendable {
    public let kind: AIProviderKind
    public let apiKey: String
    public let model: String
    public let baseURL: String?  // requis pour openAICompatible uniquement

    public init(kind: AIProviderKind, apiKey: String, model: String, baseURL: String?) {
        self.kind = kind
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
    }
}
```

L'ancienne cle Keychain `aiProviderApiKey` (sans suffixe) et l'ancienne cle UserDefaults `aiProviderModel` sont abandonnees sans migration : la fonctionnalite n'a jamais ete branchee (footer "non utilisee pour l'instant").

- [ ] **Step 4: Rework AIProviderConfigView (settings UI)**

Remplacer la struct `AIProviderConfigView` dans `SettingsView.swift` :

```swift
// Configuration de la generation IA : provider, cle, modele, test de connexion.
private struct AIProviderConfigView: View {
    @State private var provider = AIProviderConfig.selectedProvider
    @State private var apiKey = AIProviderConfig.apiKey(for: AIProviderConfig.selectedProvider)
    @State private var model = AIProviderConfig.model(for: AIProviderConfig.selectedProvider)
    @State private var baseURL = AIProviderConfig.baseURL

    var body: some View {
        Form {
            Section("Fournisseur") {
                Picker("Fournisseur", selection: $provider) {
                    ForEach(AIProviderKind.allCases, id: \.self) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .pickerStyle(.menu)
            }

            Section {
                if provider.requiresBaseURL {
                    TextField("URL de base (https://.../v1)", text: $baseURL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                }
                SecureField("Clé API", text: $apiKey)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                TextField("Modèle", text: $model)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } header: {
                Text("Connexion")
            } footer: {
                Text("La clé API est stockée de façon chiffrée dans le trousseau de l'appareil. Une fois configurée, l'option \"Générer avec l'IA\" apparaît dans le générateur de programme.")
            }

            ConnectionTestSection(provider: provider)  // ajoutee en Task 10 ; pour l'instant, omettre cette ligne
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Génération IA")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: provider) { _, newValue in
            AIProviderConfig.selectedProvider = newValue
            // Recharge les champs propres au provider selectionne.
            apiKey = AIProviderConfig.apiKey(for: newValue)
            model = AIProviderConfig.model(for: newValue)
        }
        .onChange(of: apiKey) { _, newValue in AIProviderConfig.setApiKey(newValue, for: provider) }
        .onChange(of: model) { _, newValue in AIProviderConfig.setModel(newValue, for: provider) }
        .onChange(of: baseURL) { _, newValue in AIProviderConfig.baseURL = newValue }
    }
}
```

(Ne PAS inclure la ligne `ConnectionTestSection` pour l'instant - elle arrive en Task 10.)

- [ ] **Step 5: Run tests, build, commit**

Run: `cd Packages/MuscuEngine && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
Expected: PASS
Run: `xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Muscu.xcodeproj -scheme Muscu -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -3`
Expected: BUILD SUCCEEDED

```bash
git add Packages/MuscuEngine App/Sources
git commit -m "feat(app): configuration IA multi-providers (Claude, OpenAI, Gemini, compatible OpenAI)"
```

---

### Task 8: Client HTTP injectable + requetes par provider + prompt

**Files:**
- Create: `Packages/MuscuEngine/Sources/MuscuEngine/AI/AIHTTPClient.swift`
- Create: `Packages/MuscuEngine/Sources/MuscuEngine/AI/AIProviderRequest.swift`
- Create: `Packages/MuscuEngine/Sources/MuscuEngine/AI/AIPromptBuilder.swift`
- Test: `Packages/MuscuEngine/Tests/MuscuEngineTests/AIProviderRequestTests.swift`
- Test: `Packages/MuscuEngine/Tests/MuscuEngineTests/AIPromptBuilderTests.swift`

**Interfaces:**
- Consumes: `AIProviderSettings` (Task 7), `StapleExercises` (Task 1), `GeneratorInput`, `ExerciseCatalog`.
- Produces:
  - `protocol AIHTTPClient: Sendable { func post(url: URL, headers: [String: String], body: Data) async throws -> Data }`
  - `AIProviderRequest.build(settings: AIProviderSettings, prompt: String) throws -> (url: URL, headers: [String: String], body: Data)`
  - `AIProviderRequest.extractText(from data: Data, kind: AIProviderKind) throws -> String`
  - `AIPromptBuilder.prompt(input: GeneratorInput, userNotes: String, catalog: ExerciseCatalog) -> String`
  - `enum AIGeneratorError: Error { case invalidConfiguration, httpError(Int, String), emptyResponse, invalidJSON(String), unknownExercises([String]), cancelled }`

- [ ] **Step 1: Verify the wire formats against official docs**

Avant d'ecrire le code, verifier avec WebFetch les formats exacts requete/reponse (le format Anthropic ci-dessous est deja verifie contre la reference officielle, ne verifier que les deux autres) :
- OpenAI chat completions : https://platform.openai.com/docs/api-reference/chat (champ `messages`, `response_format`, chemin de reponse `choices[0].message.content`).
- Gemini generateContent : https://ai.google.dev/api/generate-content (chemin `contents[].parts[].text`, `generationConfig.responseMimeType`, en-tete `x-goog-api-key`, reponse `candidates[0].content.parts[0].text`).

Si un format differe du code du Step 3, adapter le code (et les tests) au format officiel constate. Si WebFetch echoue (hors ligne), implementer tel quel et noter dans le commit que le format Gemini/OpenAI reste a verifier en ligne.

- [ ] **Step 2: Write the failing tests**

```swift
// Packages/MuscuEngine/Tests/MuscuEngineTests/AIProviderRequestTests.swift
import Foundation
import Testing
@testable import MuscuEngine

struct AIProviderRequestTests {
    private func settings(_ kind: AIProviderKind, baseURL: String? = nil) -> AIProviderSettings {
        AIProviderSettings(kind: kind, apiKey: "test-key", model: "test-model", baseURL: baseURL)
    }

    @Test func anthropicRequestShape() throws {
        let request = try AIProviderRequest.build(settings: settings(.anthropic), prompt: "PROMPT")
        #expect(request.url.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(request.headers["x-api-key"] == "test-key")
        #expect(request.headers["anthropic-version"] == "2023-06-01")
        let json = try JSONSerialization.jsonObject(with: request.body) as! [String: Any]
        #expect(json["model"] as? String == "test-model")
        #expect(json["max_tokens"] as? Int == 16000)
    }

    @Test func openAIRequestShape() throws {
        let request = try AIProviderRequest.build(settings: settings(.openai), prompt: "PROMPT")
        #expect(request.url.absoluteString == "https://api.openai.com/v1/chat/completions")
        #expect(request.headers["Authorization"] == "Bearer test-key")
    }

    @Test func openAICompatibleUsesBaseURL() throws {
        let request = try AIProviderRequest.build(
            settings: settings(.openAICompatible, baseURL: "https://llm.exemple.com/v1/"),
            prompt: "PROMPT"
        )
        #expect(request.url.absoluteString == "https://llm.exemple.com/v1/chat/completions")
    }

    @Test func openAICompatibleWithoutBaseURLThrows() {
        #expect(throws: AIGeneratorError.self) {
            _ = try AIProviderRequest.build(settings: settings(.openAICompatible), prompt: "P")
        }
    }

    @Test func geminiRequestShape() throws {
        let request = try AIProviderRequest.build(settings: settings(.gemini), prompt: "PROMPT")
        #expect(request.url.absoluteString
            == "https://generativelanguage.googleapis.com/v1beta/models/test-model:generateContent")
        #expect(request.headers["x-goog-api-key"] == "test-key")
    }

    @Test func extractTextAnthropic() throws {
        let data = #"{"content":[{"type":"text","text":"HELLO"}],"stop_reason":"end_turn"}"#.data(using: .utf8)!
        #expect(try AIProviderRequest.extractText(from: data, kind: .anthropic) == "HELLO")
    }

    @Test func extractTextOpenAI() throws {
        let data = #"{"choices":[{"message":{"role":"assistant","content":"HELLO"}}]}"#.data(using: .utf8)!
        #expect(try AIProviderRequest.extractText(from: data, kind: .openai) == "HELLO")
        #expect(try AIProviderRequest.extractText(from: data, kind: .openAICompatible) == "HELLO")
    }

    @Test func extractTextGemini() throws {
        let data = #"{"candidates":[{"content":{"parts":[{"text":"HELLO"}]}}]}"#.data(using: .utf8)!
        #expect(try AIProviderRequest.extractText(from: data, kind: .gemini) == "HELLO")
    }

    @Test func extractTextThrowsOnGarbage() {
        let data = #"{"error":"nope"}"#.data(using: .utf8)!
        #expect(throws: AIGeneratorError.self) {
            _ = try AIProviderRequest.extractText(from: data, kind: .anthropic)
        }
    }
}
```

```swift
// Packages/MuscuEngine/Tests/MuscuEngineTests/AIPromptBuilderTests.swift
import Testing
@testable import MuscuEngine

struct AIPromptBuilderTests {
    @Test func promptContainsWhitelistUserNotesAndSchema() throws {
        let catalog = try ExerciseCatalog.load()
        let input = GeneratorInput(
            goal: .strength, experience: .advanced, daysPerWeek: 4,
            sessionMinutes: 90, equipment: .fullGym, splitPreference: .upperLower,
            priorityMuscles: ["chest"], avoidAreas: ["lower back"]
        )
        let prompt = AIPromptBuilder.prompt(input: input, userNotes: "Je veux du volume epaules", catalog: catalog)
        #expect(prompt.contains("Barbell_Bench_Press_-_Medium_Grip"), "liste blanche presente")
        #expect(prompt.contains("Je veux du volume epaules"), "notes utilisateur presentes")
        #expect(prompt.contains("exerciseId"), "schema JSON DraftProgram decrit")
        #expect(prompt.contains("JSON"), "consigne de sortie JSON presente")
        #expect(prompt.contains("4"), "jours par semaine presents")
        #expect(!prompt.contains("Alternating_Floor_Press"), "les exos hors liste ne sont pas proposes")
    }

    @Test func bodyweightEquipmentFiltersWhitelist() throws {
        let catalog = try ExerciseCatalog.load()
        let input = GeneratorInput(
            goal: .calisthenics, experience: .beginner, daysPerWeek: 3,
            sessionMinutes: 45, equipment: .bodyweight, splitPreference: .auto,
            priorityMuscles: [], avoidAreas: []
        )
        let prompt = AIPromptBuilder.prompt(input: input, userNotes: "", catalog: catalog)
        #expect(prompt.contains("Pushups"))
        #expect(!prompt.contains("Leg_Press"), "exo machine exclu en poids du corps")
    }
}
```

- [ ] **Step 3: Run tests to verify they fail, then implement**

Run: `cd Packages/MuscuEngine && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AIProviderRequestTests`
Expected: FAIL (compilation)

```swift
// Packages/MuscuEngine/Sources/MuscuEngine/AI/AIHTTPClient.swift
import Foundation

/// Client HTTP injectable : URLSession cote app, mock dans les tests.
/// MuscuEngine ne fait jamais d'appel reseau direct.
public protocol AIHTTPClient: Sendable {
    func post(url: URL, headers: [String: String], body: Data) async throws -> Data
}

/// Erreurs de la generation IA, exploitables par l'UI.
public enum AIGeneratorError: Error, Sendable {
    case invalidConfiguration
    case httpError(Int, String)
    case emptyResponse
    case invalidJSON(String)
    case unknownExercises([String])
    case cancelled
}
```

```swift
// Packages/MuscuEngine/Sources/MuscuEngine/AI/AIProviderRequest.swift
import Foundation

/// Construction des requetes HTTP et extraction du texte de reponse,
/// par provider. Formats verifies contre la documentation officielle
/// de chaque API (voir plan, Task 8 Step 1).
public enum AIProviderRequest {
    public static func build(
        settings: AIProviderSettings,
        prompt: String
    ) throws -> (url: URL, headers: [String: String], body: Data) {
        switch settings.kind {
        case .anthropic:
            let url = URL(string: "https://api.anthropic.com/v1/messages")!
            let headers = [
                "content-type": "application/json",
                "x-api-key": settings.apiKey,
                "anthropic-version": "2023-06-01",
            ]
            let payload: [String: Any] = [
                "model": settings.model,
                "max_tokens": 16000,
                "messages": [["role": "user", "content": prompt]],
            ]
            return (url, headers, try JSONSerialization.data(withJSONObject: payload))

        case .openai, .openAICompatible:
            let base: String
            if settings.kind == .openai {
                base = "https://api.openai.com/v1"
            } else {
                guard let raw = settings.baseURL, !raw.isEmpty else {
                    throw AIGeneratorError.invalidConfiguration
                }
                base = raw.hasSuffix("/") ? String(raw.dropLast()) : raw
            }
            guard let url = URL(string: base + "/chat/completions") else {
                throw AIGeneratorError.invalidConfiguration
            }
            let headers = [
                "Content-Type": "application/json",
                "Authorization": "Bearer \(settings.apiKey)",
            ]
            let payload: [String: Any] = [
                "model": settings.model,
                "messages": [["role": "user", "content": prompt]],
                "response_format": ["type": "json_object"],
            ]
            return (url, headers, try JSONSerialization.data(withJSONObject: payload))

        case .gemini:
            guard let url = URL(string:
                "https://generativelanguage.googleapis.com/v1beta/models/\(settings.model):generateContent"
            ) else {
                throw AIGeneratorError.invalidConfiguration
            }
            let headers = [
                "Content-Type": "application/json",
                "x-goog-api-key": settings.apiKey,
            ]
            let payload: [String: Any] = [
                "contents": [["parts": [["text": prompt]]]],
                "generationConfig": ["responseMimeType": "application/json"],
            ]
            return (url, headers, try JSONSerialization.data(withJSONObject: payload))
        }
    }

    public static func extractText(from data: Data, kind: AIProviderKind) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIGeneratorError.emptyResponse
        }
        let text: String?
        switch kind {
        case .anthropic:
            let content = json["content"] as? [[String: Any]]
            text = content?.first(where: { $0["type"] as? String == "text" })?["text"] as? String
        case .openai, .openAICompatible:
            let choices = json["choices"] as? [[String: Any]]
            let message = choices?.first?["message"] as? [String: Any]
            text = message?["content"] as? String
        case .gemini:
            let candidates = json["candidates"] as? [[String: Any]]
            let content = candidates?.first?["content"] as? [String: Any]
            let parts = content?["parts"] as? [[String: Any]]
            text = parts?.first?["text"] as? String
        }
        guard let text, !text.isEmpty else { throw AIGeneratorError.emptyResponse }
        return text
    }
}
```

```swift
// Packages/MuscuEngine/Sources/MuscuEngine/AI/AIPromptBuilder.swift
import Foundation

/// Construit le prompt de generation : parametres du wizard + notes libres
/// + liste blanche des exercices autorises (filtree par equipement) + schema
/// JSON attendu (celui de DraftProgram).
public enum AIPromptBuilder {
    public static func prompt(input: GeneratorInput, userNotes: String, catalog: ExerciseCatalog) -> String {
        let byId = Dictionary(uniqueKeysWithValues: catalog.all.map { ($0.id, $0) })
        let equipmentForSelection: TrainingEquipment = (input.goal == .calisthenics) ? .bodyweight : input.equipment

        let allowed = StapleExercises.all.compactMap { staple -> String? in
            guard let exercise = byId[staple.catalogId] else { return nil }
            guard isEquipmentAllowed(exercise.equipment, for: equipmentForSelection) else { return nil }
            let equipment = exercise.equipment ?? "libre"
            let muscle = exercise.primaryMuscles.first ?? "?"
            return "- \(exercise.id) | \(exercise.nameFr) | \(muscle) | \(equipment)"
        }.joined(separator: "\n")

        let goalLabel: String
        switch input.goal {
        case .hypertrophy: goalLabel = "prise de masse (hypertrophie)"
        case .strength: goalLabel = "force"
        case .fatLoss: goalLabel = "perte de poids"
        case .endurance: goalLabel = "endurance musculaire"
        case .pullUpProgress: goalLabel = "progression aux tractions"
        case .calisthenics: goalLabel = "calisthenics / poids du corps"
        }
        let experienceLabel: String
        switch input.experience {
        case .beginner: experienceLabel = "debutant"
        case .intermediate: experienceLabel = "intermediaire"
        case .advanced: experienceLabel = "avance"
        }

        var lines: [String] = []
        lines.append("Tu es un coach de musculation. Genere un programme d'entrainement complet.")
        lines.append("")
        lines.append("Parametres :")
        lines.append("- Objectif : \(goalLabel)")
        lines.append("- Niveau : \(experienceLabel)")
        lines.append("- \(input.daysPerWeek) seances par semaine, environ \(input.sessionMinutes) minutes chacune")
        if !input.priorityMuscles.isEmpty {
            lines.append("- Muscles prioritaires : \(input.priorityMuscles.joined(separator: ", "))")
        }
        if !input.avoidAreas.isEmpty {
            lines.append("- Zones a menager (aucun exercice les ciblant) : \(input.avoidAreas.joined(separator: ", "))")
        }
        let notes = userNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty {
            lines.append("")
            lines.append("Demandes specifiques de l'utilisateur :")
            lines.append(notes)
        }
        lines.append("")
        lines.append("Exercices AUTORISES (utilise UNIQUEMENT ces exerciseId, exactement tels quels) :")
        lines.append(allowed)
        lines.append("")
        lines.append("Reponds UNIQUEMENT avec un objet JSON valide (aucun texte autour, pas de bloc markdown) au schema exact suivant :")
        lines.append("""
        {"name": "nom du programme", "notes": "conseils courts",
         "sessions": [{"name": "nom seance", "warmupEnabled": true,
           "exercises": [{"exerciseId": "id exact de la liste", "displayName": "nom francais de la liste",
             "sets": 4, "repsLower": 6, "repsUpper": 12, "restSeconds": 90, "percentOneRepMax": null}]}]}
        """)
        lines.append("Contraintes : exactement \(input.daysPerWeek) sessions ; 4 a 7 exercices par session ; percentOneRepMax est null ou un nombre (ex 80).")
        return lines.joined(separator: "\n")
    }

    // Copie de la regle du generateur local (RuleBasedGenerator.isEquipmentAllowed est private).
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
}
```

Amelioration facultative si simple : rendre `RuleBasedGenerator.isEquipmentAllowed` `static` interne (non private) et l'appeler depuis `AIPromptBuilder` au lieu de dupliquer (DRY). Faire ce refactor si les tests restent verts.

- [ ] **Step 4: Run tests and commit**

Run: `cd Packages/MuscuEngine && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
Expected: PASS

```bash
git add Packages/MuscuEngine
git commit -m "feat(engine): requetes par provider IA et construction du prompt avec liste blanche"
```

---

### Task 9: AIProgramGenerator (appel, parsing, validation, retry)

**Files:**
- Create: `Packages/MuscuEngine/Sources/MuscuEngine/AI/AIProgramGenerator.swift`
- Test: `Packages/MuscuEngine/Tests/MuscuEngineTests/AIProgramGeneratorTests.swift`

**Interfaces:**
- Consumes: `AIHTTPClient`, `AIProviderRequest`, `AIPromptBuilder`, `AIProviderSettings`, `ExerciseCatalog`, `DraftProgram` (Codable).
- Produces: `AIProgramGenerator(settings:client:catalog:)` avec `func generate(input: GeneratorInput, userNotes: String) async throws -> DraftProgram`.

- [ ] **Step 1: Write the failing tests**

```swift
// Packages/MuscuEngine/Tests/MuscuEngineTests/AIProgramGeneratorTests.swift
import Foundation
import Testing
@testable import MuscuEngine

/// Mock : rejoue des reponses pre-enregistrees et memorise les requetes.
final class MockAIHTTPClient: AIHTTPClient, @unchecked Sendable {
    var responses: [Data]
    private(set) var requests: [(url: URL, headers: [String: String], body: Data)] = []

    init(responses: [Data]) {
        self.responses = responses
    }

    func post(url: URL, headers: [String: String], body: Data) async throws -> Data {
        requests.append((url, headers, body))
        guard !responses.isEmpty else { throw AIGeneratorError.emptyResponse }
        return responses.removeFirst()
    }
}

private func anthropicResponse(text: String) -> Data {
    let payload: [String: Any] = ["content": [["type": "text", "text": text]]]
    return try! JSONSerialization.data(withJSONObject: payload)
}

private let validDraftJSON = """
{"name": "Programme test", "notes": "",
 "sessions": [{"name": "Seance A", "warmupEnabled": true,
   "exercises": [{"exerciseId": "Barbell_Squat", "displayName": "Squat à la barre",
     "sets": 4, "repsLower": 6, "repsUpper": 10, "restSeconds": 120, "percentOneRepMax": null}]}]}
"""

private func makeInput() -> GeneratorInput {
    GeneratorInput(
        goal: .hypertrophy, experience: .intermediate, daysPerWeek: 1,
        sessionMinutes: 60, equipment: .fullGym, splitPreference: .auto,
        priorityMuscles: [], avoidAreas: []
    )
}

private func makeSettings() -> AIProviderSettings {
    AIProviderSettings(kind: .anthropic, apiKey: "k", model: "m", baseURL: nil)
}

struct AIProgramGeneratorTests {
    @Test func validResponseProducesDraft() async throws {
        let catalog = try ExerciseCatalog.load()
        let client = MockAIHTTPClient(responses: [anthropicResponse(text: validDraftJSON)])
        let generator = AIProgramGenerator(settings: makeSettings(), client: client, catalog: catalog)
        let draft = try await generator.generate(input: makeInput(), userNotes: "")
        #expect(draft.sessions.count == 1)
        #expect(draft.sessions[0].exercises[0].exerciseId == "Barbell_Squat")
        #expect(client.requests.count == 1)
    }

    @Test func markdownFencedResponseIsCleaned() async throws {
        let catalog = try ExerciseCatalog.load()
        let fenced = "```json\n" + validDraftJSON + "\n```"
        let client = MockAIHTTPClient(responses: [anthropicResponse(text: fenced)])
        let generator = AIProgramGenerator(settings: makeSettings(), client: client, catalog: catalog)
        let draft = try await generator.generate(input: makeInput(), userNotes: "")
        #expect(draft.sessions.count == 1)
    }

    @Test func unknownExerciseIdTriggersOneRetryThenSucceeds() async throws {
        let catalog = try ExerciseCatalog.load()
        let bad = validDraftJSON.replacingOccurrences(of: "Barbell_Squat", with: "Exo_Invente")
        let client = MockAIHTTPClient(responses: [
            anthropicResponse(text: bad),
            anthropicResponse(text: validDraftJSON),
        ])
        let generator = AIProgramGenerator(settings: makeSettings(), client: client, catalog: catalog)
        let draft = try await generator.generate(input: makeInput(), userNotes: "")
        #expect(draft.sessions[0].exercises[0].exerciseId == "Barbell_Squat")
        #expect(client.requests.count == 2, "un retry exactement")
        // Le second prompt contient le feedback d'erreur.
        let secondBody = String(data: client.requests[1].body, encoding: .utf8) ?? ""
        #expect(secondBody.contains("Exo_Invente"))
    }

    @Test func unknownExerciseIdTwiceThrows() async throws {
        let catalog = try ExerciseCatalog.load()
        let bad = validDraftJSON.replacingOccurrences(of: "Barbell_Squat", with: "Exo_Invente")
        let client = MockAIHTTPClient(responses: [
            anthropicResponse(text: bad),
            anthropicResponse(text: bad),
        ])
        let generator = AIProgramGenerator(settings: makeSettings(), client: client, catalog: catalog)
        await #expect(throws: AIGeneratorError.self) {
            _ = try await generator.generate(input: makeInput(), userNotes: "")
        }
        #expect(client.requests.count == 2)
    }

    @Test func nearMissExerciseIdIsFixedByNameMatch() async throws {
        // displayName connu mais exerciseId errone -> correction par recherche du nom.
        let catalog = try ExerciseCatalog.load()
        let nearMiss = validDraftJSON.replacingOccurrences(of: "Barbell_Squat", with: "Barbell_Squats")
        let client = MockAIHTTPClient(responses: [anthropicResponse(text: nearMiss)])
        let generator = AIProgramGenerator(settings: makeSettings(), client: client, catalog: catalog)
        let draft = try await generator.generate(input: makeInput(), userNotes: "")
        #expect(draft.sessions[0].exercises[0].exerciseId == "Barbell_Squat")
        #expect(client.requests.count == 1, "corrige localement, pas de retry")
    }

    @Test func invalidJSONThrows() async throws {
        let catalog = try ExerciseCatalog.load()
        let client = MockAIHTTPClient(responses: [
            anthropicResponse(text: "Voici votre programme : faites du sport."),
            anthropicResponse(text: "toujours pas du JSON"),
        ])
        let generator = AIProgramGenerator(settings: makeSettings(), client: client, catalog: catalog)
        await #expect(throws: AIGeneratorError.self) {
            _ = try await generator.generate(input: makeInput(), userNotes: "")
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd Packages/MuscuEngine && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AIProgramGeneratorTests`
Expected: FAIL (compilation)

- [ ] **Step 3: Implement AIProgramGenerator**

```swift
// Packages/MuscuEngine/Sources/MuscuEngine/AI/AIProgramGenerator.swift
import Foundation

/// Contrat asynchrone (pendant reseau du ProgramGenerator synchrone local).
public protocol AsyncProgramGenerator: Sendable {
    func generate(input: GeneratorInput, userNotes: String) async throws -> DraftProgram
}

/// Generation de programme par LLM : prompt -> appel HTTP -> extraction texte ->
/// nettoyage -> decodage DraftProgram -> validation des ids -> 1 retry avec
/// feedback en cas d'ids inconnus ou de JSON invalide.
public struct AIProgramGenerator: AsyncProgramGenerator {
    private let settings: AIProviderSettings
    private let client: AIHTTPClient
    private let catalog: ExerciseCatalog

    public init(settings: AIProviderSettings, client: AIHTTPClient, catalog: ExerciseCatalog) {
        self.settings = settings
        self.client = client
        self.catalog = catalog
    }

    public func generate(input: GeneratorInput, userNotes: String) async throws -> DraftProgram {
        let basePrompt = AIPromptBuilder.prompt(input: input, userNotes: userNotes, catalog: catalog)

        var lastFailure: String?
        for attempt in 0..<2 {
            try Task.checkCancellation()
            var prompt = basePrompt
            if attempt > 0, let lastFailure {
                prompt += "\n\nTa reponse precedente etait invalide : \(lastFailure)\nCorrige et renvoie UNIQUEMENT le JSON."
            }
            let request = try AIProviderRequest.build(settings: settings, prompt: prompt)
            let data = try await client.post(url: request.url, headers: request.headers, body: request.body)
            let text = try AIProviderRequest.extractText(from: data, kind: settings.kind)

            switch Self.parseAndValidate(text: text, catalog: catalog) {
            case .success(let draft):
                return draft
            case .failure(let reason):
                lastFailure = reason
            }
        }
        // Deux tentatives infructueuses : erreur typee selon la derniere cause.
        if let lastFailure, lastFailure.contains("exerciseId inconnus") {
            throw AIGeneratorError.unknownExercises([lastFailure])
        }
        throw AIGeneratorError.invalidJSON(lastFailure ?? "reponse invalide")
    }

    // MARK: - Parsing et validation

    private enum ParseResult {
        case success(DraftProgram)
        case failure(String)
    }

    private static func parseAndValidate(text: String, catalog: ExerciseCatalog) -> ParseResult {
        let cleaned = cleanJSON(text)
        guard let data = cleaned.data(using: .utf8),
              var draft = try? JSONDecoder().decode(DraftProgram.self, from: data) else {
            return .failure("le JSON ne correspond pas au schema demande")
        }

        let knownIds = Set(catalog.all.map(\.id))
        var unknown: [String] = []
        for sessionIndex in draft.sessions.indices {
            for exerciseIndex in draft.sessions[sessionIndex].exercises.indices {
                let exercise = draft.sessions[sessionIndex].exercises[exerciseIndex]
                if knownIds.contains(exercise.exerciseId) { continue }
                // Tentative de correction locale : retrouver l'exercice par son nom.
                if let match = catalog.search(exercise.displayName).first {
                    draft.sessions[sessionIndex].exercises[exerciseIndex].exerciseId = match.id
                    draft.sessions[sessionIndex].exercises[exerciseIndex].displayName = match.nameFr
                } else {
                    unknown.append(exercise.exerciseId)
                }
            }
        }
        guard unknown.isEmpty else {
            return .failure("exerciseId inconnus : \(unknown.joined(separator: ", "))")
        }
        guard !draft.sessions.isEmpty else {
            return .failure("aucune session dans le programme")
        }
        return .success(draft)
    }

    /// Retire les clotures markdown eventuelles et isole l'objet JSON
    /// (du premier "{" au dernier "}").
    private static func cleanJSON(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let first = cleaned.firstIndex(of: "{"), let last = cleaned.lastIndex(of: "}") else {
            return cleaned
        }
        return String(cleaned[first...last])
    }
}
```

Attention au test `nearMissExerciseIdIsFixedByNameMatch` : verifier le comportement reel de `ExerciseCatalog.search` (lire `ExerciseCatalog.swift:30`) - si la recherche sur "Squat à la barre" ne renvoie pas `Barbell_Squat` en premier, adapter la correction locale (par exemple chercher une correspondance exacte nameFr d'abord, puis `search().first`). Le test fait foi : le comportement attendu est que l'id soit corrige localement sans retry.

- [ ] **Step 4: Run tests and commit**

Run: `cd Packages/MuscuEngine && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
Expected: PASS

```bash
git add Packages/MuscuEngine
git commit -m "feat(engine): AIProgramGenerator avec validation des exercices et retry"
```

---

### Task 10: Client URLSession + test de connexion dans les reglages

**Files:**
- Create: `App/Sources/Services/URLSessionAIClient.swift`
- Modify: `App/Sources/Features/Settings/SettingsView.swift` (AIProviderConfigView)

**Interfaces:**
- Consumes: `AIHTTPClient`, `AIProviderRequest`, `AIProviderConfig.currentSettings()`.
- Produces: `URLSessionAIClient` (impl `AIHTTPClient`, timeout 60 s), section "Tester la connexion" dans les reglages.

- [ ] **Step 1: Implement URLSessionAIClient**

```swift
// App/Sources/Services/URLSessionAIClient.swift
import Foundation
import MuscuEngine

// Implementation URLSession du client HTTP injecte dans AIProgramGenerator.
// Timeout volontairement long (60 s) : la generation d'un programme complet
// peut prendre plusieurs dizaines de secondes selon le provider.
struct URLSessionAIClient: AIHTTPClient {
    func post(url: URL, headers: [String: String], body: Data) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 60
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw AIGeneratorError.httpError(http.statusCode, String(bodyText.prefix(300)))
        }
        return data
    }
}
```

- [ ] **Step 2: Add the connection test section to AIProviderConfigView**

Ajouter dans `SettingsView.swift`, a la fin du `Form` de `AIProviderConfigView` :

```swift
Section {
    Button {
        testConnection()
    } label: {
        if isTesting {
            HStack {
                ProgressView()
                Text("Test en cours...")
            }
        } else {
            Text("Tester la connexion")
        }
    }
    .disabled(isTesting || !AIProviderConfig.isConfigured)

    if let testResult {
        Label(testResult.message, systemImage: testResult.success ? "checkmark.circle.fill" : "xmark.circle.fill")
            .foregroundStyle(testResult.success ? .green : .red)
            .font(.footnote)
    }
} footer: {
    if !AIProviderConfig.isConfigured {
        Text("Renseignez la clé API et le modèle pour tester.")
    }
}
```

avec les etats et la fonction dans la struct :

```swift
@State private var isTesting = false
@State private var testResult: (success: Bool, message: String)?

private func testConnection() {
    guard let settings = AIProviderConfig.currentSettings() else { return }
    isTesting = true
    testResult = nil
    Task {
        do {
            let request = try AIProviderRequest.build(
                settings: settings,
                prompt: "Reponds uniquement avec le JSON {\"ok\": true}"
            )
            let data = try await URLSessionAIClient().post(url: request.url, headers: request.headers, body: request.body)
            _ = try AIProviderRequest.extractText(from: data, kind: settings.kind)
            testResult = (true, "Connexion réussie")
        } catch let AIGeneratorError.httpError(code, body) {
            testResult = (false, "Erreur HTTP \(code) : \(body)")
        } catch {
            testResult = (false, "Échec : \(error.localizedDescription)")
        }
        isTesting = false
    }
}
```

Ajouter `import MuscuEngine` en tete de `SettingsView.swift` si absent.

- [ ] **Step 3: Build and verify**

Run: `xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Muscu.xcodeproj -scheme Muscu -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -3`
Expected: BUILD SUCCEEDED
Verification manuelle : Reglages -> Generation IA -> saisir une cle invalide -> "Tester la connexion" affiche une erreur HTTP claire (401). Le bouton est grise tant que cle/modele manquent.

- [ ] **Step 4: Commit**

```bash
git add App/Sources
git commit -m "feat(app): client URLSession et test de connexion IA dans les reglages"
```

---

### Task 11: Generation IA dans le wizard

**Files:**
- Modify: `App/Sources/Features/Programs/GeneratorWizardView.swift`

**Interfaces:**
- Consumes: `AIProgramGenerator` (Task 9), `URLSessionAIClient` (Task 10), `AIProviderConfig.currentSettings()`, `NetworkStatus` (existant, `App/Sources/Services/NetworkStatus.swift` - lire le fichier pour la propriete exacte d'etat en ligne), `DraftPreviewView` (le draft IA arrive dans le meme apercu, swap inclus).

- [ ] **Step 1: Read NetworkStatus and the last wizard step**

Lire `App/Sources/Services/NetworkStatus.swift` (comment l'observer : propriete `isOnline` ou equivalente, injection environnement ou singleton) et la derniere etape du wizard (`stepContent` pour `step == 8`) pour reperer le bouton "Générer" existant.

- [ ] **Step 2: Add AI option to the final step**

Dans `GeneratorWizardView` :

1. Etats supplementaires :

```swift
@State private var aiNotes = ""
@State private var isGeneratingWithAI = false
@State private var aiTask: Task<Void, Never>?
```

2. Dans le contenu de la derniere etape (celle du bouton "Générer"), sous le bouton existant, ajouter la section IA (visible uniquement si configuree) :

```swift
if AIProviderConfig.isConfigured {
    VStack(alignment: .leading, spacing: 12) {
        Divider()
        Text("Ou avec l'IA")
            .font(.headline)
        TextField(
            "Objectifs, contraintes, préférences... (optionnel)",
            text: $aiNotes,
            axis: .vertical
        )
        .lineLimit(3...6)
        .textFieldStyle(.roundedBorder)

        Button {
            generateWithAI()
        } label: {
            Label("Générer avec l'IA", systemImage: "sparkles")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(Theme.accent)
        .disabled(!networkAvailable)

        if !networkAvailable {
            Text("Connexion internet requise pour la génération IA.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
```

(`networkAvailable` : brancher sur NetworkStatus selon le pattern releve au Step 1 - le meme que celui du bouton video hors ligne.)

3. La generation asynchrone avec ecran d'attente annulable :

```swift
private func generateWithAI() {
    guard let goal, let experience, let daysPerWeek, let sessionMinutes, let equipment else {
        errorMessage = "Toutes les questions doivent être renseignées."
        return
    }
    guard let settings = AIProviderConfig.currentSettings() else { return }
    let input = GeneratorInput(
        goal: goal, experience: experience, daysPerWeek: daysPerWeek,
        sessionMinutes: sessionMinutes, equipment: equipment,
        splitPreference: splitPreference,
        priorityMuscles: Array(priorityMuscles), avoidAreas: Array(avoidAreas)
    )
    draftInput = input
    isGeneratingWithAI = true
    aiTask = Task {
        do {
            let generator = AIProgramGenerator(
                settings: settings,
                client: URLSessionAIClient(),
                catalog: catalogStore.catalog
            )
            let draft = try await generator.generate(input: input, userNotes: aiNotes)
            if !Task.isCancelled {
                generatedDraft = draft
            }
        } catch is CancellationError {
            // Annule par l'utilisateur : rien a afficher.
        } catch let AIGeneratorError.httpError(code, _) {
            errorMessage = "Le fournisseur IA a répondu avec une erreur (HTTP \(code)). Vérifiez la clé et le modèle dans les réglages, ou utilisez le générateur local."
        } catch {
            errorMessage = "La génération IA a échoué. Vous pouvez réessayer ou utiliser le générateur local."
        }
        isGeneratingWithAI = false
    }
}
```

4. Overlay d'attente (sur le corps du wizard) :

```swift
.overlay {
    if isGeneratingWithAI {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                Text("Génération du programme par l'IA...")
                    .font(.headline)
                Button("Annuler") {
                    aiTask?.cancel()
                    isGeneratingWithAI = false
                }
                .buttonStyle(.bordered)
            }
            .padding(24)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
}
```

Note : le draft IA arrive dans le meme `navigationDestination(item: $generatedDraft)` que le generateur local. Le bouton "Régénérer" de l'apercu rappelle le generateur LOCAL (comportement assume : regenerer apres une generation IA bascule sur le local ; pour regenerer en IA, revenir en arriere et relancer). Ne pas complexifier.

- [ ] **Step 3: Build and verify manually**

Run: `xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Muscu.xcodeproj -scheme Muscu -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -3`
Expected: BUILD SUCCEEDED
Verifier : sans cle configuree, la derniere etape du wizard est inchangee (pas de section IA). Avec une cle configuree : la section apparait, le bouton lance l'overlay, "Annuler" interrompt. Avec une vraie cle (test utilisateur) : le programme genere s'affiche dans l'apercu avec uniquement des exos de la liste blanche.

- [ ] **Step 4: Commit**

```bash
git add App/Sources
git commit -m "feat(app): generation de programme par IA dans le wizard (asynchrone, annulable)"
```

---

### Task 12: Verification finale (suites completes + UI tests)

**Files:**
- Modify (si necessaire): `UITests/ProgramsFlowTests.swift`

- [ ] **Step 1: Full engine suite**

Run: `cd Packages/MuscuEngine && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
Expected: PASS (46 tests d'origine + les nouveaux, tous verts)

- [ ] **Step 2: Full app build + UI test suite**

Run: `xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Muscu.xcodeproj -scheme Muscu -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MuscuUITests test 2>&1 | grep -E "Test [Cc]ase|Test [Ss]uite|TEST"`
Expected: 7 suites / 16 tests PASS. Points de vigilance :
- `ProgramsFlowTests.testCreateFromTemplate` et `testGeneratorWizardAllSteps` : la derniere etape du wizard et l'apercu ont change (icone swap, bouton Modifier, section IA invisible sans cle). Si un test echoue sur un element deplace, adapter le test (les helpers anti-flaky de `UITests/Support/XCUIApplication+Launch.swift` : `tapWhenReady`, `tapUntilReveals`, `waitAndAssert`). Toujours lancer les suites en avant-plan (runs bloquants), jamais en arriere-plan.

- [ ] **Step 3: Add a UI test for the swap (aperçu)**

Ajouter dans `ProgramsFlowTests.swift` :

```swift
// Swap d'exercice dans l'apercu de generation : l'icone d'echange ouvre la
// sheet d'alternatives et le remplacement met a jour la ligne.
func testSwapExerciseInDraftPreview() {
    let app = XCUIApplication()
    app.launchEmpty()
    tapWhenReady(app.tabBars.buttons["Programmes"])
    waitAndAssert(app.navigationBars["Programmes"])

    tapUntilReveals(app.buttons["programs.addButton"], reveals: app.buttons["Depuis un modèle"])
    tapWhenReady(app.buttons["Depuis un modèle"])

    // Choisir le premier modele propose puis attendre l'apercu.
    tapWhenReady(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Full Body'")).firstMatch)
    waitAndAssert(app.navigationBars["Aperçu"], timeout: 15)

    // Ouvrir la sheet de swap du premier exercice.
    let swapButton = app.buttons.matching(
        NSPredicate(format: "label BEGINSWITH 'Remplacer '")
    ).firstMatch
    tapUntilReveals(swapButton, reveals: app.navigationBars["Remplacer par"])

    // Choisir la premiere alternative (premiere cellule de la section) et
    // verifier que la sheet se ferme.
    tapWhenReady(app.cells.firstMatch)
    waitForDisappearance(app.navigationBars["Remplacer par"], timeout: 10)
    waitAndAssert(app.navigationBars["Aperçu"])
}
```

Adapter les selecteurs a la realite de l'ecran au moment de l'implementation (le flux "Depuis un modèle" existant est couvert par `testCreateFromTemplate` - s'inspirer de ses selecteurs exacts pour les premieres etapes). Lancer :
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Muscu.xcodeproj -scheme Muscu -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MuscuUITests/ProgramsFlowTests test`
Expected: PASS

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "test(app): couverture UI du swap d'alternatives et verification finale"
```

Puis relancer une derniere fois la suite UI complete (avant-plan) et `swift test` pour confirmer que tout est vert avant d'annoncer la fin.
