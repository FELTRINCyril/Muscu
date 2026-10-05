import Foundation

/// Metadonnees personnelles attachees a un exercice du catalogue : favori,
/// tags et collections. Le catalogue reste en lecture seule ; ce qui
/// appartient a l'utilisateur vit a cote.
public struct LibraryMetadata: Hashable, Sendable {
    public var favorites: Set<String>
    /// Tags par identifiant d'exercice, deja normalises.
    public var tags: [String: Set<String>]
    public var lastUsed: [String: Date]

    public init(
        favorites: Set<String> = [],
        tags: [String: Set<String>] = [:],
        lastUsed: [String: Date] = [:]
    ) {
        self.favorites = favorites
        self.tags = tags
        self.lastUsed = lastUsed
    }

    public func isFavorite(_ exerciseId: String) -> Bool { favorites.contains(exerciseId) }

    public func tags(for exerciseId: String) -> Set<String> { tags[exerciseId] ?? [] }
}

/// Filtres de la bibliotheque. Un ensemble vide signifie « pas de filtre » :
/// aucun critere ne masque du contenu tant qu'il n'est pas choisi.
public struct LibraryFilters: Hashable, Sendable {
    public var muscles: Set<String>
    public var equipment: Set<String>
    public var mechanics: Set<String>
    public var levels: Set<String>
    public var categories: Set<String>
    public var tags: Set<String>
    public var favoritesOnly: Bool
    /// Restreint aux exercices realisables avec l'inventaire d'un lieu.
    public var inventory: EquipmentInventory?

    public init(
        muscles: Set<String> = [],
        equipment: Set<String> = [],
        mechanics: Set<String> = [],
        levels: Set<String> = [],
        categories: Set<String> = [],
        tags: Set<String> = [],
        favoritesOnly: Bool = false,
        inventory: EquipmentInventory? = nil
    ) {
        self.muscles = muscles
        self.equipment = equipment
        self.mechanics = mechanics
        self.levels = levels
        self.categories = categories
        self.tags = tags
        self.favoritesOnly = favoritesOnly
        self.inventory = inventory
    }

    public var isEmpty: Bool {
        muscles.isEmpty && equipment.isEmpty && mechanics.isEmpty && levels.isEmpty
            && categories.isEmpty && tags.isEmpty && !favoritesOnly && inventory == nil
    }
}

public struct LibraryResult: Hashable, Sendable, Identifiable {
    public let exercise: CatalogExercise
    public let score: Int

    public var id: String { exercise.id }

    public init(exercise: CatalogExercise, score: Int) {
        self.exercise = exercise
        self.score = score
    }

    public static func == (lhs: LibraryResult, rhs: LibraryResult) -> Bool {
        lhs.exercise.id == rhs.exercise.id && lhs.score == rhs.score
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(exercise.id)
        hasher.combine(score)
    }
}

/// Recherche de la bibliotheque : tolerante aux accents ET aux fautes
/// simples, avec filtres cumulables.
public enum LibrarySearch {
    private enum Score {
        static let exact = 1000
        static let prefix = 800
        static let contains = 600
        static let allTokens = 500
        static let fuzzy = 400
        static let favoriteBonus = 30
    }

    public static func run(
        query: String,
        filters: LibraryFilters = LibraryFilters(),
        catalog: [CatalogExercise],
        metadata: LibraryMetadata = LibraryMetadata(),
        limit: Int = 200
    ) -> [LibraryResult] {
        let filtered = catalog.filter { passes($0, filters: filters, metadata: metadata) }
        let needle = TextMatching.normalize(query)

        guard !needle.isEmpty else {
            // Sans requete, l'ordre est alphabetique : un classement par
            // pertinence n'aurait aucun sens, et un ordre instable rendrait
            // la liste impossible a parcourir.
            return filtered
                .sorted { $0.nameFr.localizedCaseInsensitiveCompare($1.nameFr) == .orderedAscending }
                .prefix(limit)
                .map { LibraryResult(exercise: $0, score: 0) }
        }

        let queryTokens = needle.split(separator: " ").map(String.init)

        var results: [LibraryResult] = []
        for exercise in filtered {
            guard var score = score(exercise: exercise, needle: needle, queryTokens: queryTokens) else { continue }
            if metadata.isFavorite(exercise.id) { score += Score.favoriteBonus }
            results.append(LibraryResult(exercise: exercise, score: score))
        }

        return results
            .sorted { left, right in
                if left.score != right.score { return left.score > right.score }
                return left.exercise.nameFr.localizedCaseInsensitiveCompare(right.exercise.nameFr) == .orderedAscending
            }
            .prefix(limit)
            .map { $0 }
    }

    private static func score(exercise: CatalogExercise, needle: String, queryTokens: [String]) -> Int? {
        let haystacks = [TextMatching.normalize(exercise.nameFr), TextMatching.normalize(exercise.name)]

        var best: Int?
        for haystack in haystacks where !haystack.isEmpty {
            let candidate: Int?
            if haystack == needle {
                candidate = Score.exact
            } else if haystack.hasPrefix(needle) {
                candidate = Score.prefix
            } else if haystack.contains(needle) {
                candidate = Score.contains
            } else {
                let haystackTokens = haystack.split(separator: " ").map(String.init)
                if queryTokens.allSatisfy({ token in haystackTokens.contains { $0.hasPrefix(token) } }) {
                    candidate = Score.allTokens
                } else {
                    let distances = queryTokens.map { token in
                        haystackTokens.map { TextMatching.editDistance(token, $0) }.min() ?? Int.max
                    }
                    let tolerated = queryTokens.enumerated().allSatisfy { index, token in
                        distances[index] <= TextMatching.tolerance(forLength: token.count)
                    }
                    candidate = tolerated ? Score.fuzzy - (distances.reduce(0, +) * 20) : nil
                }
            }
            if let candidate, candidate > (best ?? Int.min) { best = candidate }
        }
        return best
    }

    private static func passes(
        _ exercise: CatalogExercise,
        filters: LibraryFilters,
        metadata: LibraryMetadata
    ) -> Bool {
        if filters.favoritesOnly, !metadata.isFavorite(exercise.id) { return false }
        if !filters.muscles.isEmpty, filters.muscles.isDisjoint(with: exercise.primaryMuscles) { return false }
        if !filters.equipment.isEmpty {
            guard let equipment = exercise.equipment, filters.equipment.contains(equipment) else { return false }
        }
        if !filters.mechanics.isEmpty {
            guard let mechanic = exercise.mechanic, filters.mechanics.contains(mechanic) else { return false }
        }
        if !filters.levels.isEmpty, !filters.levels.contains(exercise.level) { return false }
        if !filters.categories.isEmpty, !filters.categories.contains(exercise.category) { return false }
        if !filters.tags.isEmpty, filters.tags.isDisjoint(with: metadata.tags(for: exercise.id)) { return false }
        if let inventory = filters.inventory, !inventory.allows(equipment: exercise.equipment) { return false }
        return true
    }
}
