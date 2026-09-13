import Foundation

/// Pourquoi une tentative de synchronisation a echoue. La distinction
/// compte : une erreur reseau se retente, un compte absent ne se retente pas
/// tout seul, et AUCUNE n'autorise a effacer des donnees locales.
public enum SyncFailureKind: String, Codable, CaseIterable, Sendable {
    /// Reseau indisponible ou instable.
    case network
    /// Quota iCloud depasse.
    case quotaExceeded
    /// Service indisponible cote Apple.
    case serviceUnavailable
    /// Aucun compte iCloud, ou compte change.
    case accountUnavailable
    /// Schema distant incompatible (app a mettre a jour).
    case schemaMismatch
    /// Le conteneur CloudKit n'est pas configure dans cette version de l'app.
    case notConfigured
    /// Erreur inattendue.
    case unknown

    /// Une nouvelle tentative automatique a-t-elle un sens ?
    public var isRetryable: Bool {
        switch self {
        case .network, .serviceUnavailable, .unknown: return true
        case .quotaExceeded, .accountUnavailable, .schemaMismatch, .notConfigured: return false
        }
    }

    /// Message affichable, sans jargon et sans donnee personnelle.
    public var userMessage: String {
        switch self {
        case .network:
            return "Connexion indisponible. Vos séances restent enregistrées sur cet appareil et seront envoyées plus tard."
        case .quotaExceeded:
            return "Votre espace iCloud est plein. Libérez de l'espace pour reprendre la synchronisation."
        case .serviceUnavailable:
            return "iCloud est momentanément indisponible. Nouvelle tentative automatique plus tard."
        case .accountUnavailable:
            return "Aucun compte iCloud actif. L'application continue de fonctionner entièrement hors ligne."
        case .schemaMismatch:
            return "Des données ont été écrites par une version plus récente de l'application. Mettez-la à jour pour les synchroniser."
        case .notConfigured:
            return "La synchronisation iCloud n'est pas encore configurée dans cette version."
        case .unknown:
            return "La synchronisation a échoué. Vos données locales sont intactes."
        }
    }
}

/// Une entree de la file d'attente persistante.
public struct SyncOutboxEntry: Codable, Equatable, Sendable {
    public var kind: SyncEntityKind
    public var identifier: UUID
    /// Date de la modification locale a pousser.
    public var updatedAt: Date
    public var attemptCount: Int
    /// Prochaine tentative autorisee. `nil` = des que possible.
    public var nextAttemptAt: Date?
    public var lastFailure: SyncFailureKind?

    public init(
        kind: SyncEntityKind,
        identifier: UUID,
        updatedAt: Date,
        attemptCount: Int = 0,
        nextAttemptAt: Date? = nil,
        lastFailure: SyncFailureKind? = nil
    ) {
        self.kind = kind
        self.identifier = identifier
        self.updatedAt = updatedAt
        self.attemptCount = attemptCount
        self.nextAttemptAt = nextAttemptAt
        self.lastFailure = lastFailure
    }

    public func isReady(at date: Date) -> Bool {
        guard let nextAttemptAt else { return true }
        return date >= nextAttemptAt
    }
}

/// File d'attente locale : ce qui reste a envoyer, et quand reessayer.
///
/// Elle ne perd jamais une modification : une entree n'est retiree que
/// lorsque l'envoi a reussi.
public struct SyncOutbox: Codable, Equatable, Sendable {
    public private(set) var entries: [UUID: SyncOutboxEntry]

    public init(entries: [UUID: SyncOutboxEntry] = [:]) {
        self.entries = entries
    }

    public var count: Int { entries.count }
    public var isEmpty: Bool { entries.isEmpty }

    /// Enregistre une modification locale. Une entree deja presente est
    /// REMPLACEE par la plus recente : inutile d'envoyer deux fois la meme
    /// entite, seule sa derniere version compte.
    public mutating func enqueue(kind: SyncEntityKind, identifier: UUID, updatedAt: Date) {
        if let existing = entries[identifier], existing.updatedAt >= updatedAt {
            return
        }
        // Le compteur de tentatives repart de zero : c'est une nouvelle
        // version a envoyer, pas la enieme tentative de l'ancienne.
        entries[identifier] = SyncOutboxEntry(kind: kind, identifier: identifier, updatedAt: updatedAt)
    }

    /// Retire une entree apres un envoi reussi, sauf si elle a ete modifiee
    /// entre-temps : dans ce cas la nouvelle version reste a envoyer.
    public mutating func acknowledge(identifier: UUID, pushedUpdatedAt: Date) {
        guard let existing = entries[identifier] else { return }
        guard existing.updatedAt <= pushedUpdatedAt else { return }
        entries.removeValue(forKey: identifier)
    }

    /// Enregistre un echec et programme la prochaine tentative.
    public mutating func registerFailure(
        identifier: UUID,
        failure: SyncFailureKind,
        now: Date
    ) {
        guard var entry = entries[identifier] else { return }
        entry.attemptCount += 1
        entry.lastFailure = failure
        entry.nextAttemptAt = failure.isRetryable
            ? now.addingTimeInterval(SyncBackoff.delay(forAttempt: entry.attemptCount))
            : nil
        entries[identifier] = entry
    }

    /// Entrees pretes a etre envoyees maintenant, les plus anciennes d'abord.
    public func ready(at date: Date) -> [SyncOutboxEntry] {
        entries.values
            .filter { $0.isReady(at: date) }
            .sorted { ($0.updatedAt, $0.identifier.uuidString) < ($1.updatedAt, $1.identifier.uuidString) }
    }
}

/// Attente exponentielle bornee entre deux tentatives.
public enum SyncBackoff {
    public static let base: TimeInterval = 5
    public static let maximum: TimeInterval = 60 * 30

    /// 5 s, 10 s, 20 s, 40 s... plafonnee a 30 minutes.
    public static func delay(forAttempt attempt: Int) -> TimeInterval {
        guard attempt > 0 else { return 0 }
        let exponent = min(attempt - 1, 16)
        return min(maximum, base * pow(2, Double(exponent)))
    }
}

/// Etat de synchronisation affichable. Aucune donnee metier ici : seulement
/// des dates, des compteurs et des codes d'erreur.
public struct SyncStatus: Equatable, Sendable {
    public var isEnabled: Bool
    public var lastSuccessAt: Date?
    public var lastAttemptAt: Date?
    public var pendingCount: Int
    public var conflictCount: Int
    public var lastFailure: SyncFailureKind?

    public init(
        isEnabled: Bool = false,
        lastSuccessAt: Date? = nil,
        lastAttemptAt: Date? = nil,
        pendingCount: Int = 0,
        conflictCount: Int = 0,
        lastFailure: SyncFailureKind? = nil
    ) {
        self.isEnabled = isEnabled
        self.lastSuccessAt = lastSuccessAt
        self.lastAttemptAt = lastAttemptAt
        self.pendingCount = pendingCount
        self.conflictCount = conflictCount
        self.lastFailure = lastFailure
    }

    /// Resume court affiche en tete d'ecran.
    public var summary: String {
        guard isEnabled else {
            return "Synchronisation désactivée. Toutes vos données restent sur cet appareil."
        }
        if let lastFailure, !lastFailure.isRetryable {
            return lastFailure.userMessage
        }
        if pendingCount > 0 {
            return "\(pendingCount) élément(s) en attente d'envoi."
        }
        guard lastSuccessAt != nil else {
            return "Aucune synchronisation effectuée pour l'instant."
        }
        return "À jour."
    }
}
