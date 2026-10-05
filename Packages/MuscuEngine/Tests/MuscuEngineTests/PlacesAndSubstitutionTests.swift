import Foundation
import Testing
@testable import MuscuEngine

private let bench = CatalogExercise(
    id: "bench",
    name: "Barbell Bench Press",
    nameFr: "Développé couché à la barre",
    force: "push",
    level: "intermediate",
    mechanic: "compound",
    equipment: "barbell",
    primaryMuscles: ["chest"],
    secondaryMuscles: ["triceps", "shoulders"]
)

private let dumbbellPress = CatalogExercise(
    id: "db-press",
    name: "Dumbbell Bench Press",
    nameFr: "Développé couché aux haltères",
    force: "push",
    level: "intermediate",
    mechanic: "compound",
    equipment: "dumbbell",
    primaryMuscles: ["chest"],
    secondaryMuscles: ["triceps"]
)

private let pushup = CatalogExercise(
    id: "pushup",
    name: "Push-up",
    nameFr: "Pompes",
    force: "push",
    level: "beginner",
    mechanic: "compound",
    equipment: "body only",
    primaryMuscles: ["chest"],
    secondaryMuscles: ["triceps"]
)

private let cableFly = CatalogExercise(
    id: "fly",
    name: "Cable Fly",
    nameFr: "Écarté à la poulie",
    force: "push",
    level: "intermediate",
    mechanic: "isolation",
    equipment: "cable",
    primaryMuscles: ["chest"],
    secondaryMuscles: []
)

private let squat = CatalogExercise(
    id: "squat",
    name: "Barbell Squat",
    nameFr: "Squat à la barre",
    force: "push",
    level: "intermediate",
    mechanic: "compound",
    equipment: "barbell",
    primaryMuscles: ["quadriceps"],
    secondaryMuscles: ["glutes"]
)

private let catalog = [bench, dumbbellPress, pushup, cableFly, squat]

@Suite("Lieux et matériel")
struct EquipmentInventoryTests {
    @Test("Un inventaire vide n'interdit rien")
    func emptyInventoryAllowsEverything() {
        let inventory = EquipmentInventory()
        #expect(inventory.allows(equipment: "barbell"))
        #expect(inventory.allows(equipment: "machine"))
    }

    @Test("Un inventaire renseigné filtre le matériel absent")
    func inventoryFiltersMissingEquipment() {
        let inventory = EquipmentInventory(items: [EquipmentAvailability(equipmentId: "dumbbell")])
        #expect(inventory.allows(equipment: "dumbbell"))
        #expect(!inventory.allows(equipment: "barbell"))
    }

    @Test("Le poids du corps reste toujours disponible")
    func bodyweightIsAlwaysAvailable() {
        let inventory = EquipmentInventory(items: [EquipmentAvailability(equipmentId: "dumbbell")])
        #expect(inventory.allows(equipment: "body only"))
    }

    @Test("Un matériel déclaré deux fois ne compte qu'une fois")
    func duplicateEquipmentIsCollapsed() {
        let inventory = EquipmentInventory(items: [
            EquipmentAvailability(equipmentId: "dumbbell", maximumLoad: 30),
            EquipmentAvailability(equipmentId: "dumbbell", maximumLoad: 10),
        ])
        #expect(inventory.items.count == 1)
        #expect(inventory.availability(for: "dumbbell")?.maximumLoad == 30)
    }

    @Test("La charge est alignée sur le pas puis bornée")
    func loadIsSnappedAndClamped() {
        let inventory = EquipmentInventory(items: [
            EquipmentAvailability(equipmentId: "dumbbell", minimumLoad: 4, maximumLoad: 30, increment: 2),
        ])
        #expect(inventory.practicableLoad(17, equipmentId: "dumbbell") == 18)
        #expect(inventory.practicableLoad(2, equipmentId: "dumbbell") == 4)
        #expect(inventory.practicableLoad(45, equipmentId: "dumbbell") == 30)
    }

    @Test("Sans contrainte déclarée, la charge n'est pas modifiée")
    func unconstrainedLoadIsUnchanged() {
        let inventory = EquipmentInventory(items: [EquipmentAvailability(equipmentId: "barbell")])
        #expect(inventory.practicableLoad(63.5, equipmentId: "barbell") == 63.5)
    }
}

