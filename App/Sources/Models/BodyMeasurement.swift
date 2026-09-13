import Foundation
import SwiftData
import MuscuEngine

/// Type de mesure corporelle. `custom` permet une mesure libre nommee par
/// l'utilisateur sans changer le schema.
enum BodyMeasurementKind: String, Codable, CaseIterable, Sendable {
    case bodyweight
    case waist
    case chest
    case arm
    case thigh
    case hips
    case calf
    case neck
    case bodyFatPercent
    case custom
}

/// Provenance d'une valeur : saisie manuelle, HealthKit ou import. Une
/// analyse doit pouvoir distinguer une donnee mesuree d'une donnee importee.
enum MeasurementSource: String, Codable, CaseIterable, Sendable {
    case manual
    case healthKit
    case imported
}

/// Une mesure corporelle datee. La valeur est stockee dans son unite
/// canonique (kg pour les masses, cm pour les longueurs, pourcentage pour
/// la masse grasse) ; l'unite d'affichage vient du profil.
@Model
final class BodyMeasurement {
    @Attribute(.unique) var id: UUID = UUID()
    var kindRaw: String = BodyMeasurementKind.bodyweight.rawValue
    /// Nom libre, utilise uniquement quand `kind == .custom`.
    var customName: String = ""
    var measuredAt: Date = Date()
    /// Valeur canonique : kg, cm ou % selon `kind`.
    var value: Double = 0
    var sourceRaw: String = MeasurementSource.manual.rawValue
    var notes: String = ""

    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        kindRaw: String = BodyMeasurementKind.bodyweight.rawValue,
        customName: String = "",
        measuredAt: Date = Date(),
        value: Double,
        sourceRaw: String = MeasurementSource.manual.rawValue,
        notes: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.kindRaw = kindRaw
        self.customName = customName
        self.measuredAt = measuredAt
        self.value = value
        self.sourceRaw = sourceRaw
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

extension BodyMeasurement {
    var kind: BodyMeasurementKind {
        get { BodyMeasurementKind(rawValue: kindRaw) ?? .custom }
        set { kindRaw = newValue.rawValue }
    }

    var source: MeasurementSource {
        get { MeasurementSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    /// Unite canonique dans laquelle `value` est stockee.
    var canonicalUnitSymbol: String {
        switch kind {
        case .bodyweight: return MassUnit.kilograms.symbol
        case .bodyFatPercent: return "%"
        case .custom: return ""
        case .waist, .chest, .arm, .thigh, .hips, .calf, .neck: return LengthUnit.centimeters.symbol
        }
    }

    var syncMetadata: SyncMetadata {
        SyncMetadata(identifier: id, createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt)
    }
}

/// Check-in de forme avant une seance. Toutes les valeurs sont facultatives :
/// un check-in partiel reste exploitable. Une douleur declaree ne produit
/// jamais de diagnostic, seulement un message prudent.
@Model
final class ReadinessEntry {
    @Attribute(.unique) var id: UUID = UUID()
    var recordedAt: Date = Date()
    /// Echelles 1...5, `nil` = non renseigne.
    var energy: Int?
    var sleepQuality: Int?
    var soreness: Int?
    var stress: Int?
    /// Intensite de douleur 0...10 et zone concernee, facultatives.
    var painIntensity: Int?
    var painArea: String = ""
    var notes: String = ""
    /// Seance a laquelle ce check-in se rapporte, quand il y en a une.
    var programSessionId: UUID?

    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        recordedAt: Date = Date(),
        energy: Int? = nil,
        sleepQuality: Int? = nil,
        soreness: Int? = nil,
        stress: Int? = nil,
        painIntensity: Int? = nil,
        painArea: String = "",
        notes: String = "",
        programSessionId: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.recordedAt = recordedAt
        self.energy = energy
        self.sleepQuality = sleepQuality
        self.soreness = soreness
        self.stress = stress
        self.painIntensity = painIntensity
        self.painArea = painArea
        self.notes = notes
        self.programSessionId = programSessionId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

extension ReadinessEntry {
    var syncMetadata: SyncMetadata {
        SyncMetadata(identifier: id, createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt)
    }

    /// Entree exploitable par le moteur d'adaptation : au moins une valeur.
    var hasAnyValue: Bool {
        energy != nil || sleepQuality != nil || soreness != nil || stress != nil || painIntensity != nil
    }
}

/// Lien stable entre une seance terminee et l'entrainement ecrit dans
/// HealthKit, afin de ne jamais creer deux entrainements pour la meme
/// seance (y compris quand elle arrive depuis l'Apple Watch).
@Model
final class HealthWorkoutLink {
    @Attribute(.unique) var id: UUID = UUID()
    /// Identifiant de la `CompletedSession` liee.
    var completedSessionId: UUID = UUID()
    /// `UUID` de l'`HKWorkout` correspondant, stocke en texte.
    var healthKitWorkoutIdentifier: String = ""
    var writtenAt: Date = Date()
    /// Origine de l'ecriture : "iphone" ou "watch".
    var sourceRaw: String = "iphone"

    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        completedSessionId: UUID,
        healthKitWorkoutIdentifier: String,
        writtenAt: Date = Date(),
        sourceRaw: String = "iphone",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.completedSessionId = completedSessionId
        self.healthKitWorkoutIdentifier = healthKitWorkoutIdentifier
        self.writtenAt = writtenAt
        self.sourceRaw = sourceRaw
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}
