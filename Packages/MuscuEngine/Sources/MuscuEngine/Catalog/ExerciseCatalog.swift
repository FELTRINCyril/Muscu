import Foundation

public enum ExerciseCatalogError: Error, Sendable {
    case resourceNotFound
}

/// Catalogue des exercices charge depuis les ressources du bundle du package.
public struct ExerciseCatalog: Sendable {
    public let all: [CatalogExercise]

    public init(all: [CatalogExercise]) {
        self.all = all
    }

    /// Charge le catalogue depuis exercises_fr.json embarque dans le bundle.
    public static func load() throws -> ExerciseCatalog {
        guard let url = Bundle.module.url(
            forResource: "exercises_fr",
            withExtension: "json",
            subdirectory: "CatalogData"
        ) else {
            throw ExerciseCatalogError.resourceNotFound
        }
        let data = try Data(contentsOf: url)
        let exercises = try JSONDecoder().decode([CatalogExercise].self, from: data)
        return ExerciseCatalog(all: exercises)
    }

    /// Retrouve un exercice par son identifiant. Index construit a la
    /// demande : les analyses de plan interrogent le catalogue en boucle.
    public func exercise(id: String) -> CatalogExercise? {
        indexById[id]
    }

    private var indexById: [String: CatalogExercise] {
        Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Recherche insensible a la casse et aux accents, sur nameFr et name.
    public func search(_ query: String) -> [CatalogExercise] {
        let needle = Self.normalize(query)
        guard !needle.isEmpty else { return all }
        return all.filter {
            Self.normalize($0.nameFr).contains(needle) || Self.normalize($0.name).contains(needle)
        }
    }

    /// Filtre par muscle principal, equipement et categorie. Un critere nil est ignore.
    public func filter(muscle: String?, equipment: String?, category: String?) -> [CatalogExercise] {
        all.filter { exercise in
            if let muscle, !exercise.primaryMuscles.contains(muscle) {
                return false
            }
            if let equipment, exercise.equipment != equipment {
                return false
            }
            if let category, exercise.category != category {
                return false
            }
            return true
        }
    }

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
    }
}
