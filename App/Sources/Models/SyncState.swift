import Foundation
import SwiftData
import MuscuEngine

/// Etat de synchronisation persiste : file d'attente, derniers envois,
/// conflits en attente et dernière erreur.
///
/// Une seule instance au plus. Rien de metier ici : uniquement des dates,
/// des identifiants et des codes d'erreur — ce fichier peut etre lu dans un
/// diagnostic sans exposer la moindre donnee d'entrainement.
@Model
final class SyncState {
    @Attribute(.unique) var id: UUID = UUID()
    var isEnabled: Bool = false
    var lastSuccessAt: Date?
    var lastAttemptAt: Date?
    var lastFailureRaw: String?
    /// `SyncOutbox` encode.
    var outboxData: Data?
    /// Dernière date poussée par entité, `[UUID: Date]` encode.
    var lastPushedData: Data?
    /// Conflits conservés, `[SyncConflict]` encode.
    var conflictsData: Data?
    /// Identifiant OPAQUE du compte iCloud utilisé lors de la dernière
    /// synchronisation réussie, pour détecter un changement de compte.
    /// Ce n'est jamais l'identifiant Apple lui-même.
    var accountFingerprint: String?

    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        isEnabled: Bool = false,
        lastSuccessAt: Date? = nil,
        lastAttemptAt: Date? = nil,
        lastFailureRaw: String? = nil,
        outboxData: Data? = nil,
        lastPushedData: Data? = nil,
        conflictsData: Data? = nil,
        accountFingerprint: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.lastSuccessAt = lastSuccessAt
        self.lastAttemptAt = lastAttemptAt
        self.lastFailureRaw = lastFailureRaw
        self.outboxData = outboxData
        self.lastPushedData = lastPushedData
        self.conflictsData = conflictsData
        self.accountFingerprint = accountFingerprint
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension SyncState {
    var outbox: SyncOutbox {
        get {
            guard let outboxData,
                  let decoded = try? JSONDecoder().decode(SyncOutbox.self, from: outboxData) else {
                return SyncOutbox()
            }
            return decoded
        }
        set { outboxData = try? JSONEncoder().encode(newValue) }
    }

    var lastPushed: [UUID: Date] {
        get {
            guard let lastPushedData,
                  let decoded = try? JSONDecoder().decode([UUID: Date].self, from: lastPushedData) else {
                return [:]
            }
            return decoded
        }
        set { lastPushedData = try? JSONEncoder().encode(newValue) }
    }

    var conflicts: [SyncConflict] {
        get {
            guard let conflictsData,
                  let decoded = try? JSONDecoder().decode([StoredConflict].self, from: conflictsData) else {
                return []
            }
            return decoded.map(\.conflict)
        }
        set { conflictsData = try? JSONEncoder().encode(newValue.map(StoredConflict.init)) }
    }

    var lastFailure: SyncFailureKind? {
        get { lastFailureRaw.flatMap(SyncFailureKind.init(rawValue:)) }
        set { lastFailureRaw = newValue?.rawValue }
    }

    var status: SyncStatus {
        SyncStatus(
            isEnabled: isEnabled,
            lastSuccessAt: lastSuccessAt,
            lastAttemptAt: lastAttemptAt,
            pendingCount: outbox.count,
            conflictCount: conflicts.count,
            lastFailure: lastFailure
        )
    }
}

/// `SyncConflict` n'est pas `Codable` cote moteur (il n'a pas a l'etre) :
/// cette enveloppe le rend persistable sans alourdir l'API publique.
private struct StoredConflict: Codable {
    var kindRaw: String
    var identifier: UUID
    var localUpdatedAt: Date
    var remoteUpdatedAt: Date
    var detectedAt: Date

    init(_ conflict: SyncConflict) {
        kindRaw = conflict.kind.rawValue
        identifier = conflict.identifier
        localUpdatedAt = conflict.localUpdatedAt
        remoteUpdatedAt = conflict.remoteUpdatedAt
        detectedAt = conflict.detectedAt
    }

    var conflict: SyncConflict {
        SyncConflict(
            kind: SyncEntityKind(rawValue: kindRaw) ?? .program,
            identifier: identifier,
            localUpdatedAt: localUpdatedAt,
            remoteUpdatedAt: remoteUpdatedAt,
            detectedAt: detectedAt
        )
    }
}
