import Foundation

/// Journal de diagnostic local.
///
/// Trois regles, dictees par la roadmap : le journal est **borne** (il ne
/// grossit jamais indefiniment), **expurge** (aucune donnee de seance, de
/// sante, de cle ou d'identifiant personnel) et **desactivable**.
///
/// Rien ici ne part sur le reseau : l'export est un geste volontaire de
/// l'utilisateur, qui voit le texte avant de le partager.

// MARK: - Evenement

public enum DiagnosticCategory: String, Codable, Sendable, CaseIterable {
    case store
    case migration
    case sync
    case health
    case transfer
    case notifications
    case coach
    case widgets

    public var displayName: String {
        switch self {
        case .store: return "Stockage"
        case .migration: return "Migration"
        case .sync: return "Synchronisation"
        case .health: return "Santé"
        case .transfer: return "Import / export"
        case .notifications: return "Rappels"
        case .coach: return "Coach IA"
        case .widgets: return "Widgets et Watch"
        }
    }
}

public enum DiagnosticLevel: String, Codable, Sendable {
    case info
    case warning
    case failure

    public var symbol: String {
        switch self {
        case .info: return "·"
        case .warning: return "!"
        case .failure: return "×"
        }
    }
}

public struct DiagnosticEvent: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var date: Date
    public var category: DiagnosticCategory
    public var level: DiagnosticLevel
    /// Code STABLE, pensé pour être cherché : `store.open.failed`,
    /// `sync.push.retry`… Il ne dépend jamais d'une donnée utilisateur.
    public var code: String
    /// Détail court. Il traverse toujours `DiagnosticRedactor` : même un
    /// appelant distrait ne peut pas y laisser une adresse ou une clé.
    public var detail: String

    public init(
        id: UUID = UUID(),
        date: Date,
        category: DiagnosticCategory,
        level: DiagnosticLevel,
        code: String,
        detail: String = ""
    ) {
        self.id = id
        self.date = date
        self.category = category
        self.level = level
        self.code = code
        self.detail = DiagnosticRedactor.redact(detail)
    }
}

// MARK: - Expurgation

/// Filet de securite applique a CHAQUE detail journalise.
///
/// Il ne remplace pas la discipline de l'appelant (on ne journalise pas un
/// nom d'exercice), mais il garantit qu'une trace systeme recopiee telle
/// quelle ne fera pas fuiter une adresse, un chemin nominatif ou une cle.
public enum DiagnosticRedactor {
    public static let placeholder = "[masqué]"

    public static func redact(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        // Litteraux `Regex` et non `NSRegularExpression` : ils sont verifies
        // a la compilation, donc aucun `try!` n'est necessaire. Ils sont
        // declares ici et non en statiques parce que `Regex` n'est pas
        // `Sendable` ; le journal n'est pas un chemin chaud.
        let email = /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/
        // Chemin nominatif : seul le nom de compte est masque, le reste du
        // chemin reste utile au diagnostic.
        let homePath = /\/Users\/[^\/\s]+/
        // Jeton long melant lettres ET chiffres : cle d'API, jeton porteur,
        // identifiant d'appareil. Les UUID sont epargnes (voir `isUUIDLike`) :
        // ce sont nos propres identifiants internes, utiles au diagnostic.
        let token = /[A-Za-z0-9_\-]{20,}/
        // Suite de chiffres assez longue pour etre un numero de telephone ou
        // un identifiant de compte.
        let longNumber = /\b[0-9]{7,}\b/

        var result = text.replacing(email) { _ in placeholder }
        result = result.replacing(homePath) { _ in "/Users/\(placeholder)" }
        result = result.replacing(token) { match in
            let matched = String(match.output)
            guard !isUUIDLike(matched), containsLetterAndDigit(matched) else { return matched }
            return placeholder
        }
        result = result.replacing(longNumber) { _ in placeholder }
        return result
    }

    /// Un UUID a une forme fixe ; le reconnaitre evite de masquer nos
    /// propres identifiants d'entites.
    private static func isUUIDLike(_ text: String) -> Bool {
        UUID(uuidString: text) != nil
    }

    private static func containsLetterAndDigit(_ text: String) -> Bool {
        text.contains(where: \.isLetter) && text.contains(where: \.isNumber)
    }
}

// MARK: - Journal borne

public struct DiagnosticsBuffer: Codable, Equatable, Sendable {
    /// 200 lignes couvrent largement plusieurs sessions d'utilisation et
    /// pesent quelques dizaines de kilo-octets.
    public static let defaultCapacity = 200

    public private(set) var events: [DiagnosticEvent]
    public let capacity: Int

    public init(capacity: Int = DiagnosticsBuffer.defaultCapacity, events: [DiagnosticEvent] = []) {
        self.capacity = max(1, capacity)
        self.events = Array(events.prefix(self.capacity))
    }

