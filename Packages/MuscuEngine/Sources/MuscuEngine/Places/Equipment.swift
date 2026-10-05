import Foundation

/// Nature d'un lieu d'entrainement. Le cas `custom` evite d'enfermer
/// l'utilisateur dans trois categories.
public enum PlaceKind: String, Codable, CaseIterable, Sendable {
    case home
    case gym
    case travel
    case custom
}

/// Disponibilite d'un materiel dans un lieu, avec ses charges praticables.
///
/// `equipmentId` reprend les cles du catalogue (`barbell`, `dumbbell`,
/// `body only`...) : filtrer un exercice ne demande alors aucune table de
/// correspondance supplementaire.
public struct EquipmentAvailability: Codable, Hashable, Sendable, Identifiable {
    public let equipmentId: String
    /// Charge la plus legere disponible. `nil` = non renseigne.
    public var minimumLoad: Double?
    public var maximumLoad: Double?
    /// Pas entre deux charges. `nil` ou <= 0 = pas de contrainte de pas.
    public var increment: Double?
    public var notes: String

    public var id: String { equipmentId }

    public init(
        equipmentId: String,
        minimumLoad: Double? = nil,
        maximumLoad: Double? = nil,
        increment: Double? = nil,
        notes: String = ""
    ) {
        self.equipmentId = equipmentId
        self.minimumLoad = minimumLoad
        self.maximumLoad = maximumLoad
        self.increment = increment
        self.notes = notes
    }

    public var isLoadConstrained: Bool {
        minimumLoad != nil || maximumLoad != nil || (increment ?? 0) > 0
    }
}

/// Inventaire d'un lieu.
public struct EquipmentInventory: Codable, Hashable, Sendable {
    public private(set) var items: [EquipmentAvailability]

    public init(items: [EquipmentAvailability] = []) {
        // Un materiel ne peut figurer qu'une fois : deux lignes
        // contradictoires rendraient l'arrondi de charge imprevisible.
        var seen: Set<String> = []
        self.items = items.filter { seen.insert($0.equipmentId).inserted }
    }

    public var equipmentIds: Set<String> { Set(items.map(\.equipmentId)) }

    public var isEmpty: Bool { items.isEmpty }

    public func availability(for equipmentId: String) -> EquipmentAvailability? {
        items.first { $0.equipmentId == equipmentId }
    }

    /// Un inventaire VIDE n'interdit rien : tant que l'utilisateur n'a rien
    /// declare, on ne masque aucun exercice. C'est le seul comportement qui
    /// ne perd pas de contenu par defaut.
    public func allows(equipment: String?) -> Bool {
        guard !isEmpty else { return true }
        guard let equipment, !equipment.isEmpty else { return true }
        // Le poids de corps reste toujours disponible : on ne peut pas
        // « ne pas avoir » son propre corps, meme en voyage.
        if ExerciseClassification.bodyweightEquipment.contains(equipment) { return true }
        return equipmentIds.contains(equipment)
    }

    /// Ramene une charge a ce que le lieu permet reellement : bornee par le
    /// minimum et le maximum, alignee sur le pas disponible.
    public func practicableLoad(_ load: Double, equipmentId: String) -> Double {
        guard let availability = availability(for: equipmentId), availability.isLoadConstrained else { return load }

        var value = load
        if let step = availability.increment, step > 0 {
            let base = availability.minimumLoad ?? 0
            let steps = ((value - base) / step).rounded()
            value = base + steps * step
        }
        if let minimum = availability.minimumLoad { value = max(value, minimum) }
        if let maximum = availability.maximumLoad { value = min(value, maximum) }
        return value
    }
}
