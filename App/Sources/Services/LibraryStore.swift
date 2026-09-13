import Foundation
import SwiftData
import MuscuEngine

/// Favoris, tags et collections d'exercices.
///
/// Le catalogue embarque est remplace a chaque mise a jour de
/// l'application : rien de personnel ne peut y etre ecrit. Ce service gere
/// donc les annotations qui vivent a cote, reliees par identifiant.
@MainActor
enum LibraryStore {
    // MARK: - Lecture

    static func entries(in context: ModelContext) -> [ExerciseLibraryEntry] {
        ((try? context.fetch(FetchDescriptor<ExerciseLibraryEntry>())) ?? [])
            .filter { $0.deletedAt == nil }
    }

    static func collections(in context: ModelContext) -> [ExerciseCollection] {
        ((try? context.fetch(FetchDescriptor<ExerciseCollection>(sortBy: [SortDescriptor(\.name)]))) ?? [])
            .filter { $0.deletedAt == nil }
    }

    static func metadata(in context: ModelContext) -> LibraryMetadata {
        var favorites: Set<String> = []
        var tags: [String: Set<String>] = [:]
        var lastUsed: [String: Date] = [:]

        for entry in entries(in: context) {
            if entry.isFavorite { favorites.insert(entry.exerciseId) }
            let entryTags = entry.tags
            if !entryTags.isEmpty { tags[entry.exerciseId] = entryTags }
            if let date = entry.lastUsedAt { lastUsed[entry.exerciseId] = date }
        }

        return LibraryMetadata(favorites: favorites, tags: tags, lastUsed: lastUsed)
    }

    /// Tous les tags connus, tries. Sert a proposer l'existant plutot qu'a
    /// laisser l'utilisateur ressaisir « pectoraux » de trois facons.
    static func allTags(in context: ModelContext) -> [String] {
        Array(entries(in: context).reduce(into: Set<String>()) { $0.formUnion($1.tags) }).sorted()
    }

    // MARK: - Écriture

    @discardableResult
    static func toggleFavorite(_ exerciseId: String, in context: ModelContext, now: Date = .now) -> Bool {
        let entry = ensureEntry(exerciseId, in: context, now: now)
        entry.isFavorite.toggle()
        entry.updatedAt = now
        let value = entry.isFavorite
        pruneIfEmpty(entry, in: context)
        _ = PersistenceSupport.save(context, action: "Mise à jour des favoris")
        return value
    }

    static func setTags(_ tags: Set<String>, for exerciseId: String, in context: ModelContext, now: Date = .now) {
        let normalized = Set(tags.map(TextMatching.normalize).filter { !$0.isEmpty })
        let entry = ensureEntry(exerciseId, in: context, now: now)
        entry.tags = normalized
        entry.updatedAt = now
        pruneIfEmpty(entry, in: context)
        _ = PersistenceSupport.save(context, action: "Mise à jour des tags")
    }

    static func markUsed(_ exerciseId: String, in context: ModelContext, now: Date = .now) {
        let entry = ensureEntry(exerciseId, in: context, now: now)
        entry.lastUsedAt = now
        entry.updatedAt = now
        _ = PersistenceSupport.save(context, action: "Mise à jour de la bibliothèque")
    }

    /// Derniers exercices utilises, du plus recent au plus ancien.
    static func recentlyUsed(in context: ModelContext, limit: Int = 10) -> [String] {
        entries(in: context)
            .compactMap { entry in entry.lastUsedAt.map { (entry.exerciseId, $0) } }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    // MARK: - Collections

    @discardableResult
    static func createCollection(named name: String, in context: ModelContext, now: Date = .now) -> ExerciseCollection {
        let collection = ExerciseCollection(name: name, createdAt: now, updatedAt: now)
        context.insert(collection)
        _ = PersistenceSupport.save(context, action: "Création de la collection")
        return collection
    }

    static func add(_ exerciseId: String, to collection: ExerciseCollection, in context: ModelContext, now: Date = .now) {
        guard !collection.exerciseIds.contains(exerciseId) else { return }
        collection.exerciseIds.append(exerciseId)
        collection.updatedAt = now
        _ = PersistenceSupport.save(context, action: "Ajout à la collection")
    }

    static func remove(_ exerciseId: String, from collection: ExerciseCollection, in context: ModelContext, now: Date = .now) {
        collection.exerciseIds.removeAll { $0 == exerciseId }
        collection.updatedAt = now
        _ = PersistenceSupport.save(context, action: "Retrait de la collection")
    }

    static func delete(_ collection: ExerciseCollection, in context: ModelContext, now: Date = .now) {
        collection.deletedAt = now
        collection.updatedAt = now
        _ = PersistenceSupport.save(context, action: "Suppression de la collection")
    }

    // MARK: - Interne

    private static func ensureEntry(_ exerciseId: String, in context: ModelContext, now: Date) -> ExerciseLibraryEntry {
        if let existing = entries(in: context).first(where: { $0.exerciseId == exerciseId }) { return existing }
        let entry = ExerciseLibraryEntry(exerciseId: exerciseId, createdAt: now, updatedAt: now)
        context.insert(entry)
        return entry
    }

    /// Une annotation vide n'a pas de raison d'exister : la retirer evite
    /// d'accumuler des lignes sans contenu au fil des clics.
    private static func pruneIfEmpty(_ entry: ExerciseLibraryEntry, in context: ModelContext) {
        guard entry.isEmpty else { return }
        context.delete(entry)
    }
}

/// Lieux d'entrainement et inventaires.
@MainActor
enum PlaceStore {
    static func places(in context: ModelContext) -> [PlaceProfile] {
        ((try? context.fetch(FetchDescriptor<PlaceProfile>(sortBy: [SortDescriptor(\.name)]))) ?? [])
            .filter { $0.deletedAt == nil }
    }

    static func place(id: UUID?, in context: ModelContext) -> PlaceProfile? {
        guard let id else { return nil }
        return places(in: context).first { $0.id == id }
    }

    static func defaultPlace(in context: ModelContext) -> PlaceProfile? {
        let all = places(in: context)
        return all.first { $0.isDefault } ?? all.first
    }

    @discardableResult
    static func create(name: String, kind: PlaceKind, in context: ModelContext, now: Date = .now) -> PlaceProfile {
        let place = PlaceProfile(name: name, kindRaw: kind.rawValue, createdAt: now, updatedAt: now)
        // Le premier lieu cree devient le lieu par defaut : sans cela,
        // l'utilisateur devrait faire un geste de plus pour rien.
        place.isDefault = places(in: context).isEmpty
        context.insert(place)
        _ = PersistenceSupport.save(context, action: "Création du lieu")
        return place
    }

    static func makeDefault(_ place: PlaceProfile, in context: ModelContext, now: Date = .now) {
        for other in places(in: context) where other.id != place.id && other.isDefault {
            other.isDefault = false
            other.updatedAt = now
        }
        place.isDefault = true
        place.updatedAt = now
        _ = PersistenceSupport.save(context, action: "Lieu par défaut")
    }

    static func delete(_ place: PlaceProfile, in context: ModelContext, now: Date = .now) {
        place.deletedAt = now
        place.updatedAt = now
        _ = PersistenceSupport.save(context, action: "Suppression du lieu")
    }

    /// Inventaire du lieu, ou inventaire vide si aucun lieu n'est designe.
    /// Un inventaire vide n'interdit rien : c'est le comportement le plus sur.
    static func inventory(for placeId: UUID?, in context: ModelContext) -> EquipmentInventory {
        place(id: placeId, in: context)?.inventory ?? EquipmentInventory()
    }
}
