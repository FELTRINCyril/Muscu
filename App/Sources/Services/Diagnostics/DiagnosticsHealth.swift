import Foundation
import SwiftData
import MuscuEngine

/// Indicateurs de santé du store : migration, synchronisation en attente,
/// dernière sauvegarde.
///
/// Uniquement des versions, des compteurs et des dates. Aucun nom
/// d'exercice, de programme ni de mesure n'entre ici : c'est ce qui rend le
/// rapport partageable sans arbitrage.
@MainActor
enum DiagnosticsHealth {
    static func snapshot(context: ModelContext, migrationSucceeded: Bool) -> DiagnosticStoreHealth {
        var counts: [String: Int] = [:]
        counts["Séances terminées"] = count(of: CompletedSession.self, in: context)
        counts["Programmes"] = count(of: Program.self, in: context)
        counts["Exercices personnalisés"] = count(of: CustomExercise.self, in: context)
        counts["Mesures corporelles"] = count(of: BodyMeasurement.self, in: context)
        counts["Séances planifiées"] = count(of: ScheduledWorkout.self, in: context)

        let state = try? context.fetch(FetchDescriptor<SyncState>()).first

        return DiagnosticStoreHealth(
            schemaVersion: Int(MuscuCurrentSchema.versionIdentifier.major),
            migrationSucceeded: migrationSucceeded,
            entityCounts: counts,
            pendingSyncOperations: state?.outbox.count ?? 0,
            unresolvedConflicts: state?.conflicts.count ?? 0,
            lastSyncSuccess: state?.lastSuccessAt,
            lastBackup: lastBackupDate()
        )
    }

    /// Un compteur qui échoue ne doit pas empêcher le diagnostic : c'est
    /// justement quand le store va mal qu'on en a besoin. `-1` signale
    /// explicitement un comptage impossible plutôt que de mentir avec `0`.
    private static func count<T: PersistentModel>(of type: T.Type, in context: ModelContext) -> Int {
        (try? context.fetchCount(FetchDescriptor<T>())) ?? -1
    }

    private static func lastBackupDate() -> Date? {
        guard let latest = BackupService.existingBackups().first else { return nil }
        return try? latest.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}
