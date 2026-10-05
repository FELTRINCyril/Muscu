import Foundation
import SwiftData
import MuscuEngine

/// Ce que l'utilisateur ajoute a un exercice du catalogue : favori et tags.
///
/// Le catalogue embarque reste en LECTURE SEULE — il est remplace a chaque
/// mise a jour de l'application. Les annotations personnelles vivent donc a
/// cote, reliees par l'identifiant d'exercice.
@Model
final class ExerciseLibraryEntry {
    @Attribute(.unique) var exerciseId: String = ""
    var isFavorite: Bool = false
    /// `[String]` encode, tags deja normalises (sans accent ni majuscule).
    var tagsData: Data?
    var lastUsedAt: Date?

    // MARK: - Champs v7 (facultatifs)

    /// Lien de demonstration choisi par l'utilisateur (video, article).
    /// nil = aucun. Le texte est conserve tel que saisi ; sa validation
    /// (schema http/https) se fait a la saisie et a l'import.
    var demoURL: String?

    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?

    init(
        exerciseId: String,
        isFavorite: Bool = false,
        tagsData: Data? = nil,
        lastUsedAt: Date? = nil,
        demoURL: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.exerciseId = exerciseId
        self.isFavorite = isFavorite
        self.tagsData = tagsData
        self.lastUsedAt = lastUsedAt
        self.demoURL = demoURL
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

extension ExerciseLibraryEntry {
    var tags: Set<String> {
        get {
            guard let tagsData,
                  let values = try? JSONDecoder().decode([String].self, from: tagsData) else { return [] }
            return Set(values)
        }
        set { tagsData = try? JSONEncoder().encode(newValue.sorted()) }
    }

    /// Une entree sans favori, sans tag, sans usage et sans lien de
    /// demonstration ne merite pas d'exister : la supprimer evite d'accumuler
    /// des lignes vides au fil des clics.
    var isEmpty: Bool {
        !isFavorite && tags.isEmpty && lastUsedAt == nil && (demoURL ?? "").isEmpty
    }
}

/// Collection personnalisee d'exercices (« Mes tractions », « Voyage »...).
@Model
final class ExerciseCollection {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = ""
    var notes: String = ""
    /// `[String]` encode : identifiants d'exercices, ordre conserve.
    var exerciseIdsData: Data?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        notes: String = "",
        exerciseIdsData: Data? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.exerciseIdsData = exerciseIdsData
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

extension ExerciseCollection {
    var exerciseIds: [String] {
        get {
            guard let exerciseIdsData,
                  let values = try? JSONDecoder().decode([String].self, from: exerciseIdsData) else { return [] }
            return values
        }
        set { exerciseIdsData = try? JSONEncoder().encode(newValue) }
    }

    var syncMetadata: SyncMetadata {
        SyncMetadata(identifier: id, createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt)
    }
}

/// Ligne d'import mise de cote parce qu'elle n'a pas pu etre interpretee.
///
/// Conserver la ligne brute est ce qui distingue une quarantaine d'un rejet :
/// l'utilisateur peut corriger son fichier en sachant exactement ce qui a
/// coince, ligne par ligne.
@Model
final class ImportQuarantineEntry {
    @Attribute(.unique) var id: UUID = UUID()
    /// Identifiant de l'import qui a produit cette ligne, pour les regrouper.
    var importIdentifier: UUID = UUID()
    var sourceName: String = ""
    var rowNumber: Int = 0
    var rawRow: String = ""
    var reason: String = ""
    var resolvedAt: Date?
    var createdAt: Date = Date()

    init(
        id: UUID = UUID(),
        importIdentifier: UUID,
        sourceName: String,
        rowNumber: Int,
        rawRow: String,
        reason: String,
        resolvedAt: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.importIdentifier = importIdentifier
        self.sourceName = sourceName
        self.rowNumber = rowNumber
        self.rawRow = rawRow
        self.reason = reason
        self.resolvedAt = resolvedAt
        self.createdAt = createdAt
    }
}
