import Foundation
import SwiftData
import MuscuEngine

/// Photo de progression : un ACTIF prive, stocke hors de la base.
///
/// Trois regles portees par ce modele et par `PhotoStore` :
/// 1. l'image vit sur le disque, pas dans le store : une base ne doit pas
///    gonfler de plusieurs mega-octets par cliche ;
/// 2. elle est exclue des exports par defaut — la roadmap l'exige ;
/// 3. elle n'entre dans aucune charge utile de synchronisation : sa
///    synchronisation demanderait un consentement separe, qui n'existe pas
///    encore.
@Model
final class ProgressPhoto {
    @Attribute(.unique) var id: UUID = UUID()
    /// Nom du fichier dans le dossier des photos. Jamais un chemin absolu :
    /// le conteneur de l'application change d'une installation a l'autre.
    var assetName: String = ""
    var takenAt: Date = Date()
    var note: String = ""
    /// Mesure corporelle a laquelle la photo se rattache, le cas echeant.
    var measurementId: UUID?
    /// Taille du fichier en octets, pour afficher l'espace occupe sans
    /// avoir a parcourir le disque.
    var byteCount: Int = 0

    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        assetName: String,
        takenAt: Date = Date(),
        note: String = "",
        measurementId: UUID? = nil,
        byteCount: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.assetName = assetName
        self.takenAt = takenAt
        self.note = note
        self.measurementId = measurementId
        self.byteCount = byteCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

extension ProgressPhoto {
    var syncMetadata: SyncMetadata {
        SyncMetadata(identifier: id, createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt)
    }
}
