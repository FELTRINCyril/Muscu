import Foundation
import SwiftData

/// Quatrieme version du schema : au modele v3 s'ajoutent le planning
/// recurrent et ses rappels, les lieux et leur inventaire, les modeles de
/// seance, les annotations de bibliotheque, le lien vers l'application
/// Calendrier et la quarantaine d'import.
///
/// Types FIGES, comme les versions precedentes. Ces copies ne doivent JAMAIS
/// suivre l'evolution des modeles courants : une migration etagee a besoin
/// d'une description stable de l'etat d'ou elle part. Les valeurs brutes par
/// defaut sont ecrites en litteral pour la meme raison.
enum MuscuSchemaV4: VersionedSchema {
    static let versionIdentifier = Schema.Version(4, 0, 0)

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
        ]
    }

    @Model
    final class ActiveWorkout {
        @Attribute(.unique) var id: UUID = UUID()
        var startedAt: Date = Date()
        var programSessionId: UUID = UUID()
        var exerciseIndex: Int = 0
        var setIndex: Int = 0

        // Phase de la seance ("warmup" ou "running", cf. RunnerPhase dans
        // WorkoutState.swift). Champ optionnel-par-defaut : les ActiveWorkout
        // deja persistees avant l'ajout de l'echauffement n'etaient jamais en
        // phase d'echauffement, "running" est donc un defaut correct pour elles.
        var phaseRaw: String = "running"

        // Snapshot JSON (encodage de [RunExercise], cf. WorkoutState.swift) des
        // exercices de la seance en cours, tels que mutes en memoire par
        // addSet/removeSet/replaceExercise. Sans ce snapshot, un kill+resume de
        // l'app reconstruirait les exercices depuis la ProgramSession source et
        // perdrait ces mutations, desynchronisant exerciseIndex/setIndex (deja
        // persistes) du contenu reel de la seance. Champ optionnel : les
        // ActiveWorkout deja persistees avant son ajout se contentent de nil et
        // retombent sur la reconstruction depuis le programme (cf. `resume`).
        var runExercisesData: Data?
        var runtimeStateData: Data?

        // Snapshot du deroule (WorkoutPlan) et position exacte dans ce deroule
        // (WorkoutPosition), tels que la machine a etats du moteur les manipule.
        // Champs optionnels : une ActiveWorkout persistee avant leur ajout
        // retombe sur `runExercisesData` + `exerciseIndex`/`setIndex`.
        var planData: Data?
        var positionData: Data?

        // Metadonnees de synchronisation. Une seance en cours n'a qu'un seul
        // proprietaire d'edition a la fois : c'est la strategie de fusion
        // `singleOwner` qui tranche, sur la base de `updatedAt`.
        var updatedAt: Date = Date()
        var deletedAt: Date?

        @Relationship(deleteRule: .cascade, inverse: \CompletedSet.activeWorkout)
        var loggedSets: [CompletedSet] = []

        init(
            id: UUID = UUID(),
            startedAt: Date = Date(),
            programSessionId: UUID,
            exerciseIndex: Int = 0,
            setIndex: Int = 0,
            phaseRaw: String = "running",
            runExercisesData: Data? = nil,
            runtimeStateData: Data? = nil,
            planData: Data? = nil,
            positionData: Data? = nil,
            updatedAt: Date = Date(),
            deletedAt: Date? = nil,
            loggedSets: [CompletedSet] = []
        ) {
            self.id = id
            self.startedAt = startedAt
            self.programSessionId = programSessionId
            self.exerciseIndex = exerciseIndex
            self.setIndex = setIndex
            self.phaseRaw = phaseRaw
            self.runExercisesData = runExercisesData
            self.runtimeStateData = runtimeStateData
            self.planData = planData
            self.positionData = positionData
            self.updatedAt = updatedAt
            self.deletedAt = deletedAt
            self.loggedSets = loggedSets
        }
    }

    @Model
    final class AdaptationEntry {
        @Attribute(.unique) var id: UUID = UUID()
        var createdAt: Date = Date()
        var sourceRaw: String = "progression"
        var decisionRaw: String = "proposed"
        var decidedAt: Date?

        /// Prescription concernee, quand l'adaptation porte sur un exercice.
        var prescribedExerciseId: UUID?
        var exerciseId: String = ""
        var displayName: String = ""

        /// Resume lisible de la proposition, par exemple « 60 kg → 62,5 kg ».
        var summary: String = ""
        /// Facteurs ayant conduit a la proposition, un par ligne.
        var factors: [String] = []

        /// Valeurs avant/apres, pour pouvoir annuler exactement.
        var previousWeightKilograms: Double?
        var newWeightKilograms: Double?
        var previousRepsUpper: Int?
        var newRepsUpper: Int?
        var previousSets: Int?
        var newSets: Int?
        var previousPercentOneRepMax: Double?
        var newPercentOneRepMax: Double?

        var updatedAt: Date = Date()
        var deletedAt: Date?

        init(
            id: UUID = UUID(),
            createdAt: Date = Date(),
            sourceRaw: String = "progression",
            decisionRaw: String = "proposed",
            decidedAt: Date? = nil,
            prescribedExerciseId: UUID? = nil,
            exerciseId: String = "",
            displayName: String = "",
            summary: String = "",
            factors: [String] = [],
            previousWeightKilograms: Double? = nil,
            newWeightKilograms: Double? = nil,
            previousRepsUpper: Int? = nil,
            newRepsUpper: Int? = nil,
            previousSets: Int? = nil,
            newSets: Int? = nil,
            previousPercentOneRepMax: Double? = nil,
            newPercentOneRepMax: Double? = nil,
            updatedAt: Date = Date(),
            deletedAt: Date? = nil
        ) {
            self.id = id
            self.createdAt = createdAt
            self.sourceRaw = sourceRaw
            self.decisionRaw = decisionRaw
            self.decidedAt = decidedAt
            self.prescribedExerciseId = prescribedExerciseId
            self.exerciseId = exerciseId
            self.displayName = displayName
            self.summary = summary
            self.factors = factors
            self.previousWeightKilograms = previousWeightKilograms
            self.newWeightKilograms = newWeightKilograms
            self.previousRepsUpper = previousRepsUpper
            self.newRepsUpper = newRepsUpper
            self.previousSets = previousSets
            self.newSets = newSets
            self.previousPercentOneRepMax = previousPercentOneRepMax
            self.newPercentOneRepMax = newPercentOneRepMax
            self.updatedAt = updatedAt
            self.deletedAt = deletedAt
        }
    }

    @Model
    final class AthleteProfile {
        @Attribute(.unique) var id: UUID = UUID()

        // MARK: - Identite (facultative)

        var firstName: String = ""
        var birthDate: Date?

        // MARK: - Mesures de reference (facultatives, valeurs canoniques)

        /// Taille en centimetres. `nil` = non renseignee, jamais 0.
        var heightCentimeters: Double?
        /// Poids de reference en kilogrammes, utilise par les calculs de charge
        /// effective (poids du corps, lest, assistance) quand aucune mesure
        /// datee n'existe. `nil` = inconnu : les vues affichent alors
        /// « donnee manquante » plutot que zero.
        var bodyweightKilograms: Double?

        // MARK: - Preferences d'affichage

        var massUnitRaw: String = "kg"
        var lengthUnitRaw: String = "cm"
        /// Increments de chargement disponibles, en kg canonique, tries.
        var availableIncrementsKilograms: [Double] = [1.25, 2.5, 5]

        // MARK: - Entrainement

        var experienceRaw: String = "beginner"
        var primaryGoalRaw: String = "hypertrophy"
        var secondaryGoalsRaw: [String] = []
        /// Jours de la semaine disponibles, convention `Calendar.weekday` (1 = dimanche).
        var availableWeekdays: [Int] = []
        var sessionMinutesMinimum: Int = 45
        var sessionMinutesMaximum: Int = 75
        var equipmentRaw: String = "fullGym"
        var priorityMuscles: [String] = []
        var excludedExerciseIds: [String] = []
        /// Zones a menager. Jamais un diagnostic : l'interface rappelle de
        /// consulter un professionnel en cas de douleur.
        var avoidAreas: [String] = []
        /// Frequence hebdomadaire souhaitee par groupe musculaire (cle EN du catalogue).
        var weeklyFrequencyByMuscleData: Data?
        var defaultProgressionRuleData: Data?

        // MARK: - Metadonnees de synchronisation

        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        var deletedAt: Date?

        init(
            id: UUID = UUID(),
            firstName: String = "",
            birthDate: Date? = nil,
            heightCentimeters: Double? = nil,
            bodyweightKilograms: Double? = nil,
            massUnitRaw: String = "kg",
            lengthUnitRaw: String = "cm",
            availableIncrementsKilograms: [Double] = [1.25, 2.5, 5],
            experienceRaw: String = "beginner",
            primaryGoalRaw: String = "hypertrophy",
            secondaryGoalsRaw: [String] = [],
            availableWeekdays: [Int] = [],
            sessionMinutesMinimum: Int = 45,
            sessionMinutesMaximum: Int = 75,
            equipmentRaw: String = "fullGym",
            priorityMuscles: [String] = [],
            excludedExerciseIds: [String] = [],
            avoidAreas: [String] = [],
            weeklyFrequencyByMuscleData: Data? = nil,
            defaultProgressionRuleData: Data? = nil,
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            deletedAt: Date? = nil
        ) {
            self.id = id
            self.firstName = firstName
            self.birthDate = birthDate
            self.heightCentimeters = heightCentimeters
            self.bodyweightKilograms = bodyweightKilograms
            self.massUnitRaw = massUnitRaw
            self.lengthUnitRaw = lengthUnitRaw
            self.availableIncrementsKilograms = availableIncrementsKilograms
            self.experienceRaw = experienceRaw
            self.primaryGoalRaw = primaryGoalRaw
            self.secondaryGoalsRaw = secondaryGoalsRaw
            self.availableWeekdays = availableWeekdays
            self.sessionMinutesMinimum = sessionMinutesMinimum
            self.sessionMinutesMaximum = sessionMinutesMaximum
            self.equipmentRaw = equipmentRaw
            self.priorityMuscles = priorityMuscles
            self.excludedExerciseIds = excludedExerciseIds
            self.avoidAreas = avoidAreas
            self.weeklyFrequencyByMuscleData = weeklyFrequencyByMuscleData
            self.defaultProgressionRuleData = defaultProgressionRuleData
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.deletedAt = deletedAt
        }
    }

    @Model
    final class BodyMeasurement {
        @Attribute(.unique) var id: UUID = UUID()
        var kindRaw: String = "bodyweight"
        /// Nom libre, utilise uniquement quand `kind == .custom`.
        var customName: String = ""
        var measuredAt: Date = Date()
        /// Valeur canonique : kg, cm ou % selon `kind`.
        var value: Double = 0
        var sourceRaw: String = "manual"
        var notes: String = ""

        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        var deletedAt: Date?

        init(
            id: UUID = UUID(),
            kindRaw: String = "bodyweight",
            customName: String = "",
            measuredAt: Date = Date(),
            value: Double,
            sourceRaw: String = "manual",
            notes: String = "",
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            deletedAt: Date? = nil
        ) {
            self.id = id
            self.kindRaw = kindRaw
            self.customName = customName
            self.measuredAt = measuredAt
            self.value = value
            self.sourceRaw = sourceRaw
            self.notes = notes
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.deletedAt = deletedAt
        }
    }

    @Model
    final class ReadinessEntry {
        @Attribute(.unique) var id: UUID = UUID()
        var recordedAt: Date = Date()
        /// Echelles 1...5, `nil` = non renseigne.
        var energy: Int?
        var sleepQuality: Int?
        var soreness: Int?
        var stress: Int?
        /// Intensite de douleur 0...10 et zone concernee, facultatives.
        var painIntensity: Int?
        var painArea: String = ""
        var notes: String = ""
        /// Seance a laquelle ce check-in se rapporte, quand il y en a une.
        var programSessionId: UUID?

        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        var deletedAt: Date?

        init(
            id: UUID = UUID(),
            recordedAt: Date = Date(),
            energy: Int? = nil,
            sleepQuality: Int? = nil,
            soreness: Int? = nil,
            stress: Int? = nil,
            painIntensity: Int? = nil,
            painArea: String = "",
            notes: String = "",
            programSessionId: UUID? = nil,
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            deletedAt: Date? = nil
        ) {
            self.id = id
            self.recordedAt = recordedAt
            self.energy = energy
            self.sleepQuality = sleepQuality
            self.soreness = soreness
            self.stress = stress
            self.painIntensity = painIntensity
            self.painArea = painArea
            self.notes = notes
            self.programSessionId = programSessionId
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.deletedAt = deletedAt
        }
    }

    @Model
    final class HealthWorkoutLink {
        @Attribute(.unique) var id: UUID = UUID()
        /// Identifiant de la `CompletedSession` liee.
        var completedSessionId: UUID = UUID()
        /// `UUID` de l'`HKWorkout` correspondant, stocke en texte.
        var healthKitWorkoutIdentifier: String = ""
        var writtenAt: Date = Date()
        /// Origine de l'ecriture : "iphone" ou "watch".
        var sourceRaw: String = "iphone"

        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        var deletedAt: Date?

        init(
            id: UUID = UUID(),
            completedSessionId: UUID,
            healthKitWorkoutIdentifier: String,
            writtenAt: Date = Date(),
            sourceRaw: String = "iphone",
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            deletedAt: Date? = nil
        ) {
            self.id = id
            self.completedSessionId = completedSessionId
            self.healthKitWorkoutIdentifier = healthKitWorkoutIdentifier
            self.writtenAt = writtenAt
            self.sourceRaw = sourceRaw
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.deletedAt = deletedAt
        }
    }

    @Model
    final class CustomExercise {
        @Attribute(.unique) var id: UUID = UUID()
        var name: String = ""
        var primaryMuscles: [String] = []
        var equipment: String = ""
        var notes: String = ""

        // MARK: - Champs v3 (facultatifs)

        var secondaryMuscles: [String] = []
        /// Mouvement principal (push, pull, squat, hinge, carry, core...).
        var movementPattern: String = ""
        /// Type de charge par defaut de cet exercice personnalise.
        var defaultLoadKindRaw: String = "external"
        var isUnilateral: Bool = false
        var tags: [String] = []
        var isFavorite: Bool = false

        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        var deletedAt: Date?

        init(
            id: UUID = UUID(),
            name: String,
            primaryMuscles: [String] = [],
            equipment: String = "",
            notes: String = "",
            secondaryMuscles: [String] = [],
            movementPattern: String = "",
            defaultLoadKindRaw: String = "external",
            isUnilateral: Bool = false,
            tags: [String] = [],
            isFavorite: Bool = false,
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            deletedAt: Date? = nil
        ) {
            self.id = id
            self.name = name
            self.primaryMuscles = primaryMuscles
            self.equipment = equipment
            self.notes = notes
            self.secondaryMuscles = secondaryMuscles
            self.movementPattern = movementPattern
            self.defaultLoadKindRaw = defaultLoadKindRaw
            self.isUnilateral = isUnilateral
            self.tags = tags
            self.isFavorite = isFavorite
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.deletedAt = deletedAt
        }
    }

    @Model
    final class ExerciseGroup {
        @Attribute(.unique) var id: UUID = UUID()
        var kindRaw: String = "superset"
        var orderIndex: Int = 0
        var rounds: Int = 3
        /// Repos entre deux exercices du groupe, en secondes. Zero autorise.
        var restBetweenExercisesSeconds: Int = 0
        /// Repos apres un tour complet, en secondes.
        var restBetweenRoundsSeconds: Int = 90
        /// Transition facultative entre stations d'un circuit, en secondes.
        var transitionSeconds: Int = 0
        /// Circuit : validation manuelle de chaque station plutot qu'automatique.
        var requiresManualStationValidation: Bool = true
        var notes: String = ""

        var session: ProgramSession?

        @Relationship(deleteRule: .nullify, inverse: \PrescribedExercise.group)
        var exercises: [PrescribedExercise] = []

        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        var deletedAt: Date?

        init(
            id: UUID = UUID(),
            kindRaw: String = "superset",
            orderIndex: Int,
            rounds: Int = 3,
            restBetweenExercisesSeconds: Int = 0,
            restBetweenRoundsSeconds: Int = 90,
            transitionSeconds: Int = 0,
            requiresManualStationValidation: Bool = true,
            notes: String = "",
            exercises: [PrescribedExercise] = [],
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            deletedAt: Date? = nil
        ) {
            self.id = id
            self.kindRaw = kindRaw
            self.orderIndex = orderIndex
            self.rounds = rounds
            self.restBetweenExercisesSeconds = restBetweenExercisesSeconds
            self.restBetweenRoundsSeconds = restBetweenRoundsSeconds
            self.transitionSeconds = transitionSeconds
            self.requiresManualStationValidation = requiresManualStationValidation
            self.notes = notes
            self.exercises = exercises
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.deletedAt = deletedAt
        }
    }

    @Model
    final class ExerciseLibraryEntry {
        @Attribute(.unique) var exerciseId: String = ""
        var isFavorite: Bool = false
        /// `[String]` encode, tags deja normalises (sans accent ni majuscule).
        var tagsData: Data?
        var lastUsedAt: Date?
        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        var deletedAt: Date?

        init(
            exerciseId: String,
            isFavorite: Bool = false,
            tagsData: Data? = nil,
            lastUsedAt: Date? = nil,
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            deletedAt: Date? = nil
        ) {
            self.exerciseId = exerciseId
            self.isFavorite = isFavorite
            self.tagsData = tagsData
            self.lastUsedAt = lastUsedAt
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.deletedAt = deletedAt
        }
    }

    @Model
    final class ExerciseCollection {
        @Attribute(.unique) var id: UUID = UUID()
        var name: String = ""
        var notes: String = ""
        /// `[String]` encode : identifiants d'exercices, ordre conserve.
        var exerciseIdsData: Data?
        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        var deletedAt: Date?

        init(
            id: UUID = UUID(),
            name: String,
            notes: String = "",
            exerciseIdsData: Data? = nil,
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            deletedAt: Date? = nil
        ) {
            self.id = id
            self.name = name
            self.notes = notes
            self.exerciseIdsData = exerciseIdsData
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.deletedAt = deletedAt
        }
    }

    @Model
    final class ImportQuarantineEntry {
        @Attribute(.unique) var id: UUID = UUID()
        /// Identifiant de l'import qui a produit cette ligne, pour les regrouper.
        var importIdentifier: UUID = UUID()
        var sourceName: String = ""
        var rowNumber: Int = 0
        var rawRow: String = ""
        var reason: String = ""
        var resolvedAt: Date?
        var createdAt: Date = Date()

        init(
            id: UUID = UUID(),
            importIdentifier: UUID,
            sourceName: String,
            rowNumber: Int,
            rawRow: String,
            reason: String,
            resolvedAt: Date? = nil,
            createdAt: Date = Date()
        ) {
            self.id = id
            self.importIdentifier = importIdentifier
            self.sourceName = sourceName
            self.rowNumber = rowNumber
            self.rawRow = rawRow
            self.reason = reason
            self.resolvedAt = resolvedAt
            self.createdAt = createdAt
        }
    }

    @Model
    final class PersonalBest {
        @Attribute(.unique) var id: UUID = UUID()
        var exerciseId: String = ""
        var displayName: String = ""
        var kindRaw: String = "maxWeight"
        /// Cle de configuration du format, par exemple `amrap:600` ou
        /// `circuit:5x4`. Vide pour les records classiques.
        var configurationKey: String = ""
        var value: Double = 0
        /// Repetitions associees a la performance, quand la nature du record en
        /// depend (charge maximale sur 3 repetitions, par exemple).
        var reps: Int?
        var achievedAt: Date = Date()
        /// `CompletedSession.id` d'origine : un record est toujours recalculable
        /// depuis l'historique, qui reste la source de verite.
        var sourceSessionId: UUID?

        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        var deletedAt: Date?

        init(
            id: UUID = UUID(),
            exerciseId: String,
            displayName: String,
            kindRaw: String = "maxWeight",
            configurationKey: String = "",
            value: Double,
            reps: Int? = nil,
            achievedAt: Date = Date(),
            sourceSessionId: UUID? = nil,
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            deletedAt: Date? = nil
        ) {
            self.id = id
            self.exerciseId = exerciseId
            self.displayName = displayName
            self.kindRaw = kindRaw
            self.configurationKey = configurationKey
            self.value = value
            self.reps = reps
            self.achievedAt = achievedAt
            self.sourceSessionId = sourceSessionId
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.deletedAt = deletedAt
        }
    }

    @Model
    final class PlaceProfile {
        @Attribute(.unique) var id: UUID = UUID()
        var name: String = ""
        var kindRaw: String = "gym"
        /// `[EquipmentAvailability]` encode. Vide = inventaire non renseigne,
        /// ce qui n'interdit aucun exercice.
        var inventoryData: Data?
        /// Lieu propose par defaut lors de la planification.
        var isDefault: Bool = false
        var notes: String = ""

        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        var deletedAt: Date?

        init(
            id: UUID = UUID(),
            name: String,
            kindRaw: String = "gym",
            inventoryData: Data? = nil,
            isDefault: Bool = false,
            notes: String = "",
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            deletedAt: Date? = nil
        ) {
            self.id = id
            self.name = name
            self.kindRaw = kindRaw
            self.inventoryData = inventoryData
            self.isDefault = isDefault
            self.notes = notes
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.deletedAt = deletedAt
        }
    }

    @Model
    final class PlanningSchedule {
        @Attribute(.unique) var id: UUID = UUID()
        var programId: UUID?
        var name: String = ""
        var isEnabled: Bool = true

        /// Jours de semaine, convention `Calendar` (1 = dimanche). Encode en JSON.
        var weekdaysData: Data?
        var startDate: Date = Date()
        var endDate: Date?
        /// Rangs de semaines mises en pause, encodes en JSON.
        var pausedWeekOffsetsData: Data?
        var hour: Int = 18
        var minute: Int = 0
        var placeId: UUID?

        // MARK: - Rappels

        var remindersEnabled: Bool = false
        var reminderLeadMinutes: Int = 60
        /// Heure du rappel « le jour même ». `nil` = rappel desactive.
        var reminderDayOfHour: Int?
        var reminderDayOfMinute: Int?
        var reminderComebackAfterDays: Int = 0
        var reminderSoundEnabled: Bool = true

        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        var deletedAt: Date?

        init(
            id: UUID = UUID(),
            programId: UUID? = nil,
            name: String = "",
            isEnabled: Bool = true,
            weekdaysData: Data? = nil,
            startDate: Date = Date(),
            endDate: Date? = nil,
            pausedWeekOffsetsData: Data? = nil,
            hour: Int = 18,
            minute: Int = 0,
            placeId: UUID? = nil,
            remindersEnabled: Bool = false,
            reminderLeadMinutes: Int = 60,
            reminderDayOfHour: Int? = nil,
            reminderDayOfMinute: Int? = nil,
            reminderComebackAfterDays: Int = 0,
            reminderSoundEnabled: Bool = true,
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            deletedAt: Date? = nil
        ) {
            self.id = id
            self.programId = programId
            self.name = name
            self.isEnabled = isEnabled
            self.weekdaysData = weekdaysData
            self.startDate = startDate
            self.endDate = endDate
            self.pausedWeekOffsetsData = pausedWeekOffsetsData
            self.hour = hour
            self.minute = minute
            self.placeId = placeId
            self.remindersEnabled = remindersEnabled
            self.reminderLeadMinutes = reminderLeadMinutes
            self.reminderDayOfHour = reminderDayOfHour
            self.reminderDayOfMinute = reminderDayOfMinute
            self.reminderComebackAfterDays = reminderComebackAfterDays
            self.reminderSoundEnabled = reminderSoundEnabled
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.deletedAt = deletedAt
        }
    }

    @Model
    final class NotificationRecord {
        @Attribute(.unique) var identifier: String = ""
        var workoutId: UUID?
        var kindRaw: String = "before"
        var fireDate: Date = Date()
        /// Date de suppression volontaire. Non nil = ne jamais reprogrammer.
        var dismissedAt: Date?
        var createdAt: Date = Date()
        var updatedAt: Date = Date()

        init(
            identifier: String,
            workoutId: UUID? = nil,
            kindRaw: String = "before",
            fireDate: Date = Date(),
            dismissedAt: Date? = nil,
            createdAt: Date = Date(),
            updatedAt: Date = Date()
        ) {
            self.identifier = identifier
            self.workoutId = workoutId
            self.kindRaw = kindRaw
            self.fireDate = fireDate
            self.dismissedAt = dismissedAt
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }

    @Model
    final class CalendarLink {
        @Attribute(.unique) var id: UUID = UUID()
        var scheduledWorkoutId: UUID = UUID()
        var eventIdentifier: String = ""
        var calendarIdentifier: String = ""
        var exportedAt: Date = Date()
        var updatedAt: Date = Date()
        var deletedAt: Date?

        init(
            id: UUID = UUID(),
            scheduledWorkoutId: UUID,
            eventIdentifier: String,
            calendarIdentifier: String,
            exportedAt: Date = Date(),
            updatedAt: Date = Date(),
            deletedAt: Date? = nil
        ) {
            self.id = id
            self.scheduledWorkoutId = scheduledWorkoutId
            self.eventIdentifier = eventIdentifier
            self.calendarIdentifier = calendarIdentifier
            self.exportedAt = exportedAt
            self.updatedAt = updatedAt
            self.deletedAt = deletedAt
        }
    }

    @Model
    final class Program {
        @Attribute(.unique) var id: UUID = UUID()
        var name: String = ""
        var notes: String = ""
        var isActive: Bool = false
        var createdAt: Date = Date()
        // Metadonnees de synchronisation. `updatedAt` par defaut a la date de
        // creation : les programmes enregistres avant leur ajout obtiennent
        // cette valeur par la migration legere, ce qui reste coherent.
        var updatedAt: Date = Date()
        var deletedAt: Date?

        @Relationship(deleteRule: .cascade, inverse: \ProgramSession.program)
        var sessions: [ProgramSession] = []

        init(
            id: UUID = UUID(),
            name: String,
            notes: String = "",
            isActive: Bool = false,
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            deletedAt: Date? = nil,
            sessions: [ProgramSession] = []
        ) {
            self.id = id
            self.name = name
            self.notes = notes
            self.isActive = isActive
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.deletedAt = deletedAt
            self.sessions = sessions
        }
    }

    @Model
    final class ProgramSession {
        @Attribute(.unique) var id: UUID = UUID()
        var name: String = ""
        var orderIndex: Int = 0
        var warmupEnabled: Bool = false
        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        var deletedAt: Date?

        var program: Program?

        @Relationship(deleteRule: .cascade, inverse: \PrescribedExercise.session)
        var exercises: [PrescribedExercise] = []

        // Supprimer une seance supprime ses groupes ; les prescriptions qu'ils
        // contiennent sont detachees (deleteRule .nullify cote ExerciseGroup),
        // jamais supprimees deux fois.
        @Relationship(deleteRule: .cascade, inverse: \ExerciseGroup.session)
        var groups: [ExerciseGroup] = []

        init(
            id: UUID = UUID(),
            name: String,
            orderIndex: Int,
            warmupEnabled: Bool = false,
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            deletedAt: Date? = nil,
            exercises: [PrescribedExercise] = []
        ) {
            self.id = id
            self.name = name
            self.orderIndex = orderIndex
            self.warmupEnabled = warmupEnabled
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.deletedAt = deletedAt
            self.exercises = exercises
        }
    }

    @Model
    final class PrescribedExercise {
        @Attribute(.unique) var id: UUID = UUID()
        var exerciseId: String = ""
        var displayName: String = ""
        var orderIndex: Int = 0
        var formatRaw: String = "classic"
        var sets: Int = 0
        var repsLower: Int = 0
        var repsUpper: Int = 0
        var restSeconds: Int = 0
        var percentOneRepMax: Double?
        var percentMaxReps: Double?
        // Poids cible optionnel en mode de charge "Libre" : quand renseigne,
        // prefill prioritaire dans le runner (cf. WorkoutState.suggestedWeight),
        // avant le dernier poids logge. nil = comportement inchange.
        var targetWeight: Double?
        var pyramidReps: [Int] = []
        var pyramidMinRest: Int = 0
        var pyramidMaxRest: Int = 0
        var intervalWork: Int = 0
        var intervalRest: Int = 0
        var intervalRounds: Int = 0
        var amrapSeconds: Int = 0
        var notes: String = ""

        // MARK: - Champs v3 (tous facultatifs, migration legere)

        /// Position dans son groupe (superset, circuit...). Ignore hors groupe.
        var groupOrderIndex: Int = 0
        /// Tempo en quatre phases, notation `a-b-c-d`. Vide = non prescrit.
        var tempoNotation: String = ""
        /// Effort cible encode (`EffortRating`). nil = non prescrit.
        var targetEffortData: Data?
        /// Regle de progression encodee (`ProgressionRule`). nil = regle du profil.
        var progressionRuleData: Data?
        /// Type de charge prescrit. Vide = deduit du catalogue a l'execution.
        var loadKindRaw: String = ""
        /// Convention unilaterale explicite.
        var sideConventionRaw: String = "bilateral"
        /// Duree ou distance cible pour les exercices qui ne se comptent pas en
        /// repetitions. Zero = non prescrit.
        var targetDurationSeconds: Int = 0
        var targetDistanceMeters: Double = 0

        // Dropset : paliers de baisse de charge apres la serie principale.
        // Valeurs en pourcentage de la charge de depart lorsque
        // `dropsetUsesPercent`, sinon en kilogrammes.
        var dropsetDrops: [Double] = []
        var dropsetUsesPercent: Bool = true
        var dropsetRestSeconds: Int = 0

        // Rest-pause : micro-repos et mini-series apres la serie principale.
        var restPauseMicroRestSeconds: Int = 0
        var restPauseMaxMiniSets: Int = 0
        /// Seuil d'arret : en dessous de ce nombre de repetitions, on arrete.
        var restPauseMinimumReps: Int = 0

        // Myo-reps : serie d'activation puis mini-series courtes.
        var myoRepsActivationLower: Int = 0
        var myoRepsActivationUpper: Int = 0
        var myoRepsTargetRepsInReserve: Int = 0
        var myoRepsMiniSetReps: Int = 0
        var myoRepsMaxMiniSets: Int = 0
        var myoRepsRestSeconds: Int = 0

        // Intervalles etendus : compte a rebours et preparation.
        var intervalCountdownSeconds: Int = 0
        /// For Time : plafond de temps en secondes. Zero = pas de plafond.
        var forTimeCapSeconds: Int = 0

        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        var deletedAt: Date?

        var session: ProgramSession?
        var group: ExerciseGroup?

        init(
            id: UUID = UUID(),
            exerciseId: String,
            displayName: String,
            orderIndex: Int,
            formatRaw: String = "classic",
            sets: Int = 0,
            repsLower: Int = 0,
            repsUpper: Int = 0,
            restSeconds: Int = 0,
            percentOneRepMax: Double? = nil,
            percentMaxReps: Double? = nil,
            targetWeight: Double? = nil,
            pyramidReps: [Int] = [],
            pyramidMinRest: Int = 0,
            pyramidMaxRest: Int = 0,
            intervalWork: Int = 0,
            intervalRest: Int = 0,
            intervalRounds: Int = 0,
            amrapSeconds: Int = 0,
            notes: String = "",
            groupOrderIndex: Int = 0,
            tempoNotation: String = "",
            targetEffortData: Data? = nil,
            progressionRuleData: Data? = nil,
            loadKindRaw: String = "",
            sideConventionRaw: String = "bilateral",
            targetDurationSeconds: Int = 0,
            targetDistanceMeters: Double = 0,
            dropsetDrops: [Double] = [],
            dropsetUsesPercent: Bool = true,
            dropsetRestSeconds: Int = 0,
            restPauseMicroRestSeconds: Int = 0,
            restPauseMaxMiniSets: Int = 0,
            restPauseMinimumReps: Int = 0,
            myoRepsActivationLower: Int = 0,
            myoRepsActivationUpper: Int = 0,
            myoRepsTargetRepsInReserve: Int = 0,
            myoRepsMiniSetReps: Int = 0,
            myoRepsMaxMiniSets: Int = 0,
            myoRepsRestSeconds: Int = 0,
            intervalCountdownSeconds: Int = 0,
            forTimeCapSeconds: Int = 0,
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            deletedAt: Date? = nil
        ) {
            self.id = id
            self.exerciseId = exerciseId
            self.displayName = displayName
            self.orderIndex = orderIndex
            self.formatRaw = formatRaw
            self.sets = sets
            self.repsLower = repsLower
            self.repsUpper = repsUpper
            self.restSeconds = restSeconds
            self.percentOneRepMax = percentOneRepMax
            self.percentMaxReps = percentMaxReps
            self.targetWeight = targetWeight
            self.pyramidReps = pyramidReps
            self.pyramidMinRest = pyramidMinRest
            self.pyramidMaxRest = pyramidMaxRest
            self.intervalWork = intervalWork
            self.intervalRest = intervalRest
            self.intervalRounds = intervalRounds
            self.amrapSeconds = amrapSeconds
            self.notes = notes
            self.groupOrderIndex = groupOrderIndex
            self.tempoNotation = tempoNotation
            self.targetEffortData = targetEffortData
            self.progressionRuleData = progressionRuleData
            self.loadKindRaw = loadKindRaw
            self.sideConventionRaw = sideConventionRaw
            self.targetDurationSeconds = targetDurationSeconds
            self.targetDistanceMeters = targetDistanceMeters
            self.dropsetDrops = dropsetDrops
            self.dropsetUsesPercent = dropsetUsesPercent
            self.dropsetRestSeconds = dropsetRestSeconds
            self.restPauseMicroRestSeconds = restPauseMicroRestSeconds
            self.restPauseMaxMiniSets = restPauseMaxMiniSets
            self.restPauseMinimumReps = restPauseMinimumReps
            self.myoRepsActivationLower = myoRepsActivationLower
            self.myoRepsActivationUpper = myoRepsActivationUpper
            self.myoRepsTargetRepsInReserve = myoRepsTargetRepsInReserve
            self.myoRepsMiniSetReps = myoRepsMiniSetReps
            self.myoRepsMaxMiniSets = myoRepsMaxMiniSets
            self.myoRepsRestSeconds = myoRepsRestSeconds
            self.intervalCountdownSeconds = intervalCountdownSeconds
            self.forTimeCapSeconds = forTimeCapSeconds
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.deletedAt = deletedAt
        }
    }

    @Model
    final class ExerciseRecord {
        @Attribute(.unique) var id: UUID = UUID()
        var exerciseId: String = ""
        var displayName: String = ""
        var oneRepMax: Double?
        var maxReps: Int?
        var updatedAt: Date = Date()
        var createdAt: Date = Date()
        var deletedAt: Date?

        init(
            id: UUID = UUID(),
            exerciseId: String,
            displayName: String,
            oneRepMax: Double? = nil,
            maxReps: Int? = nil,
            updatedAt: Date = Date(),
            createdAt: Date = Date(),
            deletedAt: Date? = nil
        ) {
            self.id = id
            self.exerciseId = exerciseId
            self.displayName = displayName
            self.oneRepMax = oneRepMax
            self.maxReps = maxReps
            self.updatedAt = updatedAt
            self.createdAt = createdAt
            self.deletedAt = deletedAt
        }
    }

    @Model
    final class SessionTemplate {
        @Attribute(.unique) var id: UUID = UUID()
        var name: String = ""
        var scopeRaw: String = "session"
        var notes: String = ""
        /// Charge utile encodee. Vide = modele invalide, jamais applique.
        var payloadData: Data?
        /// Version du modele, incrementee a chaque enregistrement d'une nouvelle
        /// mouture sous le meme nom.
        var version: Int = 1
        var isArchived: Bool = false
        var isFavorite: Bool = false
        var lastUsedAt: Date?

        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        var deletedAt: Date?

        init(
            id: UUID = UUID(),
            name: String,
            scopeRaw: String = "session",
            notes: String = "",
            payloadData: Data? = nil,
            version: Int = 1,
            isArchived: Bool = false,
            isFavorite: Bool = false,
            lastUsedAt: Date? = nil,
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            deletedAt: Date? = nil
        ) {
            self.id = id
            self.name = name
            self.scopeRaw = scopeRaw
            self.notes = notes
            self.payloadData = payloadData
            self.version = version
            self.isArchived = isArchived
            self.isFavorite = isFavorite
            self.lastUsedAt = lastUsedAt
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.deletedAt = deletedAt
        }
    }

    @Model
    final class SyncState {
        @Attribute(.unique) var id: UUID = UUID()
        var isEnabled: Bool = false
        var lastSuccessAt: Date?
        var lastAttemptAt: Date?
        var lastFailureRaw: String?
        /// `SyncOutbox` encode.
        var outboxData: Data?
        /// Dernière date poussée par entité, `[UUID: Date]` encode.
        var lastPushedData: Data?
        /// Conflits conservés, `[SyncConflict]` encode.
        var conflictsData: Data?
        /// Identifiant OPAQUE du compte iCloud utilisé lors de la dernière
        /// synchronisation réussie, pour détecter un changement de compte.
        /// Ce n'est jamais l'identifiant Apple lui-même.
        var accountFingerprint: String?

        var createdAt: Date = Date()
        var updatedAt: Date = Date()

        init(
            id: UUID = UUID(),
            isEnabled: Bool = false,
            lastSuccessAt: Date? = nil,
            lastAttemptAt: Date? = nil,
            lastFailureRaw: String? = nil,
            outboxData: Data? = nil,
            lastPushedData: Data? = nil,
            conflictsData: Data? = nil,
            accountFingerprint: String? = nil,
            createdAt: Date = Date(),
            updatedAt: Date = Date()
        ) {
            self.id = id
            self.isEnabled = isEnabled
            self.lastSuccessAt = lastSuccessAt
            self.lastAttemptAt = lastAttemptAt
            self.lastFailureRaw = lastFailureRaw
            self.outboxData = outboxData
            self.lastPushedData = lastPushedData
            self.conflictsData = conflictsData
            self.accountFingerprint = accountFingerprint
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }

    @Model
    final class TrainingGoal {
        @Attribute(.unique) var id: UUID = UUID()
        var title: String = ""
        /// `GoalTarget` encode. Le type porte son unite et son sens.
        var targetData: Data?
        var stateRaw: String = "active"
        /// Echeance facultative : un objectif sans date reste valable.
        var dueDate: Date?
        /// Valeur de depart, figee a la creation : indispensable pour exprimer
        /// l'avancement d'un objectif en baisse.
        var startValue: Double?
        var notes: String = ""

        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        var deletedAt: Date?

        init(
            id: UUID = UUID(),
            title: String,
            targetData: Data? = nil,
            stateRaw: String = "active",
            dueDate: Date? = nil,
            startValue: Double? = nil,
            notes: String = "",
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            deletedAt: Date? = nil
        ) {
            self.id = id
            self.title = title
            self.targetData = targetData
            self.stateRaw = stateRaw
            self.dueDate = dueDate
            self.startValue = startValue
            self.notes = notes
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.deletedAt = deletedAt
        }
    }

    @Model
    final class TrainingPlan {
        @Attribute(.unique) var id: UUID = UUID()
        var name: String = ""
        var programId: UUID?
        var startDate: Date = Date()
        var statusRaw: String = "draft"
        /// Version du plan : incrementee a chaque recalcul confirme, afin de
        /// tracer quelle version a produit une seance planifiee.
        var version: Int = 1
        var notes: String = ""

        @Relationship(deleteRule: .cascade, inverse: \TrainingBlock.plan)
        var blocks: [TrainingBlock] = []

        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        var deletedAt: Date?

        init(
            id: UUID = UUID(),
            name: String,
            programId: UUID? = nil,
            startDate: Date = Date(),
            statusRaw: String = "draft",
            version: Int = 1,
            notes: String = "",
            blocks: [TrainingBlock] = [],
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            deletedAt: Date? = nil
        ) {
            self.id = id
            self.name = name
            self.programId = programId
            self.startDate = startDate
            self.statusRaw = statusRaw
            self.version = version
            self.notes = notes
            self.blocks = blocks
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.deletedAt = deletedAt
        }
    }

    @Model
    final class TrainingBlock {
        @Attribute(.unique) var id: UUID = UUID()
        var kindRaw: String = "accumulation"
        var orderIndex: Int = 0
        var name: String = ""
        /// Explication courte du role du bloc, affichee a l'utilisateur.
        var rationale: String = ""

        var plan: TrainingPlan?

        @Relationship(deleteRule: .cascade, inverse: \TrainingWeek.block)
        var weeks: [TrainingWeek] = []

        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        var deletedAt: Date?

        init(
            id: UUID = UUID(),
            kindRaw: String = "accumulation",
            orderIndex: Int,
            name: String = "",
            rationale: String = "",
            weeks: [TrainingWeek] = [],
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            deletedAt: Date? = nil
        ) {
            self.id = id
            self.kindRaw = kindRaw
            self.orderIndex = orderIndex
            self.name = name
            self.rationale = rationale
            self.weeks = weeks
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.deletedAt = deletedAt
        }
    }

    @Model
    final class TrainingWeek {
        @Attribute(.unique) var id: UUID = UUID()
        /// Numero de semaine dans le PLAN (1-based), pas dans le bloc.
        var weekNumber: Int = 1
        var startDate: Date = Date()
        var stateRaw: String = "upcoming"
        /// Cible de volume : nombre de series difficiles par groupe musculaire.
        var volumeTargetData: Data?
        /// Multiplicateur applique au volume et a l'intensite pour une decharge.
        var volumeMultiplier: Double = 1
        var intensityMultiplier: Double = 1

        var block: TrainingBlock?

        @Relationship(deleteRule: .cascade, inverse: \ScheduledWorkout.week)
        var scheduledWorkouts: [ScheduledWorkout] = []

        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        var deletedAt: Date?

        init(
            id: UUID = UUID(),
            weekNumber: Int,
            startDate: Date = Date(),
            stateRaw: String = "upcoming",
            volumeTargetData: Data? = nil,
            volumeMultiplier: Double = 1,
            intensityMultiplier: Double = 1,
            scheduledWorkouts: [ScheduledWorkout] = [],
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            deletedAt: Date? = nil
        ) {
            self.id = id
            self.weekNumber = weekNumber
            self.startDate = startDate
            self.stateRaw = stateRaw
            self.volumeTargetData = volumeTargetData
            self.volumeMultiplier = volumeMultiplier
            self.intensityMultiplier = intensityMultiplier
            self.scheduledWorkouts = scheduledWorkouts
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.deletedAt = deletedAt
        }
    }

    @Model
    final class ScheduledWorkout {
        @Attribute(.unique) var id: UUID = UUID()
        var plannedDate: Date = Date()
        var programSessionId: UUID?
        /// Nom affiche au moment de la planification : garde le planning lisible
        /// meme si la seance source est renommee ou supprimee.
        var displayName: String = ""
        var stateRaw: String = "planned"
        /// `CompletedSession.id` produite par cette seance planifiee, le cas echeant.
        var completedSessionId: UUID?
        var notes: String = ""

        // MARK: - Champs v4 (facultatifs, migration legere)

        /// Lieu prevu pour cette seance. nil = lieu par defaut du profil.
        var placeId: UUID?
        /// Recurrence qui a produit cette seance, le cas echeant.
        var scheduleId: UUID?
        /// Date d'origine avant un report. Conservee pour expliquer le
        /// deplacement : « reportee du 3 au 5 » est plus utile que « le 5 ».
        var originalDate: Date?

        var week: TrainingWeek?

        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        var deletedAt: Date?

        init(
            id: UUID = UUID(),
            plannedDate: Date,
            programSessionId: UUID? = nil,
            displayName: String = "",
            stateRaw: String = "planned",
            completedSessionId: UUID? = nil,
            notes: String = "",
            placeId: UUID? = nil,
            scheduleId: UUID? = nil,
            originalDate: Date? = nil,
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            deletedAt: Date? = nil
        ) {
            self.id = id
            self.plannedDate = plannedDate
            self.programSessionId = programSessionId
            self.displayName = displayName
            self.stateRaw = stateRaw
            self.completedSessionId = completedSessionId
            self.notes = notes
            self.placeId = placeId
            self.scheduleId = scheduleId
            self.originalDate = originalDate
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.deletedAt = deletedAt
        }
    }

    @Model
    final class CompletedSession {
        @Attribute(.unique) var id: UUID = UUID()
        var programId: UUID?
        var programSessionId: UUID?
        var date: Date = Date()
        var programName: String = ""
        var sessionName: String = ""
        var durationSeconds: Int = 0

        // MARK: - Champs v3 (facultatifs, migration legere)

        var notes: String = ""
        /// Seance planifiee a l'origine de cette seance realisee, le cas echeant.
        var scheduledWorkoutId: UUID?
        /// Check-in de forme rattache a cette seance.
        var readinessEntryId: UUID?
        /// Poids de corps connu au moment de la seance (kg). Fige ici pour que
        /// les calculs de charge effective restent justes des annees apres.
        var bodyweightKilograms: Double?
        /// Une seance terminee est immuable : une correction cree une revision
        /// tracee par ce compteur et par `updatedAt`.
        var revision: Int = 1

        // MARK: - Champs v4 (facultatifs, migration legere)

        /// Lieu ou la seance a eu lieu. nil = non renseigne.
        var placeId: UUID?
        /// Origine de la seance quand elle vient d'un import (« Strong »,
        /// « Hevy », « CSV »). Vide = saisie dans Muscu.
        var importSource: String = ""
        /// Cle de deduplication d'import. Vide hors import.
        var importSignature: String = ""

        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        var deletedAt: Date?

        @Relationship(deleteRule: .cascade, inverse: \CompletedSet.session)
        var sets: [CompletedSet] = []

        init(
            id: UUID = UUID(),
            date: Date = Date(),
            programId: UUID? = nil,
            programSessionId: UUID? = nil,
            programName: String,
            sessionName: String,
            durationSeconds: Int = 0,
            notes: String = "",
            placeId: UUID? = nil,
            importSource: String = "",
            importSignature: String = "",
            scheduledWorkoutId: UUID? = nil,
            readinessEntryId: UUID? = nil,
            bodyweightKilograms: Double? = nil,
            revision: Int = 1,
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            deletedAt: Date? = nil,
            sets: [CompletedSet] = []
        ) {
            self.id = id
            self.date = date
            self.programId = programId
            self.programSessionId = programSessionId
            self.programName = programName
            self.sessionName = sessionName
            self.durationSeconds = durationSeconds
            self.notes = notes
            self.placeId = placeId
            self.importSource = importSource
            self.importSignature = importSignature
            self.scheduledWorkoutId = scheduledWorkoutId
            self.readinessEntryId = readinessEntryId
            self.bodyweightKilograms = bodyweightKilograms
            self.revision = revision
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.deletedAt = deletedAt
            self.sets = sets
        }
    }

    @Model
    final class CompletedSet {
        @Attribute(.unique) var id: UUID = UUID()
        var exerciseId: String = ""
        var displayName: String = ""
        var orderIndex: Int = 0
        var setIndex: Int = 0
        var weight: Double = 0
        var reps: Int = 0
        var isWarmup: Bool = false
        var loadTypeRaw: String = "unknown"

        // MARK: - Champs v3 (facultatifs, migration legere)

        /// Role de la serie. Vide = deduit de `isWarmup`, qui reste la source de
        /// verite pour les series enregistrees avant l'ajout de ce champ.
        var roleRaw: String = ""
        var sideConventionRaw: String = "bilateral"
        var tempoNotation: String = ""
        /// `EffortRating` encode (RPE ou RIR declare). nil = non renseigne.
        var effortData: Data?
        var notes: String = ""
        /// Echec musculaire atteint sur cette serie, marque explicitement.
        var reachedFailure: Bool = false
        /// Groupe (superset, circuit) auquel la serie appartient, et tour courant.
        var groupId: UUID?
        var roundIndex: Int = 0
        /// Palier d'un dropset, mini-serie d'un rest-pause ou d'un myo-reps.
        /// Zero = serie principale.
        var subSetIndex: Int = 0
        var durationSeconds: Int?
        var distanceMeters: Double?
        var calories: Double?
        /// Exercice initialement prevu lorsqu'une substitution a eu lieu :
        /// l'historique garde prevu ET realise.
        var plannedExerciseId: String = ""
        var formatRaw: String = "classic"
        /// Rang de saisie dans la seance (0-based). L'ordre d'affichage groupe
        /// les series par exercice ; ce rang conserve l'ordre REEL de saisie,
        /// dont depend la correction de la derniere serie. Zero pour les series
        /// anterieures a ce champ, qui n'en avaient pas besoin (aucun groupe).
        var sequenceIndex: Int = 0

        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        var deletedAt: Date?

        var session: CompletedSession?
        var activeWorkout: ActiveWorkout?

        init(
            id: UUID = UUID(),
            exerciseId: String,
            displayName: String,
            orderIndex: Int,
            setIndex: Int,
            weight: Double,
            reps: Int,
            isWarmup: Bool = false,
            loadTypeRaw: String = "unknown",
            roleRaw: String = "",
            sideConventionRaw: String = "bilateral",
            tempoNotation: String = "",
            effortData: Data? = nil,
            notes: String = "",
            reachedFailure: Bool = false,
            groupId: UUID? = nil,
            roundIndex: Int = 0,
            subSetIndex: Int = 0,
            durationSeconds: Int? = nil,
            distanceMeters: Double? = nil,
            calories: Double? = nil,
            plannedExerciseId: String = "",
            formatRaw: String = "classic",
            sequenceIndex: Int = 0,
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            deletedAt: Date? = nil
        ) {
            self.id = id
            self.exerciseId = exerciseId
            self.displayName = displayName
            self.orderIndex = orderIndex
            self.setIndex = setIndex
            self.weight = weight
            self.reps = reps
            self.isWarmup = isWarmup
            self.loadTypeRaw = loadTypeRaw
            self.roleRaw = roleRaw
            self.sideConventionRaw = sideConventionRaw
            self.tempoNotation = tempoNotation
            self.effortData = effortData
            self.notes = notes
            self.reachedFailure = reachedFailure
            self.groupId = groupId
            self.roundIndex = roundIndex
            self.subSetIndex = subSetIndex
            self.durationSeconds = durationSeconds
            self.distanceMeters = distanceMeters
            self.calories = calories
            self.plannedExerciseId = plannedExerciseId
            self.formatRaw = formatRaw
            self.sequenceIndex = sequenceIndex
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.deletedAt = deletedAt
        }
    }

}
