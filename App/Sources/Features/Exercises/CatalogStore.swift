import Foundation
import MuscuEngine

// Charge le catalogue d'exercices une seule fois et l'expose en environnement
// pour tous les onglets qui en ont besoin (Exercices, Programmes, Seance).
@MainActor
@Observable
final class CatalogStore {
    let all: [CatalogExercise]

    let muscles: [String]
    let equipments: [String]
    let categories: [String]

    private let catalog: ExerciseCatalog

    init() {
        let loaded: ExerciseCatalog
        do {
            loaded = try ExerciseCatalog.load()
        } catch {
            // Ne peut pas realistiquement echouer (JSON embarque dans le bundle),
            // mais on degrade proprement plutot que de crasher l'app.
            print("CatalogStore: echec du chargement du catalogue: \(error)")
            loaded = ExerciseCatalog(all: [])
        }
        self.catalog = loaded
        self.all = loaded.all

        self.muscles = Self.distinctSorted(loaded.all.flatMap(\.primaryMuscles), label: FrenchLabels.muscle)
        self.equipments = Self.distinctSorted(loaded.all.compactMap(\.equipment), label: FrenchLabels.equipment)
        self.categories = Self.distinctSorted(loaded.all.map(\.category), label: FrenchLabels.category)
    }

    func search(_ query: String) -> [CatalogExercise] {
        catalog.search(query)
    }

    func filter(muscle: String?, equipment: String?, category: String?) -> [CatalogExercise] {
        catalog.filter(muscle: muscle, equipment: equipment, category: category)
    }

    private static func distinctSorted(_ keys: [String], label: (String) -> String) -> [String] {
        Array(Set(keys)).sorted { label($0).localizedCompare(label($1)) == .orderedAscending }
    }
}
