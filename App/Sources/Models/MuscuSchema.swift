import Foundation
import SwiftData

/// Version courante du schema : modele v3 du produit (profil, mesures,
/// check-in, planning, groupes d'exercices, records types, lien HealthKit,
/// metadonnees de synchronisation).
///
/// Contrairement aux versions figees (`MuscuSchemaV1`, `MuscuSchemaV2`),
/// celle-ci pointe sur les modeles reellement utilises par l'application.
/// Une evolution future doit d'abord FIGER une copie de ces modeles dans une
/// nouvelle `VersionedSchema` avant de les modifier ici.
enum MuscuSchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)

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
        ]
    }
}

/// Schema courant de l'application. Un seul point a changer lors de l'ajout
/// d'une version ; les tests de migration s'appuient dessus.
typealias MuscuCurrentSchema = MuscuSchemaV3

enum MuscuMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [MuscuSchemaV1.self, MuscuSchemaV2.self, MuscuSchemaV3.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2, migrateV2toV3]
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
}
