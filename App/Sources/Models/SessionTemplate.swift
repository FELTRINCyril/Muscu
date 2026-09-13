import Foundation
import SwiftData
import MuscuEngine

/// Portee d'un modele : une seance seule ou un programme complet.
enum TemplateScope: String, Codable, CaseIterable, Sendable {
    case session
    case program

    var displayName: String {
        switch self {
        case .session: return String(localized: "Séance")
        case .program: return String(localized: "Programme")
        }
    }
}

/// Modele reutilisable de seance ou de programme.
///
/// Le contenu est stocke en JSON (le meme DTO que l'export v3) plutot qu'en
/// relations : un modele est un INSTANTANE. S'il pointait sur les entites
/// vivantes, renommer un exercice du programme d'origine reecrirait le
/// modele, et supprimer ce programme le viderait.
@Model
final class SessionTemplate {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = ""
    var scopeRaw: String = TemplateScope.session.rawValue
    var notes: String = ""
    /// Charge utile encodee. Vide = modele invalide, jamais applique.
    var payloadData: Data?
    /// Version du modele, incrementee a chaque enregistrement d'une nouvelle
    /// mouture sous le meme nom.
    var version: Int = 1
    var isArchived: Bool = false
    var isFavorite: Bool = false
    var lastUsedAt: Date?

    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        scopeRaw: String = TemplateScope.session.rawValue,
        notes: String = "",
        payloadData: Data? = nil,
        version: Int = 1,
        isArchived: Bool = false,
        isFavorite: Bool = false,
        lastUsedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.scopeRaw = scopeRaw
        self.notes = notes
        self.payloadData = payloadData
        self.version = version
        self.isArchived = isArchived
        self.isFavorite = isFavorite
        self.lastUsedAt = lastUsedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

extension SessionTemplate {
    var scope: TemplateScope {
        get { TemplateScope(rawValue: scopeRaw) ?? .session }
        set { scopeRaw = newValue.rawValue }
    }

    var syncMetadata: SyncMetadata {
        SyncMetadata(identifier: id, createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt)
    }
}