    /// Les evenements sont ranges du plus recent au plus ancien : c'est
    /// l'ordre dans lequel on lit un journal quand quelque chose vient
    /// d'echouer.
    public mutating func append(_ event: DiagnosticEvent) {
        events.insert(event, at: 0)
        if events.count > capacity {
            events.removeSubrange(capacity...)
        }
    }

    public mutating func removeAll() {
        events.removeAll()
    }

    public var failureCount: Int { events.count(where: { $0.level == .failure }) }

    public func events(in category: DiagnosticCategory) -> [DiagnosticEvent] {
        events.filter { $0.category == category }
    }
}

// MARK: - Sante du store

/// Indicateurs de sante demandes par la roadmap : migration, synchronisation
/// en attente, derniere sauvegarde. Uniquement des compteurs et des dates.
public struct DiagnosticStoreHealth: Equatable, Sendable {
    public var schemaVersion: Int
    public var migrationSucceeded: Bool
    public var entityCounts: [String: Int]
    public var pendingSyncOperations: Int
    public var unresolvedConflicts: Int
    public var lastSyncSuccess: Date?
    public var lastBackup: Date?

    public init(
        schemaVersion: Int,
        migrationSucceeded: Bool,
        entityCounts: [String: Int] = [:],
        pendingSyncOperations: Int = 0,
        unresolvedConflicts: Int = 0,
        lastSyncSuccess: Date? = nil,
        lastBackup: Date? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.migrationSucceeded = migrationSucceeded
        self.entityCounts = entityCounts
        self.pendingSyncOperations = pendingSyncOperations
        self.unresolvedConflicts = unresolvedConflicts
        self.lastSyncSuccess = lastSyncSuccess
        self.lastBackup = lastBackup
    }
}

public struct DiagnosticEnvironment: Equatable, Sendable {
    public var applicationVersion: String
    public var buildNumber: String
    public var systemName: String
    public var systemVersion: String
    /// Modele GENERIQUE (`iPhone17,1`), jamais le nom que l'utilisateur a
    /// donne a son appareil — celui-ci contient souvent un prenom.
    public var deviceModel: String
    public var localeIdentifier: String

    public init(
        applicationVersion: String,
        buildNumber: String,
        systemName: String,
        systemVersion: String,
        deviceModel: String,
        localeIdentifier: String
    ) {
        self.applicationVersion = applicationVersion
        self.buildNumber = buildNumber
        self.systemName = systemName
        self.systemVersion = systemVersion
        self.deviceModel = deviceModel
        self.localeIdentifier = localeIdentifier
    }
}

// MARK: - Rapport

public enum DiagnosticReportBuilder {
    /// Texte exporte. Il ne contient QUE des versions, des compteurs, des
    /// dates et des codes d'erreur : c'est verifie par un test qui y injecte
    /// des donnees metier et verifie qu'aucune ne ressort.
    public static func text(
        environment: DiagnosticEnvironment,
        health: DiagnosticStoreHealth,
        events: [DiagnosticEvent],
        generatedAt: Date
    ) -> String {
        let stamp = ISO8601DateFormatter()
        stamp.formatOptions = [.withInternetDateTime]

        var lines: [String] = []
        lines.append("Diagnostic Muscu — \(stamp.string(from: generatedAt))")
        lines.append("")
        lines.append("## Application")
        lines.append("Version : \(environment.applicationVersion) (\(environment.buildNumber))")
        lines.append("Système : \(environment.systemName) \(environment.systemVersion)")
        lines.append("Appareil : \(environment.deviceModel)")
        lines.append("Région : \(environment.localeIdentifier)")
        lines.append("")
        lines.append("## Stockage")
        lines.append("Schéma : v\(health.schemaVersion)")
        lines.append("Migration : \(health.migrationSucceeded ? "réussie" : "ÉCHOUÉE")")
        for name in health.entityCounts.keys.sorted() {
            lines.append("\(name) : \(health.entityCounts[name] ?? 0)")
        }
        lines.append("Sauvegarde la plus récente : \(format(health.lastBackup, stamp))")
        lines.append("")
        lines.append("## Synchronisation")
        lines.append("Opérations en attente : \(health.pendingSyncOperations)")
        lines.append("Conflits non résolus : \(health.unresolvedConflicts)")
        lines.append("Dernier succès : \(format(health.lastSyncSuccess, stamp))")
        lines.append("")
        lines.append("## Journal (\(events.count))")
        if events.isEmpty {
            lines.append("Aucun événement enregistré.")
        } else {
            for event in events {
                let detail = event.detail.isEmpty ? "" : " — \(event.detail)"
                lines.append(
                    "\(stamp.string(from: event.date)) \(event.level.symbol) "
                        + "[\(event.category.rawValue)] \(event.code)\(detail)"
                )
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func format(_ date: Date?, _ formatter: ISO8601DateFormatter) -> String {
        guard let date else { return "aucune" }
        return formatter.string(from: date)
    }
}
