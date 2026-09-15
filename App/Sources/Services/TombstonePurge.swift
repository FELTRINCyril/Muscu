import Foundation
import SwiftData
import MuscuEngine

/// Purge différée des suppressions logiques.
///
/// Une entité synchronisée n'est pas effacée tout de suite : elle garde un
/// `deletedAt` (un « tombstone ») pour qu'un appareil resté longtemps hors
/// ligne reçoive quand même la suppression. `MergePolicy.tombstoneRetention`
/// fixe la durée de ce sursis.
///
/// Sans cette purge, ces marqueurs s'accumuleraient indéfiniment : le moteur
/// savait dire `canPurge`, mais personne ne l'appelait. C'est exactement ce
/// que la roadmap demandait par « prévoir une purge différée ».
///
/// Trois précautions :
/// 1. seules les entités **déjà supprimées** sont concernées — rien de
///    visible par l'utilisateur ne disparaît ;
/// 2. le sursis se compte depuis `deletedAt`, jamais depuis `updatedAt` ;
/// 3. la purge est **idempotente** et ne remonte jamais d'erreur bloquante :
///    elle ne doit pas empêcher l'application de démarrer.
@MainActor
enum TombstonePurge {
    /// Ce qui a réellement été purgé, par type. Utilisé par les tests et le
    /// journal de diagnostic.
    struct Report: Equatable {
        var countsByModel: [String: Int] = [:]
        var total: Int { countsByModel.values.reduce(0, +) }
    }

    @discardableResult
    static func run(context: ModelContext, now: Date = .now) throws -> Report {
        var report = Report()

        // Les enfants d'abord : supprimer un parent effacerait ses enfants en
        // cascade et fausserait le compte.
        purge(CompletedSet.self, in: context, now: now, into: &report)
        purge(PrescribedExercise.self, in: context, now: now, into: &report)
        purge(ExerciseGroup.self, in: context, now: now, into: &report)
        purge(ProgramSession.self, in: context, now: now, into: &report)
        purge(TrainingWeek.self, in: context, now: now, into: &report)
        purge(TrainingBlock.self, in: context, now: now, into: &report)
        purge(ScheduledWorkout.self, in: context, now: now, into: &report)

        purge(CompletedSession.self, in: context, now: now, into: &report)
        purge(Program.self, in: context, now: now, into: &report)
        purge(TrainingPlan.self, in: context, now: now, into: &report)
        purge(ExerciseRecord.self, in: context, now: now, into: &report)
        purge(PersonalBest.self, in: context, now: now, into: &report)
        purge(BodyMeasurement.self, in: context, now: now, into: &report)
        purge(ReadinessEntry.self, in: context, now: now, into: &report)
        purge(AdaptationEntry.self, in: context, now: now, into: &report)
        purge(TrainingGoal.self, in: context, now: now, into: &report)
        purge(CustomExercise.self, in: context, now: now, into: &report)
        purge(HealthWorkoutLink.self, in: context, now: now, into: &report)
        purge(PlaceProfile.self, in: context, now: now, into: &report)
        purge(PlanningSchedule.self, in: context, now: now, into: &report)
        purge(CalendarLink.self, in: context, now: now, into: &report)
        purge(SessionTemplate.self, in: context, now: now, into: &report)
        purge(ExerciseLibraryEntry.self, in: context, now: now, into: &report)
        purge(ExerciseCollection.self, in: context, now: now, into: &report)
        purge(AthleteProfile.self, in: context, now: now, into: &report)
        purge(ActiveWorkout.self, in: context, now: now, into: &report)

        // Les photos de progression portent un FICHIER : le retirer de la
        // base sans retirer l'image laisserait un fichier orphelin sur le
        // disque, invisible et impossible à supprimer depuis l'application.
        purgeProgressPhotos(in: context, now: now, into: &report)

        if report.total > 0 {
            try context.save()
            DiagnosticsCenter.record(
                .store,
                .info,
                code: "store.tombstones.purged",
                detail: "\(report.total)",
                now: now
            )
        }
        return report
    }

    /// Modèles réellement traités ci-dessus. Un test compare cette liste à
    /// l'ensemble des modèles du schéma qui portent une suppression logique :
    /// en ajouter un sans l'inscrire ici ferait échouer la suite, plutôt que
    /// de laisser ses tombstones s'accumuler en silence.
    static let coveredModelNames: Set<String> = [
        "CompletedSet", "PrescribedExercise", "ExerciseGroup", "ProgramSession",
        "TrainingWeek", "TrainingBlock", "ScheduledWorkout",
        "CompletedSession", "Program", "TrainingPlan",
        "ExerciseRecord", "PersonalBest",
        "BodyMeasurement", "ReadinessEntry", "AdaptationEntry", "TrainingGoal",
        "CustomExercise", "HealthWorkoutLink", "PlaceProfile",
        "PlanningSchedule", "CalendarLink", "SessionTemplate",
        "ExerciseLibraryEntry", "ExerciseCollection",
        "AthleteProfile", "ActiveWorkout", "ProgressPhoto",
    ]

    private static func purge<T: PersistentModel & SyncTombstoned>(
        _ type: T.Type,
        in context: ModelContext,
        now: Date,
        into report: inout Report
    ) {
        guard let items = try? context.fetch(FetchDescriptor<T>()) else { return }
        var purged = 0
        for item in items where canPurge(item.deletedAt, now: now) {
            context.delete(item)
            purged += 1
        }
        if purged > 0 { report.countsByModel["\(T.self)"] = purged }
    }

    private static func purgeProgressPhotos(
        in context: ModelContext,
        now: Date,
        into report: inout Report
    ) {
        guard let photos = try? context.fetch(FetchDescriptor<ProgressPhoto>()) else { return }
        var purged = 0
        for photo in photos where canPurge(photo.deletedAt, now: now) {
            PhotoStore.delete(assetName: photo.assetName)
            context.delete(photo)
            purged += 1
        }
        if purged > 0 { report.countsByModel["ProgressPhoto"] = purged }
    }

    private static func canPurge(_ deletedAt: Date?, now: Date) -> Bool {
        MergePolicy.canPurge(deletedAt: deletedAt, now: now)
    }
}

/// Marque les modèles qui portent une suppression logique. Déclarer la
/// conformité rend la liste ci-dessus vérifiable par le compilateur : un
/// modèle sans `deletedAt` ne peut pas y figurer par erreur.
protocol SyncTombstoned {
    var deletedAt: Date? { get }
}
