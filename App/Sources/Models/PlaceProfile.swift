import Foundation
import SwiftData
import MuscuEngine

/// Lieu d'entrainement et son inventaire.
///
/// L'inventaire est encode en JSON plutot que modelise en relation : c'est
/// une LISTE DE VALEURS editee en bloc, jamais interrogee independamment du
/// lieu. La meme approche est deja utilisee pour les cibles de volume d'une
/// semaine de plan.
@Model
final class PlaceProfile {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = ""
    var kindRaw: String = PlaceKind.gym.rawValue
    /// `[EquipmentAvailability]` encode. Vide = inventaire non renseigne,
    /// ce qui n'interdit aucun exercice.
    var inventoryData: Data?
    /// Lieu propose par defaut lors de la planification.
    var isDefault: Bool = false
    var notes: String = ""

    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        kindRaw: String = PlaceKind.gym.rawValue,
        inventoryData: Data? = nil,
        isDefault: Bool = false,
        notes: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.kindRaw = kindRaw
        self.inventoryData = inventoryData
        self.isDefault = isDefault
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

extension PlaceProfile {
    var kind: PlaceKind {
        get { PlaceKind(rawValue: kindRaw) ?? .custom }
        set { kindRaw = newValue.rawValue }
    }

    var inventory: EquipmentInventory {
        get {
            guard let inventoryData,
                  let items = try? JSONDecoder().decode([EquipmentAvailability].self, from: inventoryData) else {
                return EquipmentInventory()
            }
            return EquipmentInventory(items: items)
        }
        set { inventoryData = try? JSONEncoder().encode(newValue.items) }
    }

    var syncMetadata: SyncMetadata {
        SyncMetadata(identifier: id, createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt)
    }

    var displayKind: String {
        switch kind {
        case .home: return String(localized: "Domicile")
        case .gym: return String(localized: "Salle")
        case .travel: return String(localized: "Voyage")
        case .custom: return String(localized: "Personnalisé")
        }
    }
}
