import Foundation
import SwiftData

/// Version courante du schema : modele v6 du produit. Ajoute au modele v5
/// les valeurs precedentes manquantes sur `AdaptationEntry`, sans lesquelles
/// deux adaptations acceptees — l'ajustement d'un intervalle et le changement
/// de variante apres plateau — ne pouvaient pas etre annulees.
///
/// Contrairement aux versions figees (`MuscuSchemaV1` a `MuscuSchemaV5`),
/// celle-ci pointe sur les modeles reellement utilises par l'application.
/// Une evolution future doit d'abord FIGER une copie de ces modeles
/// (`Scripts/freeze-schema.py`) avant de les modifier ici.
enum MuscuSchemaV6: VersionedSchema {
    static let versionIdentifier = Schema.Version(6, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Program.self,
            ProgramSession.self,
            PrescribedExercise.self,
            ExerciseGroup.self,
            CompletedSession.self,
            CompletedSet.self,
            ExerciseRecord.self,
            PersonalBest.self,
            CustomExercise.self,
            ActiveWorkout.self,
            AthleteProfile.self,
            BodyMeasurement.self,
            ReadinessEntry.self,
            HealthWorkoutLink.self,
            TrainingPlan.self,
            TrainingBlock.self,
            TrainingWeek.self,
            ScheduledWorkout.self,
            AdaptationEntry.self,
            TrainingGoal.self,
            SyncState.self,
            PlaceProfile.self,
            PlanningSchedule.self,
            NotificationRecord.self,
            CalendarLink.self,
            SessionTemplate.self,
            ExerciseLibraryEntry.self,
            ExerciseCollection.self,
            ImportQuarantineEntry.self,
            ProgressPhoto.self,
        ]
    }
}

/// Schema courant de l'application. Un seul point a changer lors de l'ajout
/// d'une version ; les tests de migration s'appuient dessus.
typealias MuscuCurrentSchema = MuscuSchemaV6

enum MuscuMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            MuscuSchemaV1.self, MuscuSchemaV2.self, MuscuSchemaV3.self,
            MuscuSchemaV4.self, MuscuSchemaV5.self, MuscuSchemaV6.self,
        ]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2, migrateV2toV3, migrateV3toV4, migrateV4toV5, migrateV5toV6]
    }

    /// V1 -> V2 : ajout des identifiants uniques, du typage de charge des
    /// series, des identifiants de programme sur l'historique et de l'etat
    /// d'execution persiste. Uniquement des ajouts a valeur par defaut.
    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: MuscuSchemaV1.self,
        toVersion: MuscuSchemaV2.self
    )

    /// V2 -> V3 : nouveaux modeles et attributs facultatifs. Aucune donnee
    /// n'est transformee ni supprimee, donc une migration legere suffit ; la
    /// normalisation des metadonnees est faite apres ouverture par
    /// `SchemaUpgrade`, qui peut echouer sans empecher l'ouverture du store.
    static let migrateV2toV3 = MigrationStage.lightweight(
        fromVersion: MuscuSchemaV2.self,
        toVersion: MuscuSchemaV3.self
    )

    /// V3 -> V4 : huit nouveaux modeles et quelques attributs facultatifs sur
    /// `CompletedSession` et `ScheduledWorkout`. Que des ajouts a valeur par
    /// defaut : aucune donnee existante n'est relue ni reecrite.
    static let migrateV3toV4 = MigrationStage.lightweight(
        fromVersion: MuscuSchemaV3.self,
        toVersion: MuscuSchemaV4.self
    )

    /// V4 -> V5 : le modele `ProgressPhoto` et deux attributs facultatifs sur
    /// `TrainingPlan`. Que des ajouts a valeur par defaut : aucune donnee
    /// existante n'est relue ni reecrite.
    static let migrateV4toV5 = MigrationStage.lightweight(
        fromVersion: MuscuSchemaV4.self,
        toVersion: MuscuSchemaV5.self
    )

    /// V5 -> V6 : trois attributs FACULTATIFS sur `AdaptationEntry`, qui
    /// permettent d'annuler un ajustement d'intervalle et un changement de
    /// variante. Que des ajouts a valeur par defaut : aucune donnee existante
    /// n'est relue ni reecrite, et une adaptation deja enregistree reste
    /// lisible — simplement non annulable, comme elle l'etait deja.
    static let migrateV5toV6 = MigrationStage.lightweight(
        fromVersion: MuscuSchemaV5.self,
        toVersion: MuscuSchemaV6.self
    )
}
