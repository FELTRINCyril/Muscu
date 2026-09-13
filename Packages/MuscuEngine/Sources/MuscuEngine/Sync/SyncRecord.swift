import Foundation

/// Type d'entite synchronisee.
///
/// Ce sont des RACINES D'AGREGAT : un programme voyage avec ses seances, ses
/// prescriptions et ses groupes ; une seance terminee avec ses series ; un
/// plan avec ses blocs, semaines et seances planifiees. Synchroniser les
/// enfants separement supposerait une granularite que l'application n'a pas :
/// elle edite ces objets comme des touts.
///
/// Chaque cas porte sa propre strategie de fusion : on ne resout pas un
/// conflit de programme comme un conflit d'historique.
public enum SyncEntityKind: String, Codable, CaseIterable, Sendable {
    case program
    case completedSession
    case activeWorkout
    case exerciseRecord
    case personalBest
    case customExercise
    case athleteProfile
    case bodyMeasurement
    case readinessEntry
    case healthWorkoutLink
    case trainingPlan
    case trainingGoal
    case adaptationEntry

    /// Strategie de fusion de ce type, documentee dans la roadmap :
    /// - historique termine : immuable, fusion par UUID ;
    /// - record : maximum des performances, puis date la plus recente ;
    /// - programme : derniere modification avec conflit VISIBLE ;
    /// - seance active : un seul proprietaire d'edition a la fois ;
    /// - mesures : fusion par UUID uniquement, jamais par valeur ni date.
    public var mergeStrategy: MergeStrategy {
        switch self {
        case .completedSession:
            return .immutableByIdentifier
        case .exerciseRecord, .personalBest:
            return .maximumThenNewest
        case .program, .trainingPlan:
            return .lastWriteWinsWithConflictFlag
        case .activeWorkout:
            return .singleOwner
        case .athleteProfile:
            return .lastWriteWinsPerKey
        case .bodyMeasurement, .readinessEntry, .healthWorkoutLink,
             .customExercise, .trainingGoal, .adaptationEntry:
            return .identifierOnly
        }
    }

    /// Une seance terminee ne se modifie jamais : une correction produit une
    /// revision, pas une reecriture. Utile pour refuser tot une mise a jour
    /// distante incoherente.
    public var isImmutableOnceCreated: Bool {
        mergeStrategy == .immutableByIdentifier
    }
}

/// Une entite prete a etre synchronisee : ses metadonnees et sa charge utile
/// encodee. Le moteur ne connait pas le contenu, seulement son empreinte.
public struct SyncRecord: Codable, Equatable, Sendable {
    public var kind: SyncEntityKind
    public var metadata: SyncMetadata
    /// DTO encode (JSON canonique).
    public var payload: Data

    public init(kind: SyncEntityKind, metadata: SyncMetadata, payload: Data) {
        self.kind = kind
        self.metadata = metadata
        self.payload = payload
    }

    public var identifier: UUID { metadata.identifier }
    public var isDeleted: Bool { metadata.isDeleted }

    /// Deux enregistrements sont identiques si leur contenu ET leur etat de
    /// suppression le sont. Sert a eviter d'ecrire pour rien.
    public func hasSameContent(as other: SyncRecord) -> Bool {
        payload == other.payload && metadata.deletedAt == other.metadata.deletedAt
    }
}

/// Ce que la reconciliation decide pour un enregistrement.
public enum SyncDecision: Equatable, Sendable {
    /// Rien a faire : contenu identique.
    case noChange
    /// Conserver la version locale et la renvoyer au serveur.
    case keepLocal
    /// Appliquer la version distante localement.
    case applyRemote
    /// Divergence non resolvable automatiquement : les DEUX versions sont
    /// conservees et l'utilisateur tranche. Rien n'est supprime.
    case conflict
}

/// Un conflit conserve, en attente de decision de l'utilisateur.
public struct SyncConflict: Equatable, Sendable {
    public var kind: SyncEntityKind
    public var identifier: UUID
    public var localUpdatedAt: Date
    public var remoteUpdatedAt: Date
    public var detectedAt: Date

    public init(
        kind: SyncEntityKind,
        identifier: UUID,
        localUpdatedAt: Date,
        remoteUpdatedAt: Date,
        detectedAt: Date
    ) {
        self.kind = kind
        self.identifier = identifier
        self.localUpdatedAt = localUpdatedAt
        self.remoteUpdatedAt = remoteUpdatedAt
        self.detectedAt = detectedAt
    }
}