@Suite("Substitutions")
struct SubstitutionTests {
    @Test("Les remplacements partagent les muscles principaux")
    func candidatesShareMuscles() {
        let candidates = SubstitutionFinder.candidates(for: bench, in: catalog)
        #expect(!candidates.isEmpty)
        #expect(!candidates.contains { $0.exercise.id == squat.id })
        #expect(!candidates.contains { $0.exercise.id == bench.id })
    }

    @Test("Le même mouvement polyarticulaire passe devant l'isolation")
    func compoundRanksBeforeIsolation() {
        let candidates = SubstitutionFinder.candidates(for: bench, in: catalog)
        let flyIndex = candidates.firstIndex { $0.exercise.id == cableFly.id }
        let pressIndex = candidates.firstIndex { $0.exercise.id == dumbbellPress.id }
        #expect(pressIndex! < flyIndex!)
    }

    @Test("L'inventaire du lieu écarte le matériel absent")
    func inventoryRemovesUnavailableEquipment() {
        let travel = EquipmentInventory(items: [EquipmentAvailability(equipmentId: "bands")])
        let candidates = SubstitutionFinder.candidates(for: bench, in: catalog, inventory: travel)
        #expect(candidates.map(\.exercise.id) == [pushup.id])
    }

    @Test("Chaque proposition porte ses raisons")
    func candidatesCarryReasons() {
        let candidates = SubstitutionFinder.candidates(for: bench, in: catalog)
        #expect(candidates.allSatisfy { !$0.reasons.isEmpty })
        let top = candidates[0]
        #expect(top.reasons.contains { if case .sharedPrimaryMuscles = $0 { return true } else { return false } })
        #expect(top.reasons.allSatisfy { !$0.explanation.isEmpty })
    }

    @Test("Le classement est déterministe")
    func rankingIsDeterministic() {
        let first = SubstitutionFinder.candidates(for: bench, in: catalog)
        let second = SubstitutionFinder.candidates(for: bench, in: catalog.reversed())
        #expect(first.map(\.exercise.id) == second.map(\.exercise.id))
    }

    @Test("Un exercice sans muscle principal ne propose rien")
    func withoutPrimaryMusclesNothingIsProposed() {
        let unknown = CatalogExercise(id: "x", name: "X", nameFr: "X")
        #expect(SubstitutionFinder.candidates(for: unknown, in: catalog).isEmpty)
    }
}

@Suite("Génération selon le lieu")
struct GeneratorInventoryTests {
    private func makeInput(inventory: EquipmentInventory?) -> GeneratorInput {
        GeneratorInput(
            goal: .hypertrophy,
            experience: .intermediate,
            daysPerWeek: 3,
            sessionMinutes: 60,
            equipment: .fullGym,
            splitPreference: .fullBody,
            priorityMuscles: [],
            avoidAreas: [],
            inventory: inventory
        )
    }

    @Test("Sans inventaire, la génération est inchangée")
    func withoutInventoryNothingChanges() throws {
        let catalog = try ExerciseCatalog.load()
        let draft = try RuleBasedGenerator(catalog: catalog).generate(makeInput(inventory: nil))
        #expect(!draft.sessions.isEmpty)
        #expect(draft.sessions.allSatisfy { !$0.exercises.isEmpty })
    }

    @Test("Un lieu sans barre ne propose aucun exercice à la barre")
    func inventoryExcludesMissingEquipment() throws {
        let catalog = try ExerciseCatalog.load()
        let inventory = EquipmentInventory(items: [
            EquipmentAvailability(equipmentId: "dumbbell"),
            EquipmentAvailability(equipmentId: "bands"),
        ])
        let draft = try RuleBasedGenerator(catalog: catalog).generate(makeInput(inventory: inventory))

        let used = draft.sessions
            .flatMap(\.exercises)
            .compactMap { catalog.exercise(id: $0.exerciseId)?.equipment }
        #expect(!used.isEmpty)
        #expect(!used.contains("barbell"))
        #expect(!used.contains("machine"))
        // Le poids du corps reste toujours disponible.
        #expect(used.allSatisfy { ["dumbbell", "bands", "body only"].contains($0) })
    }

    @Test("Un inventaire vide ne restreint rien")
    func emptyInventoryDoesNotRestrict() throws {
        let catalog = try ExerciseCatalog.load()
        let generator = RuleBasedGenerator(catalog: catalog)
        let free = try generator.generate(makeInput(inventory: nil))
        let empty = try generator.generate(makeInput(inventory: EquipmentInventory()))
        #expect(free.sessions.flatMap(\.exercises).map(\.exerciseId) == empty.sessions.flatMap(\.exercises).map(\.exerciseId))
    }
}
