import Foundation
import MuscuEngine

/// Ce que la synchronisation attend d'un serveur, quel qu'il soit.
///
/// Abstraire le transport n'est pas de la gymnastique : c'est ce qui permet
/// de tester DEUX appareils, hors ligne puis en ligne, sans conteneur
/// CloudKit ni compte Apple.
protocol SyncTransport: Sendable {
    /// Le transport est-il utilisable ici et maintenant ?
    func availability() async -> SyncAvailability

    /// Enregistrements modifiés depuis le jeton fourni. Le jeton opaque
    /// permet de ne pas retélécharger tout l'historique à chaque fois.
    func fetchChanges(since token: String?) async throws -> SyncFetchResult

    /// Envoie des enregistrements. Renvoie ceux réellement acceptés.
    func push(_ records: [SyncRecord]) async throws -> [UUID]
}

/// Disponibilité du transport, avec la raison quand il est indisponible.
enum SyncAvailability: Equatable {
    case available(accountFingerprint: String?)
    case unavailable(SyncFailureKind)

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    var failure: SyncFailureKind? {
        if case .unavailable(let kind) = self { return kind }
        return nil
    }

    var accountFingerprint: String? {
        if case .available(let fingerprint) = self { return fingerprint }
        return nil
    }
}

struct SyncFetchResult: Equatable {
    var records: [SyncRecord]
    var token: String?

    init(records: [SyncRecord], token: String? = nil) {
        self.records = records
        self.token = token
    }
}

/// Erreur de transport traduite en cause compréhensible.
struct SyncTransportError: LocalizedError {
    let kind: SyncFailureKind

    var errorDescription: String? { kind.userMessage }
}

/// Transport de test : un « serveur » en mémoire, partagé par plusieurs
/// appareils simulés. Sert aux tests à deux stores exigés par la roadmap.
///
/// Il reproduit les comportements qui comptent : coupure réseau, ordre
/// d'arrivée quelconque, et rejeu de la même salve.
actor InMemorySyncTransport: SyncTransport {
    private var storage: [UUID: SyncRecord] = [:]
    private var log: [SyncRecord] = []
    private var isOffline = false
    private var forcedFailure: SyncFailureKind?
    private var fingerprint: String?

    init(accountFingerprint: String? = "compte-test") {
        self.fingerprint = accountFingerprint
    }

    func setOffline(_ offline: Bool) { isOffline = offline }
    func setForcedFailure(_ failure: SyncFailureKind?) { forcedFailure = failure }
    func setAccountFingerprint(_ value: String?) { fingerprint = value }

    var storedCount: Int { storage.count }
    func stored(_ identifier: UUID) -> SyncRecord? { storage[identifier] }

    func availability() async -> SyncAvailability {
        if let forcedFailure { return .unavailable(forcedFailure) }
        if isOffline { return .unavailable(.network) }
        guard let fingerprint else { return .unavailable(.accountUnavailable) }
        return .available(accountFingerprint: fingerprint)
    }

    func fetchChanges(since token: String?) async throws -> SyncFetchResult {
        if let forcedFailure { throw SyncTransportError(kind: forcedFailure) }
        if isOffline { throw SyncTransportError(kind: .network) }

        let start = token.flatMap(Int.init) ?? 0
        let slice = start < log.count ? Array(log[start...]) : []
        return SyncFetchResult(records: slice, token: String(log.count))
    }

    func push(_ records: [SyncRecord]) async throws -> [UUID] {
        if let forcedFailure { throw SyncTransportError(kind: forcedFailure) }
        if isOffline { throw SyncTransportError(kind: .network) }

        var accepted: [UUID] = []
        for record in records {
            // Le « serveur » applique la même règle que les clients : il ne
            // régresse jamais vers une version plus ancienne.
            if let existing = storage[record.identifier],
               existing.metadata.updatedAt > record.metadata.updatedAt {
                continue
            }
            storage[record.identifier] = record
            log.append(record)
            accepted.append(record.identifier)
        }
        return accepted
    }
}

/// Transport CloudKit. **Non validé** : il ne peut pas l'être sans conteneur
/// CloudKit ni compte développeur, qui sont des prérequis externes.
///
/// Tant que le conteneur n'est pas configuré, `availability()` renvoie
/// `notConfigured` et la synchronisation reste désactivée : l'application
/// fonctionne entièrement hors ligne, sans jamais prétendre synchroniser.
/// Les étapes exactes à réaliser sont décrites dans
/// `docs/decisions/0005-synchronisation-icloud.md`.
struct CloudKitSyncTransport: SyncTransport {
    /// Identifiant du conteneur, à renseigner une fois celui-ci créé dans le
    /// compte développeur. Vide = non configuré.
    static let containerIdentifier = ""

    var isConfigured: Bool { !Self.containerIdentifier.isEmpty }

    func availability() async -> SyncAvailability {
        guard isConfigured else { return .unavailable(.notConfigured) }
        // L'interrogation réelle du compte iCloud sera ajoutée en même temps
        // que le conteneur : écrire ce code sans pouvoir l'exécuter une seule
        // fois donnerait une fausse impression de fonctionnement.
        return .unavailable(.notConfigured)
    }

    func fetchChanges(since token: String?) async throws -> SyncFetchResult {
        throw SyncTransportError(kind: .notConfigured)
    }

    func push(_ records: [SyncRecord]) async throws -> [UUID] {
        throw SyncTransportError(kind: .notConfigured)
    }
}
