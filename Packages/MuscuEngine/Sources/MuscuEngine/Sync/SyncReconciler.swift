import Foundation

/// Decide, pour chaque enregistrement distant, ce qu'il advient de la
/// version locale.
///
/// Entierement pur et deterministe : c'est ce qui permet de rejouer deux
/// appareils, dans n'importe quel ordre d'arrivee, dans un test.
///
/// Trois regles non negociables, issues de la roadmap :
/// 1. aucune version divergente n'est supprimee silencieusement ;
/// 2. une suppression ne gagne que si elle est plus recente que la
///    modification concurrente ;
/// 3. une seance terminee est immuable : elle ne peut qu'apparaitre, jamais
///    etre reecrite par un autre appareil.
public enum SyncReconciler {
    public static func decide(local: SyncRecord?, remote: SyncRecord) -> SyncDecision {
        guard let local else {
            // Inconnu localement : on applique, y compris un tombstone, pour
            // qu'une suppression faite ailleurs se propage vraiment.
            return .applyRemote
        }
        precondition(local.identifier == remote.identifier, "reconciliation de deux entites differentes")

        if local.hasSameContent(as: remote), local.metadata.updatedAt == remote.metadata.updatedAt {
            return .noChange
        }

        // Un enregistrement ecrit par une version plus recente du schema ne
        // doit pas etre applique a l'aveugle : on garde le local et on laisse
        // l'utilisateur mettre l'app a jour.
        if remote.metadata.schemaVersion > SyncMetadata.currentSchemaVersion {
            return .keepLocal
        }

        // L'historique termine est immuable : une fois cree, il ne change
        // plus, sauf suppression explicite plus recente.
        if local.kind.isImmutableOnceCreated, !remote.isDeleted, !local.isDeleted {
            return .noChange
        }

        // « Maximum des performances comparables, PUIS date la plus
        // recente » : la valeur passe avant la date. `MergePolicy` ne voit
        // que les metadonnees et ne peut donc pas appliquer cette regle
        // lui-meme ; c'est ici, ou le contenu est disponible, que la
        // comparaison a un sens.
        if local.kind.mergeStrategy == .maximumThenNewest,
           local.metadata.deletedAt == nil, remote.metadata.deletedAt == nil,
           let localValue = local.comparableValue,
           let remoteValue = remote.comparableValue,
           localValue != remoteValue {
            return remoteValue > localValue ? .applyRemote : .keepLocal
        }

        switch MergePolicy.resolve(
            strategy: local.kind.mergeStrategy,
            local: local.metadata,
            remote: remote.metadata
        ) {
        case .keepLocal:
            return local.hasSameContent(as: remote) ? .noChange : .keepLocal
        case .takeRemote:
            return .applyRemote
        case .merged:
            return .applyRemote
        case .conflict:
            // Contenus identiques ecrits au meme moment : ce n'est pas un
            // vrai conflit, inutile de deranger l'utilisateur.
            return local.hasSameContent(as: remote) ? .noChange : .conflict
        }
    }

    /// Applique une salve d'enregistrements distants a un etat local.
    ///
    /// Idempotent : rejouer la meme salve ne change rien la seconde fois.
    /// Insensible a l'ORDRE d'arrivee : deux salves permutees aboutissent au
    /// meme etat, propriete verifiee par les tests.
    public static func apply(
        remote: [SyncRecord],
        to local: [UUID: SyncRecord],
        now: Date
    ) -> (state: [UUID: SyncRecord], conflicts: [SyncConflict], applied: Int) {
        var state = local
        var conflicts: [SyncConflict] = []
        var applied = 0

        for record in remote.sorted(by: { $0.metadata.updatedAt < $1.metadata.updatedAt }) {
            let current = state[record.identifier]
            switch decide(local: current, remote: record) {
            case .noChange, .keepLocal:
                continue
            case .applyRemote:
                state[record.identifier] = record
                applied += 1
            case .conflict:
                guard let current else { continue }
                // Les deux versions sont conservees : l'etat local reste en
                // place et le conflit est signale. Rien n'est ecrase.
                conflicts.append(
                    SyncConflict(
                        kind: record.kind,
                        identifier: record.identifier,
                        localUpdatedAt: current.metadata.updatedAt,
                        remoteUpdatedAt: record.metadata.updatedAt,
                        detectedAt: now
                    )
                )
            }
        }
        return (state, conflicts, applied)
    }

    /// Enregistrements locaux a pousser : ceux dont la version distante
    /// connue est absente, plus ancienne, ou de contenu different.
    public static func pending(
        local: [UUID: SyncRecord],
        lastPushed: [UUID: Date]
    ) -> [SyncRecord] {
        local.values
            .filter { record in
                guard let pushedAt = lastPushed[record.identifier] else { return true }
                return record.metadata.updatedAt > pushedAt
            }
            .sorted { $0.metadata.updatedAt < $1.metadata.updatedAt }
    }
}
