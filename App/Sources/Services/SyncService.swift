import Foundation
import SwiftData
import MuscuEngine

/// Synchronisation local-first.
///
/// Principes non négociables, repris de la roadmap :
/// - toute action valide est d'abord enregistrée **localement**, puis
///   envoyée ; l'application ne dépend jamais du réseau pour entraîner ;
/// - la file d'attente est **persistante** : une modification faite hors
///   ligne part plus tard, elle n'est jamais perdue ;
/// - aucune erreur — compte absent, quota, schéma — n'autorise à effacer des
///   données locales ;
/// - un conflit conserve les **deux** versions et devient visible.
@MainActor
@Observable
final class SyncService {
    private let modelContext: ModelContext
    private let transport: SyncTransport

    private(set) var status: SyncStatus
    private(set) var isSyncing = false

    /// Jeton opaque de la dernière lecture distante.
    private var changeToken: String?

    init(modelContext: ModelContext, transport: SyncTransport) {
        self.modelContext = modelContext
        self.transport = transport
        self.status = SyncService.state(in: modelContext).status
    }

    // MARK: - État

    /// État persisté, créé à la demande. Une seule instance.
    static func state(in context: ModelContext) -> SyncState {
        let descriptor = FetchDescriptor<SyncState>(sortBy: [SortDescriptor(\.createdAt)])
        if let existing = try? context.fetch(descriptor).first { return existing }
        let state = SyncState()
        context.insert(state)
        return state
    }

    var conflicts: [SyncConflict] {
        SyncService.state(in: modelContext).conflicts
    }

    /// Active ou désactive la synchronisation. Désactiver ne supprime
    /// jamais de données : l'application repasse simplement en local pur.
    func setEnabled(_ enabled: Bool) {
        let state = SyncService.state(in: modelContext)
        state.isEnabled = enabled
        state.updatedAt = .now
        // Miroir leger, lu a chaque sauvegarde locale : interroger l'etat
        // persiste sur ce chemin-la couterait une requete a chaque serie
        // validee.
        SyncOutboxFeeder.isEnabled = enabled
        persist(state)
    }

    // MARK: - Enregistrement des modifications locales

    /// Met une entité en file d'attente. À appeler après chaque écriture
    /// locale réussie.
    func enqueue(kind: SyncEntityKind, identifier: UUID, updatedAt: Date = .now) {
        let state = SyncService.state(in: modelContext)
        var outbox = state.outbox
        outbox.enqueue(kind: kind, identifier: identifier, updatedAt: updatedAt)
        state.outbox = outbox
        state.updatedAt = .now
        persist(state)
    }

    /// Reconstruit la file d'attente à partir de l'état local. Utile après
    /// un import, une restauration, ou la première activation.
    func enqueueEverything() throws {
        let state = SyncService.state(in: modelContext)
        let records = try SyncSerialization.localRecords(context: modelContext)
        var outbox = state.outbox
        for record in records.values {
            outbox.enqueue(kind: record.kind, identifier: record.identifier, updatedAt: record.metadata.updatedAt)
        }
        state.outbox = outbox
        state.updatedAt = .now
        persist(state)
    }

    // MARK: - Cycle de synchronisation

    @discardableResult
    func synchronize(now: Date = .now) async -> SyncStatus {
        let state = SyncService.state(in: modelContext)
        guard state.isEnabled else {
            status = state.status
            return status
        }
        guard !isSyncing else { return status }

        isSyncing = true
        defer { isSyncing = false }

        state.lastAttemptAt = now

        let availability = await transport.availability()
        guard availability.isAvailable else {
            // Indisponible : on note la cause et on s'arrête. Rien n'est
            // supprimé, la file reste intacte.
            state.lastFailure = availability.failure
            persist(state)
            status = state.status
            return status
        }

        // Changement de compte iCloud : on ne fusionne pas à l'aveugle les
        // données d'un autre compte avec celles de cet appareil.
        if let fingerprint = availability.accountFingerprint,
           let known = state.accountFingerprint,
           known != fingerprint {
            state.lastFailure = .accountUnavailable
            state.isEnabled = false
            persist(state)
            status = state.status
            return status
        }
        state.accountFingerprint = availability.accountFingerprint

        do {
            try await pull(state: state, now: now)
            try await push(state: state, now: now)
            state.lastSuccessAt = now
            state.lastFailure = nil
        } catch let error as SyncTransportError {
            state.lastFailure = error.kind
            DiagnosticsCenter.record(.sync, .failure, code: "sync.cycle.failed", detail: error.kind.rawValue)
        } catch {
            state.lastFailure = .unknown
            DiagnosticsCenter.record(.sync, code: "sync.cycle.failed", error: error)
        }

        persist(state)
        status = state.status
        return status
    }

