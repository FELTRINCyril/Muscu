import Foundation
import Testing
@testable import MuscuEngine

private let bench = CatalogExercise(
    id: "bench", name: "Barbell Bench Press", nameFr: "Développé couché à la barre",
    force: "push", level: "intermediate", mechanic: "compound", equipment: "barbell",
    primaryMuscles: ["chest"], secondaryMuscles: ["triceps"]
)
private let inclineBench = CatalogExercise(
    id: "incline", name: "Incline Bench Press", nameFr: "Développé incliné",
    force: "push", level: "intermediate", mechanic: "compound", equipment: "barbell",
    primaryMuscles: ["chest"]
)
private let curl = CatalogExercise(
    id: "curl", name: "Dumbbell Curl", nameFr: "Curl haltères",
    force: "pull", level: "beginner", mechanic: "isolation", equipment: "dumbbell",
    primaryMuscles: ["biceps"]
)
private let squat = CatalogExercise(
    id: "squat", name: "Barbell Squat", nameFr: "Squat à la barre",
    force: "push", level: "expert", mechanic: "compound", equipment: "barbell",
    primaryMuscles: ["quadriceps"], category: "powerlifting"
)
private let catalog = [bench, inclineBench, curl, squat]

@Suite("Comparaison de texte")
struct TextMatchingTests {
    @Test("La normalisation retire accents, casse et ponctuation")
    func normalization() {
        #expect(TextMatching.normalize("Développé couché — à la barre !") == "developpe couche a la barre")
        #expect(TextMatching.normalize("  Curl   biceps ") == "curl biceps")
    }

    @Test("La distance compte une transposition pour une seule faute")
    func transpositionCostsOne() {
        #expect(TextMatching.editDistance("develop", "devleop") == 1)
        #expect(TextMatching.editDistance("curl", "curl") == 0)
        #expect(TextMatching.editDistance("", "abc") == 3)
    }

    @Test("Un mot court ne tolère aucune faute")
    func shortWordsAreStrict() {
        #expect(TextMatching.tolerance(forLength: 4) == 0)
        #expect(!TextMatching.matches(token: "bras", reference: "gras"))
    }

    @Test("Un mot long tolère deux fautes")
    func longWordsAreTolerant() {
        #expect(TextMatching.tolerance(forLength: 10) == 2)
        #expect(TextMatching.matches(token: "developpee", reference: "developpe"))
    }
}

@Suite("Recherche de la bibliothèque")
struct LibrarySearchTests {
    @Test("La recherche ignore les accents")
    func accentInsensitive() {
        let results = LibrarySearch.run(query: "developpe couche", catalog: catalog)
        #expect(results.first?.exercise.id == bench.id)
    }

    @Test("La recherche tolère une faute de frappe")
    func typoTolerant() {
        let results = LibrarySearch.run(query: "develope", catalog: catalog)
        #expect(results.contains { $0.exercise.id == bench.id })
        #expect(results.contains { $0.exercise.id == inclineBench.id })
        #expect(!results.contains { $0.exercise.id == curl.id })
    }

    @Test("La recherche fonctionne aussi en anglais")
    func englishQueryWorks() {
        let results = LibrarySearch.run(query: "bench press", catalog: catalog)
        #expect(results.contains { $0.exercise.id == bench.id })
        #expect(results.contains { $0.exercise.id == inclineBench.id })
    }

    @Test("Une correspondance exacte passe devant une correspondance partielle")
    func exactBeatsPartial() {
        let results = LibrarySearch.run(query: "developpe incline", catalog: catalog)
        #expect(results.first?.exercise.id == inclineBench.id)
    }

    @Test("Sans requête, l'ordre est alphabétique et stable")
    func emptyQueryIsAlphabetical() {
        let results = LibrarySearch.run(query: "   ", catalog: catalog)
        #expect(results.map(\.exercise.id) == ["curl", "bench", "incline", "squat"])
    }

    @Test("Les filtres se cumulent")
    func filtersCombine() {
        let filters = LibraryFilters(muscles: ["chest"], levels: ["intermediate"])
        let results = LibrarySearch.run(query: "", filters: filters, catalog: catalog)
        #expect(Set(results.map(\.exercise.id)) == ["bench", "incline"])
    }

    @Test("Le filtre favoris n'utilise que les favoris déclarés")
    func favoritesFilter() {
        let metadata = LibraryMetadata(favorites: ["curl"])
        let results = LibrarySearch.run(
            query: "",
            filters: LibraryFilters(favoritesOnly: true),
            catalog: catalog,
            metadata: metadata
        )
        #expect(results.map(\.exercise.id) == ["curl"])
    }

    @Test("Un favori remonte à pertinence égale")
    func favoriteBreaksTies() {
        let neutral = LibrarySearch.run(query: "developpe", catalog: catalog)
        let withFavorite = LibrarySearch.run(
            query: "developpe",
            catalog: catalog,
            metadata: LibraryMetadata(favorites: [inclineBench.id])
        )
        #expect(neutral.first?.exercise.id == bench.id)
        #expect(withFavorite.first?.exercise.id == inclineBench.id)
    }

    @Test("Les tags personnels filtrent la bibliothèque")
    func tagsFilter() {
        let metadata = LibraryMetadata(tags: ["squat": ["competition"]])
        let results = LibrarySearch.run(
            query: "",
            filters: LibraryFilters(tags: ["competition"]),
            catalog: catalog,
            metadata: metadata
        )
        #expect(results.map(\.exercise.id) == ["squat"])
    }

    @Test("Le filtre par lieu écarte le matériel absent")
    func inventoryFilter() {
        let inventory = EquipmentInventory(items: [EquipmentAvailability(equipmentId: "dumbbell")])
        let results = LibrarySearch.run(
            query: "",
            filters: LibraryFilters(inventory: inventory),
            catalog: catalog
        )
        #expect(results.map(\.exercise.id) == ["curl"])
    }

    @Test("Une requête sans correspondance ne renvoie rien")
    func noMatchReturnsNothing() {
        #expect(LibrarySearch.run(query: "natation papillon", catalog: catalog).isEmpty)
    }

    @Test("Le vrai catalogue reste cherchable avec une faute")
    func realCatalogToleratesTypo() throws {
        let catalog = try ExerciseCatalog.load()
        let results = LibrarySearch.run(query: "developpe couche", catalog: catalog.all)
        #expect(results.contains { $0.exercise.nameFr.contains("Développé couché") })
    }
}
