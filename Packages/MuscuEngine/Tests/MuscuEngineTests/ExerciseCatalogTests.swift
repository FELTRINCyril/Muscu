import Testing
@testable import MuscuEngine

@Suite
struct ExerciseCatalogTests {
    @Test
    func testLoadReturnsMoreThanEightHundredExercises() throws {
        let catalog = try ExerciseCatalog.load()
        #expect(catalog.all.count > 800)
    }

    @Test
    func testSearchWithoutAccentsFindsAccentedNameFr() throws {
        let catalog = try ExerciseCatalog.load()
        let results = catalog.search("developpe couche")
        #expect(!results.isEmpty)
        #expect(results.contains { $0.nameFr.contains("Développé couché") })
    }

    @Test
    func testSearchMatchesEnglishNameToo() throws {
        let catalog = try ExerciseCatalog.load()
        let results = catalog.search("bench press")
        #expect(!results.isEmpty)
        #expect(results.allSatisfy { $0.name.lowercased().contains("bench press") })
    }

    @Test
    func testFilterByMuscleOnlyReturnsExercisesWithThatPrimaryMuscle() throws {
        let catalog = try ExerciseCatalog.load()
        let results = catalog.filter(muscle: "chest", equipment: nil, category: nil)
        #expect(!results.isEmpty)
        #expect(results.allSatisfy { $0.primaryMuscles.contains("chest") })
    }

    @Test
    func testFilterByEquipmentAndCategory() throws {
        let catalog = try ExerciseCatalog.load()
        let results = catalog.filter(muscle: nil, equipment: "barbell", category: "strength")
        #expect(!results.isEmpty)
        #expect(results.allSatisfy { $0.equipment == "barbell" && $0.category == "strength" })
    }

    @Test
    func testFrenchLabelsMappings() {
        #expect(FrenchLabels.muscle("chest") == "Pectoraux")
        #expect(FrenchLabels.muscle("lats") == "Dorsaux")
        #expect(FrenchLabels.equipment("barbell") == "Barre")
        #expect(FrenchLabels.category("stretching") == "Étirements")
        #expect(FrenchLabels.level("beginner") == "Débutant")
    }

    @Test
    func testFrenchLabelsFallbackToCapitalizedUnknownKey() {
        #expect(FrenchLabels.muscle("unknown_muscle") == "Unknown_muscle")
    }
}
