import Foundation

/// Strategie de fusion appliquee a une entite lorsqu'une meme donnee existe
/// en deux versions (import, synchronisation multi-appareils). Les regles
/// sont documentees ici, en un seul endroit, afin qu'aucune vue ni service
/// ne reinvente sa propre politique.
public enum MergeStrategy: String, Codable, CaseIterable, Sendable {
    /// Historique termine : immuable, fusion par UUID, la premiere version
    /// connue est conservee telle quelle.
    case immutableByIdentifier
    /// Record : maximum des performances comparables, puis date la plus recente.
    case maximumThenNewest
    /// Programme, planning : derniere modification gagne, conflit signale.
    case lastWriteWinsWithConflictFlag
    /// Seance active : un seul proprietaire d'edition a la fois.
    case singleOwner
    /// Reglages : derniere modification par cle.
    case lastWriteWinsPerKey
    /// Mesures corporelles : fusion par UUID uniquement, jamais par valeur
    /// ni par date seule (deux mesures peuvent legitimement coexister).
    case identifierOnly
}

/// Resultat d'une fusion de deux versions d'une meme entite.
public enum MergeOutcome<Value: Equatable>: Equatable {
    case keepLocal(Value)
    case takeRemote(Value)
    case merged(Value)
    /// Les deux versions sont conservees : l'utilisateur doit trancher.
    case conflict(local: Value, remote: Value)
}

/// Metadonnees minimales necessaires a une fusion deterministe.
public struct SyncMetadata: Codable, Equatable, Hashable, Sendable {
    public var identifier: UUID
    public var createdAt: Date
    public var updatedAt: Date
    /// Suppression logique : une suppression hors ligne doit pouvoir se
    /// propager. `nil` signifie « vivant ».
    public var deletedAt: Date?
    /// Version du schema d'enregistrement, pour refuser proprement une
    /// donnee ecrite par une version plus recente de l'app.
    public var schemaVersion: Int

    public init(
        identifier: UUID,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil,
        schemaVersion: Int = SyncMetadata.currentSchemaVersion
    ) {
        self.identifier = identifier
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.schemaVersion = schemaVersion
    }

    public static let currentSchemaVersion = 3

    public var isDeleted: Bool { deletedAt != nil }
}

public enum MergePolicy {
    /// Duree pendant laquelle un tombstone est conserve avant purge, afin
    /// qu'un appareil longtemps hors ligne recoive quand meme la suppression.
    public static let tombstoneRetention: TimeInterval = 60 * 60 * 24 * 90

    /// Fusion generique fondee sur les metadonnees, avant toute regle
    /// specifique au type. Une suppression ne gagne que si elle est plus
    /// recente que la modification concurrente.
    public static func resolve(
        strategy: MergeStrategy,
        local: SyncMetadata,
        remote: SyncMetadata
    ) -> MergeOutcome<SyncMetadata> {
        precondition(local.identifier == remote.identifier, "fusion de deux entites differentes")

        switch (local.deletedAt, remote.deletedAt) {
        case (let localDeleted?, let remoteDeleted?):
            return localDeleted >= remoteDeleted ? .keepLocal(local) : .takeRemote(remote)
        case (let localDeleted?, nil):
            // Suppression locale contre modification distante : la plus
            // recente gagne ; a egalite on conserve la donnee vivante.
            return localDeleted > remote.updatedAt ? .keepLocal(local) : .takeRemote(remote)
        case (nil, let remoteDeleted?):
            return remoteDeleted > local.updatedAt ? .takeRemote(remote) : .keepLocal(local)
        case (nil, nil):
            break
        }

        switch strategy {
        case .immutableByIdentifier:
            return .keepLocal(local)
        case .identifierOnly:
            return local.updatedAt >= remote.updatedAt ? .keepLocal(local) : .takeRemote(remote)
        case .maximumThenNewest, .lastWriteWinsPerKey:
            return local.updatedAt >= remote.updatedAt ? .keepLocal(local) : .takeRemote(remote)
        case .singleOwner:
            return local.updatedAt >= remote.updatedAt ? .keepLocal(local) : .takeRemote(remote)
        case .lastWriteWinsWithConflictFlag:
            if local.updatedAt == remote.updatedAt { return .keepLocal(local) }
            // Deux modifications concurrentes distinctes depuis le meme
            // ancetre : on ne supprime jamais silencieusement une version.
            return .conflict(local: local, remote: remote)
        }
    }

    /// Fusion nil-safe de deux maxima (records).
    public static func maximum<T: Comparable>(_ lhs: T?, _ rhs: T?) -> T? {
        switch (lhs, rhs) {
        case (nil, nil): return nil
        case (let value?, nil), (nil, let value?): return value
        case (let lhs?, let rhs?): return Swift.max(lhs, rhs)
        }
    }

    /// Un tombstone peut-il etre purge a cette date ?
    public static func canPurge(_ metadata: SyncMetadata, now: Date) -> Bool {
        canPurge(deletedAt: metadata.deletedAt, now: now)
    }

    /// Meme regle, pour un appelant qui n'a que la date de suppression sous
    /// la main — typiquement une entite persistee. Fabriquer une
    /// `SyncMetadata` factice juste pour poser la question reviendrait a
    /// inventer un `createdAt` qui n'existe pas.
    public static func canPurge(deletedAt: Date?, now: Date) -> Bool {
        guard let deletedAt else { return false }
        return now.timeIntervalSince(deletedAt) > tombstoneRetention
    }
}
