import Foundation
import SwiftData

/// Version courante du schema : modele v7 du produit. Ajoute au modele v6
/// des attributs FACULTATIFS preparant les inspirations open source (document
/// 10) : note d'effort, cardio et calories d'une seance, date de correction,
/// repos reellement pris avant une serie, lien de demonstration personnel,
/// redirection d'un exercice personnalise fusionne et identifiant d'echantillon
/// Sante d'une mesure importee.
///
/// Contrairement aux versions figees (`MuscuSchemaV1` a `MuscuSchemaV6`),
/// celle-ci pointe sur les modeles reellement utilises par l'application.
/// Une evolution future doit d'abord FIGER une copie de ces modeles
/// (`Scripts/freeze-schema.py`) avant de les modifier ici.
enum MuscuSchemaV7: VersionedSchema {
    static let versionIdentifier = Schema.Version(7, 0, 0)

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
typealias MuscuCurrentSchema = MuscuSchemaV7

enum MuscuMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            MuscuSchemaV1.self, MuscuSchemaV2.self, MuscuSchemaV3.self,
            MuscuSchemaV4.self, MuscuSchemaV5.self, MuscuSchemaV6.self,
            MuscuSchemaV7.self,
        ]
    }

    static var stages: [MigrationStage] {
        [
            migrateV1toV2, migrateV2toV3, migrateV3toV4, migrateV4toV5,
            migrateV5toV6, migrateV6toV7,
        ]
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

    /// V6 -> V7 : dix attributs FACULTATIFS (`CompletedSession`,
    /// `CompletedSet`, `ExerciseLibraryEntry`, `CustomExercise`,
    /// `BodyMeasurement`), tous `nil` par defaut. Que des ajouts : aucune
    /// donnee existante n'est relue ni reecrite, et `nil` signifie « non
    /// renseigne » — jamais zero.
    static let migrateV6toV7 = MigrationStage.lightweight(
        fromVersion: MuscuSchemaV6.self,
        toVersion: MuscuSchemaV7.self
    )
}