    /// Récupère les changements distants et les applique localement.
    private func pull(state: SyncState, now: Date) async throws {
        let result = try await transport.fetchChanges(since: changeToken)
        guard !result.records.isEmpty else {
            changeToken = result.token ?? changeToken
            return
        }

        let local = try SyncSerialization.localRecords(context: modelContext)
        let outcome = SyncReconciler.apply(remote: result.records, to: local, now: now)

        // On n'écrit que ce qui a réellement changé.
        for record in result.records {
            guard let updated = outcome.state[record.identifier], updated == record else { continue }
            guard local[record.identifier] != record else { continue }
            try SyncSerialization.apply(record, into: modelContext)
        }

        if !outcome.conflicts.isEmpty {
            var conflicts = state.conflicts
            for conflict in outcome.conflicts where !conflicts.contains(where: { $0.identifier == conflict.identifier }) {
                conflicts.append(conflict)
            }
            state.conflicts = conflicts
        }

        changeToken = result.token ?? changeToken
        guard PersistenceSupport.save(modelContext, action: "Application des changements iCloud") else {
            throw SyncTransportError(kind: .unknown)
        }
        // Une fusion d'exercices faite sur l'autre appareil arrive comme une
        // redirection : les references locales sont reecrites ici.
        if result.records.contains(where: { $0.kind == .customExercise }) {
            ExerciseMergeService.applyPendingRedirects(in: modelContext, now: now)
        }
    }

    /// Envoie les modifications locales en attente.
    private func push(state: SyncState, now: Date) async throws {
        var outbox = state.outbox
        let ready = outbox.ready(at: now)
        guard !ready.isEmpty else { return }

        let local = try SyncSerialization.localRecords(context: modelContext)
        var records: [SyncRecord] = []
        for entry in ready {
            if let record = local[entry.identifier] {
                records.append(record)
            } else {
                // L'entité a disparu localement sans tombstone : on retire
                // l'entrée plutôt que de réessayer indéfiniment.
                outbox.acknowledge(identifier: entry.identifier, pushedUpdatedAt: entry.updatedAt)
            }
        }

        guard !records.isEmpty else {
            state.outbox = outbox
            return
        }

        do {
            let accepted = Set(try await transport.push(records))
            var lastPushed = state.lastPushed
            for record in records where accepted.contains(record.identifier) {
                outbox.acknowledge(identifier: record.identifier, pushedUpdatedAt: record.metadata.updatedAt)
                lastPushed[record.identifier] = record.metadata.updatedAt
            }
            state.lastPushed = lastPushed
            state.outbox = outbox
        } catch let error as SyncTransportError {
            for record in records {
                outbox.registerFailure(identifier: record.identifier, failure: error.kind, now: now)
            }
            state.outbox = outbox
            throw error
        }
    }

    // MARK: - Conflits

    /// L'utilisateur tranche un conflit en gardant la version locale : le
    /// conflit disparaît et la version locale sera renvoyée.
    func resolveKeepingLocal(_ conflict: SyncConflict) {
        let state = SyncService.state(in: modelContext)
        state.conflicts = state.conflicts.filter { $0.identifier != conflict.identifier }
        var outbox = state.outbox
        outbox.enqueue(kind: conflict.kind, identifier: conflict.identifier, updatedAt: .now)
        state.outbox = outbox
        persist(state)
    }

    /// L'utilisateur garde la version distante : elle sera réappliquée à la
    /// prochaine synchronisation.
    func resolveTakingRemote(_ conflict: SyncConflict) {
        let state = SyncService.state(in: modelContext)
        state.conflicts = state.conflicts.filter { $0.identifier != conflict.identifier }
        var lastPushed = state.lastPushed
        lastPushed.removeValue(forKey: conflict.identifier)
        state.lastPushed = lastPushed
        // On repart du début du journal distant pour recevoir à nouveau la
        // version que l'on avait mise de côté.
        changeToken = nil
        persist(state)
    }

    // MARK: - Diagnostic

    /// Diagnostic exportable : versions, compteurs, dates et codes d'erreur.
    /// **Aucune donnée d'entraînement, de santé ou d'identité.**
    func diagnosticReport(now: Date = .now) -> String {
        let state = SyncService.state(in: modelContext)
        let formatter = ISO8601DateFormatter()
        var lines = [
            "Diagnostic de synchronisation Muscu",
            "Généré le : \(formatter.string(from: now))",
            "Version du schéma : \(SyncMetadata.currentSchemaVersion)",
            "Synchronisation activée : \(state.isEnabled ? "oui" : "non")",
            "Dernière réussite : \(state.lastSuccessAt.map(formatter.string(from:)) ?? "aucune")",
            "Dernière tentative : \(state.lastAttemptAt.map(formatter.string(from:)) ?? "aucune")",
            "Éléments en attente : \(state.outbox.count)",
            "Conflits en attente : \(state.conflicts.count)",
            "Dernière erreur : \(state.lastFailure?.rawValue ?? "aucune")",
        ]
        let byKind = Dictionary(grouping: state.outbox.entries.values, by: \.kind)
            .mapValues(\.count)
            .sorted { $0.key.rawValue < $1.key.rawValue }
        for (kind, count) in byKind {
            lines.append("En attente · \(kind.rawValue) : \(count)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func persist(_ state: SyncState) {
        state.updatedAt = .now
        _ = PersistenceSupport.save(modelContext, action: "Mise à jour de la synchronisation")
        status = state.status
    }
}
