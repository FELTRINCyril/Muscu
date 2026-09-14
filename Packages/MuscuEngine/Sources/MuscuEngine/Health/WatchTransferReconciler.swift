import Foundation

/// Decision prise a la reception d'une seance venue de la montre.
public enum WatchTransferDecision: Equatable, Sendable {
    case accept
    /// Deja recue : le transfert a ete rejoue.
    case duplicate
    /// Format inconnu : on ne devine pas ce qu'une version future voulait dire.
    case unsupportedVersion(Int)
    /// Seance vide : rien a enregistrer.
    case empty

    public var writesAnything: Bool { self == .accept }

    public var explanation: String {
        switch self {
        case .accept: return "Séance reçue de la montre."
        case .duplicate: return "Séance déjà reçue : rien n’a été ajouté."
        case .unsupportedVersion(let version): return "Format de transfert non pris en charge (version \(version))."
        case .empty: return "Séance vide : rien à enregistrer."
        }
    }
}

/// Decide si une seance recue de la montre doit etre ecrite.
///
/// La garantie du jalon tient ici : l'identifiant est genere a la montre et
/// ne change jamais, donc rejouer un transfert — apres une coupure, une
/// relance ou une reinstallation — ne cree jamais de doublon.
public enum WatchTransferReconciler {
    public static func decide(
        incomingId: UUID,
        version: Int,
        setCount: Int,
        currentVersion: Int,
        existingSessionIds: Set<UUID>
    ) -> WatchTransferDecision {
        guard version <= currentVersion else { return .unsupportedVersion(version) }
        guard !existingSessionIds.contains(incomingId) else { return .duplicate }
        guard setCount > 0 else { return .empty }
        return .accept
    }
}
