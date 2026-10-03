import CryptoKit
import Foundation
import SwiftData
import MuscuEngine

// Export/import complet des donnees utilisateur au format JSON versionne.
// Les modeles @Model ne sont pas rendus Codable directement (SwiftData ne
// le supporte pas proprement pour les relations) : on passe par des DTO
// Codable dedies, mappes explicitement dans les deux sens.
//
// Format v3 : enveloppe { version, exportedAt, manifest, payload }. Le
// manifeste porte les compteurs et une somme de controle du payload, afin
// de detecter une troncature ou une alteration AVANT toute insertion. Les
// formats v1 et v2 (enveloppe plate) restent importables : ils sont decodes
// vers le meme `Payload`.
enum ExportImport {
    static let currentVersion = 4
    static let maximumImportBytes = 20 * 1_024 * 1_024

    // MARK: - Enveloppe

    /// Enveloppe v4. `version` reste en tete pour qu'une version future
    /// puisse etre refusee avec un message precis sans decoder le reste.
    struct Envelope: Codable {
        var version: Int
        var exportedAt: Date
        var manifest: Manifest
        var payload: Payload
    }

    /// Metadonnees verifiables de l'archive. Ne contient aucune donnee
    /// personnelle : uniquement des compteurs et une empreinte.
    struct Manifest: Codable, Equatable {
        var schemaVersion: Int
        var appVersion: String
        var counts: [String: Int]
        /// `sha256:<hex>` du payload encode de maniere canonique.
        var checksum: String

        static let checksumPrefix = "sha256:"
    }

    /// Contenu reel de l'archive. Les champs ajoutes en v3 et v4 ont tous
    /// une valeur par defaut afin qu'une archive v1, v2 ou v3 se decode vers
    /// ce meme type sans traitement particulier.
    struct Payload: Codable {
        var programs: [ProgramDTO] = []
        var sessions: [CompletedSessionDTO] = []
        var records: [RecordDTO] = []
        var customExercises: [CustomExerciseDTO] = []
        var activeWorkout: ActiveWorkoutDTO?
        var settings: SettingsDTO?
        var profile: ProfileDTO?
        var measurements: [BodyMeasurementDTO] = []
        var readinessEntries: [ReadinessEntryDTO] = []
        var personalBests: [PersonalBestDTO] = []
        var trainingPlans: [TrainingPlanDTO] = []
        var adaptations: [AdaptationDTO] = []
        var goals: [GoalDTO] = []
        // Ajouts v4.
        var places: [PlaceDTO] = []
        var schedules: [ScheduleDTO] = []
        var templates: [TemplateDTO] = []
        var libraryEntries: [LibraryEntryDTO] = []
        var collections: [CollectionDTO] = []
    }

    /// Enveloppe plate des versions 1 et 2, conservee en LECTURE SEULE.
    struct LegacyEnvelope: Codable {
        var version: Int
        var exportedAt: Date
        var programs: [ProgramDTO]
        var sessions: [CompletedSessionDTO]
        var records: [RecordDTO]
        var customExercises: [CustomExerciseDTO]
        var activeWorkout: ActiveWorkoutDTO?
        var settings: SettingsDTO?

        var payload: Payload {
            Payload(
                programs: programs,
                sessions: sessions,
                records: records,
                customExercises: customExercises,
                activeWorkout: activeWorkout,
                settings: settings
            )
        }
    }

    // MARK: - DTO Programme

    struct ProgramDTO: Codable {
        var id: UUID
        var name: String
        var notes: String
        var isActive: Bool
        var createdAt: Date
        var sessions: [SessionDTO]
    }

    struct SessionDTO: Codable {
        var id: UUID
        var name: String
        var orderIndex: Int
        var warmupEnabled: Bool
        var exercises: [ExerciseDTO]
        /// Groupes (superset, circuit...) de cette seance. Vide en v1/v2.
        var groups: [GroupDTO]?
    }

    struct ExerciseDTO: Codable {
        var id: UUID
        var exerciseId: String
        var displayName: String
        var orderIndex: Int
        var formatRaw: String
        var sets: Int
        var repsLower: Int
        var repsUpper: Int
        var restSeconds: Int
        var percentOneRepMax: Double?
        var percentMaxReps: Double?
        var targetWeight: Double?
        var pyramidReps: [Int]
        var pyramidMinRest: Int
        var pyramidMaxRest: Int
        var intervalWork: Int
        var intervalRest: Int
        var intervalRounds: Int
        var amrapSeconds: Int
        var notes: String
        // Champs v3, absents des archives v1/v2.
        var groupId: UUID?
        var groupOrderIndex: Int?
        var tempoNotation: String?
        var targetEffort: EffortRating?
        var progressionRule: ProgressionRule?
        var loadKindRaw: String?
        var sideConventionRaw: String?
        var targetDurationSeconds: Int?
        var targetDistanceMeters: Double?
    }

    struct GroupDTO: Codable {
        var id: UUID
        var kindRaw: String
        var orderIndex: Int
        var rounds: Int
        var restBetweenExercisesSeconds: Int
        var restBetweenRoundsSeconds: Int
        var transitionSeconds: Int
        var requiresManualStationValidation: Bool
        var notes: String
    }

    // MARK: - DTO Historique

    struct CompletedSessionDTO: Codable {
        var id: UUID
        var date: Date
        var programId: UUID?
        var programSessionId: UUID?
        var programName: String
        var sessionName: String
        var durationSeconds: Int
        var sets: [CompletedSetDTO]
        // Champs v3.
        var notes: String?
        var scheduledWorkoutId: UUID?
        var readinessEntryId: UUID?
        var bodyweightKilograms: Double?
        var revision: Int?
        // Champs v7 (schema SwiftData), tous facultatifs : une archive
        // anterieure les omet et se decode sans eux.
        var effortRating: Int?
        var avgHeartRate: Double?
        var maxHeartRate: Double?
        var minHeartRate: Double?
        var activeEnergyKcal: Double?
        var editedAt: Date?
    }

    struct CompletedSetDTO: Codable {
        var id: UUID
        var exerciseId: String
        var displayName: String
        var orderIndex: Int
        var setIndex: Int
        var weight: Double
        var reps: Int
        var isWarmup: Bool
        var loadTypeRaw: String?
        // Champs v3.
        var roleRaw: String?
        var sideConventionRaw: String?
        var tempoNotation: String?
        var effort: EffortRating?
        var notes: String?
        var reachedFailure: Bool?
        var groupId: UUID?
        var roundIndex: Int?
        var subSetIndex: Int?
        var durationSeconds: Int?
        var distanceMeters: Double?
        var calories: Double?
        var plannedExerciseId: String?
        var formatRaw: String?
        var sequenceIndex: Int?
        // Champ v7 (schema SwiftData).
        var actualRestSeconds: Int?
    }

    // MARK: - DTO Records / exercices personnalises

    struct RecordDTO: Codable {
        var id: UUID
        var exerciseId: String
        var displayName: String
        var oneRepMax: Double?
        var maxReps: Int?
        var updatedAt: Date
    }

    struct CustomExerciseDTO: Codable {
        var id: UUID
        var name: String
        var primaryMuscles: [String]
        var equipment: String
        var notes: String
        // Champs v3.
        var secondaryMuscles: [String]?
        var movementPattern: String?
        var defaultLoadKindRaw: String?
        var isUnilateral: Bool?
        var tags: [String]?
        var isFavorite: Bool?
        // Champ v7 (schema SwiftData).
        var mergedIntoExerciseId: String?
    }

    // MARK: - DTO v3

    struct ProfileDTO: Codable {
        var id: UUID
        var firstName: String
        var birthDate: Date?
        var heightCentimeters: Double?
        var bodyweightKilograms: Double?
        var massUnitRaw: String
        var lengthUnitRaw: String
        var availableIncrementsKilograms: [Double]
        var experienceRaw: String
        var primaryGoalRaw: String
        var secondaryGoalsRaw: [String]
        var availableWeekdays: [Int]
        var sessionMinutesMinimum: Int
        var sessionMinutesMaximum: Int
        var equipmentRaw: String
        var priorityMuscles: [String]
        var excludedExerciseIds: [String]
        var avoidAreas: [String]
        var weeklyFrequencyByMuscle: [String: Int]
        var defaultProgressionRule: ProgressionRule?
        var createdAt: Date
        var updatedAt: Date
    }

    struct BodyMeasurementDTO: Codable {
        var id: UUID
        var kindRaw: String
        var customName: String
        var measuredAt: Date
        var value: Double
        var sourceRaw: String
        var notes: String
        var createdAt: Date
        var updatedAt: Date
        // Champ v7 (schema SwiftData).
        var healthSampleUUID: String?
    }

    struct ReadinessEntryDTO: Codable {
        var id: UUID
        var recordedAt: Date
        var energy: Int?
        var sleepQuality: Int?
        var soreness: Int?
        var stress: Int?
        var painIntensity: Int?
        var painArea: String
        var notes: String
        var programSessionId: UUID?
        var createdAt: Date
        var updatedAt: Date
    }

    struct PersonalBestDTO: Codable {
        var id: UUID
        var exerciseId: String
        var displayName: String
        var kindRaw: String
        var configurationKey: String
        var value: Double
        var reps: Int?
        var achievedAt: Date
        var sourceSessionId: UUID?
        var createdAt: Date
        var updatedAt: Date
    }

    struct TrainingPlanDTO: Codable {
        var id: UUID
        var name: String
        var programId: UUID?
        var startDate: Date
        var statusRaw: String
        var version: Int
        var notes: String
        var blocks: [TrainingBlockDTO]
        var createdAt: Date
        var updatedAt: Date
    }

    struct TrainingBlockDTO: Codable {
        var id: UUID
        var kindRaw: String
        var orderIndex: Int
        var name: String
        var rationale: String
        var weeks: [TrainingWeekDTO]
    }

    struct TrainingWeekDTO: Codable {
        var id: UUID
        var weekNumber: Int
        var startDate: Date
        var stateRaw: String
        var volumeTarget: [String: Int]
        var volumeMultiplier: Double
        var intensityMultiplier: Double
        var scheduledWorkouts: [ScheduledWorkoutDTO]
    }

    struct GoalDTO: Codable {
        var id: UUID
        var title: String
        var target: GoalTarget?
        var stateRaw: String
        var dueDate: Date?
        var startValue: Double?
        var notes: String
        var createdAt: Date
        var updatedAt: Date
    }

    struct AdaptationDTO: Codable {
        var id: UUID
        var createdAt: Date
        var sourceRaw: String
        var decisionRaw: String
        var decidedAt: Date?
        var prescribedExerciseId: UUID?
        var exerciseId: String
        var displayName: String
        var summary: String
        var factors: [String]
        var previousWeightKilograms: Double?
        var newWeightKilograms: Double?
        var previousRepsUpper: Int?
        var newRepsUpper: Int?
        var previousSets: Int?
        var newSets: Int?
        var previousPercentOneRepMax: Double?
        var newPercentOneRepMax: Double?
        var updatedAt: Date
    }

    struct ScheduledWorkoutDTO: Codable {
        var id: UUID
        var plannedDate: Date
        var programSessionId: UUID?
        var displayName: String
        var stateRaw: String
        var completedSessionId: UUID?
        var notes: String
    }

    struct ActiveWorkoutDTO: Codable {
        var id: UUID
        var startedAt: Date
        var programSessionId: UUID
        var exerciseIndex: Int
        var setIndex: Int
        var phaseRaw: String
        var runExercisesData: Data?
        var runtimeStateData: Data?
        var loggedSets: [CompletedSetDTO]
    }

    struct SettingsDTO: Codable {
        var soundEnabled: Bool
        var hapticsEnabled: Bool
        var defaultRestSeconds: Int
    }

    // MARK: - Resultat d'import

    struct ImportSummary: Sendable, Equatable {
        var programsCount: Int
        var sessionsCount: Int
        var recordsCount: Int
        var customExercisesCount: Int
        var hasActiveWorkout: Bool = false
        var measurementsCount: Int = 0
        var readinessEntriesCount: Int = 0
        var personalBestsCount: Int = 0
        var trainingPlansCount: Int = 0
        var hasProfile: Bool = false
        /// Version de l'archive lue, affichee dans l'apercu avant import.
        var sourceVersion: Int = ExportImport.currentVersion
    }

    // MARK: - Erreurs

    enum ImportError: LocalizedError, Equatable {
        case unsupportedVersion(Int)
        case malformedData(String)
        case invalidData(String)
        case fileTooLarge(Int)
        case checksumMismatch

        var errorDescription: String? {
            switch self {
            case .unsupportedVersion(let version):
                return String(localized: "Version de fichier non prise en charge (\(version)). Cette version de l'app attend la version \(ExportImport.currentVersion).")
            case .malformedData(let details):
                return String(localized: "Le fichier importé est illisible ou corrompu : \(details)")
            case .invalidData(let details):
                return String(localized: "Le fichier importé contient une valeur invalide : \(details)")
            case .fileTooLarge(let bytes):
                return String(localized: "Le fichier importé est trop volumineux (\(bytes) octets, maximum \(ExportImport.maximumImportBytes)).")
            case .checksumMismatch:
                return String(localized: "Le fichier importé est incomplet ou a été modifié : sa somme de contrôle ne correspond pas.")
            }
        }
    }

    // MARK: - Encodage

    /// Encodeur canonique : cles triees et dates ISO 8601, afin que la somme
    /// de controle du manifeste soit reproductible.
    private static func makeEncoder(prettyPrinted: Bool) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func checksum(of payloadData: Data) -> String {
        let digest = SHA256.hash(data: payloadData)
        return Manifest.checksumPrefix + digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func counts(of payload: Payload) -> [String: Int] {
        [
            "programs": payload.programs.count,
            "programSessions": payload.programs.reduce(0) { $0 + $1.sessions.count },
            "completedSessions": payload.sessions.count,
            "completedSets": payload.sessions.reduce(0) { $0 + $1.sets.count },
            "records": payload.records.count,
            "personalBests": payload.personalBests.count,
            "customExercises": payload.customExercises.count,
            "measurements": payload.measurements.count,
            "readinessEntries": payload.readinessEntries.count,
            "trainingPlans": payload.trainingPlans.count,
            "adaptations": payload.adaptations.count,
            "goals": payload.goals.count,
            "places": payload.places.count,
            "schedules": payload.schedules.count,
            "templates": payload.templates.count,
            "libraryEntries": payload.libraryEntries.count,
            "collections": payload.collections.count,
            "activeWorkouts": payload.activeWorkout == nil ? 0 : 1,
            "profiles": payload.profile == nil ? 0 : 1,
        ]
    }

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "inconnue"
    }

    // MARK: - Export

    static func exportAll(context: ModelContext) throws -> Data {
        let programs = try context.fetch(FetchDescriptor<Program>())
        let sessions = try context.fetch(FetchDescriptor<CompletedSession>())
        let records = try context.fetch(FetchDescriptor<ExerciseRecord>())
        let personalBests = try context.fetch(FetchDescriptor<PersonalBest>())
        let customExercises = try context.fetch(FetchDescriptor<CustomExercise>())
        let activeWorkout = try context.fetch(FetchDescriptor<ActiveWorkout>()).first
        let profile = try context.fetch(FetchDescriptor<AthleteProfile>()).first
        let measurements = try context.fetch(FetchDescriptor<BodyMeasurement>())
        let readinessEntries = try context.fetch(FetchDescriptor<ReadinessEntry>())
        let plans = try context.fetch(FetchDescriptor<TrainingPlan>())
        let adaptations = try context.fetch(FetchDescriptor<AdaptationEntry>())
        let goals = try context.fetch(FetchDescriptor<TrainingGoal>())
        let places = try context.fetch(FetchDescriptor<PlaceProfile>())
        let schedules = try context.fetch(FetchDescriptor<PlanningSchedule>())
        let templates = try context.fetch(FetchDescriptor<SessionTemplate>())
        let libraryEntries = try context.fetch(FetchDescriptor<ExerciseLibraryEntry>())
        let collections = try context.fetch(FetchDescriptor<ExerciseCollection>())

        let payload = Payload(
            programs: programs.map(Self.dto(from:)),
            sessions: sessions.map(Self.dto(from:)),
            records: records.map(Self.dto(from:)),
            customExercises: customExercises.map(Self.dto(from:)),
            activeWorkout: activeWorkout.map(Self.dto(from:)),
            settings: SettingsDTO(
                soundEnabled: FeedbackSettings.isSoundEnabled,
                hapticsEnabled: FeedbackSettings.isHapticsEnabled,
                defaultRestSeconds: Self.defaultRestSeconds
            ),
            profile: profile.map(Self.dto(from:)),
            measurements: measurements.map(Self.dto(from:)),
            readinessEntries: readinessEntries.map(Self.dto(from:)),
            personalBests: personalBests.map(Self.dto(from:)),
            trainingPlans: plans.map(Self.dto(from:)),
            adaptations: adaptations.map(Self.dto(from:)),
            goals: goals.map(Self.dto(from:)),
            places: places.map(Self.dto(from:)),
            schedules: schedules.map(Self.dto(from:)),
            templates: templates.map(Self.dto(from:)),
            libraryEntries: libraryEntries.map(Self.dto(from:)),
            collections: collections.map(Self.dto(from:))
        )

        // La somme de controle porte sur le payload encode de maniere
        // canonique, jamais sur l'enveloppe (qui contient le manifeste).
        let canonicalPayload = try makeEncoder(prettyPrinted: false).encode(payload)
        let envelope = Envelope(
            version: currentVersion,
            exportedAt: Date(),
            manifest: Manifest(
                schemaVersion: SyncMetadata.currentSchemaVersion,
                appVersion: appVersion,
                counts: counts(of: payload),
                checksum: checksum(of: canonicalPayload)
            ),
            payload: payload
        )

        return try makeEncoder(prettyPrinted: true).encode(envelope)
    }

    // MARK: - Import

    // Decode et valide l'integralite du JSON AVANT toute insertion dans le
    // contexte : en cas d'erreur (version incompatible ou JSON malforme),
    // aucune donnee n'est touchee. En cas de succes, fusion idempotente par
    // UUID (et par exerciseId pour les records), sans ecraser l'existant.
    // Au plus un programme importe peut devenir actif.
    @discardableResult
    static func importAll(data: Data, context: ModelContext) throws -> ImportSummary {
        let (envelope, sourceVersion) = try decodedPayload(from: data)

        var importedProgramsCount = 0
        var importedSessionsCount = 0
        var importedRecordsCount = 0
        var importedCustomExercisesCount = 0
        var importedActiveWorkout = false
        var importedMeasurementsCount = 0
        var importedReadinessCount = 0
        var importedPersonalBestsCount = 0
        var importedPlansCount = 0
        var importedProfile = false

        // Etape 3 : insertion, uniquement une fois tout valide.
        do {
            let existingPrograms = try context.fetch(FetchDescriptor<Program>())
            let existingProgramIds = Set(existingPrograms.map(\.id))
            var hasActiveProgram = existingPrograms.contains(where: \.isActive)
            for programDTO in envelope.programs where !existingProgramIds.contains(programDTO.id) {
                let program = model(from: programDTO)
                program.isActive = !hasActiveProgram && programDTO.isActive
                if program.isActive { hasActiveProgram = true }
                context.insert(program)
                importedProgramsCount += 1
            }
            let existingSessions = try context.fetch(FetchDescriptor<CompletedSession>())
            let existingSessionIds = Set(existingSessions.map(\.id))
            for sessionDTO in envelope.sessions where !existingSessionIds.contains(sessionDTO.id) {
                let session = model(from: sessionDTO)
                context.insert(session)
                importedSessionsCount += 1
            }
            // Fusion par exerciseId plutot qu'insertion aveugle : un import
            // repete (ou une base contenant deja des records) ne doit jamais
            // creer un second ExerciseRecord pour le meme exerciseId (cf.
            // RecordDetection qui suppose au plus un record par exercice).
            // On garde le max nil-safe de chaque valeur et le updatedAt le
            // plus recent.
            let existingRecords = try context.fetch(FetchDescriptor<ExerciseRecord>())
            var recordsByExerciseId = Dictionary(existingRecords.map { ($0.exerciseId, $0) }, uniquingKeysWith: { first, _ in first })
            for recordDTO in envelope.records {
                if let existing = recordsByExerciseId[recordDTO.exerciseId] {
                    let mergedOneRepMax = Self.maxNilSafe(existing.oneRepMax, recordDTO.oneRepMax)
                    let mergedMaxReps = Self.maxNilSafe(existing.maxReps, recordDTO.maxReps)
                    let mergedUpdatedAt = max(existing.updatedAt, recordDTO.updatedAt)
                    if existing.oneRepMax != mergedOneRepMax
                        || existing.maxReps != mergedMaxReps
                        || existing.updatedAt != mergedUpdatedAt {
                        existing.oneRepMax = mergedOneRepMax
                        existing.maxReps = mergedMaxReps
                        existing.updatedAt = mergedUpdatedAt
                        importedRecordsCount += 1
                    }
                } else {
                    let record = model(from: recordDTO)
                    context.insert(record)
                    recordsByExerciseId[recordDTO.exerciseId] = record
                    importedRecordsCount += 1
                }
            }
            let existingCustomExercises = try context.fetch(FetchDescriptor<CustomExercise>())
            let existingCustomIds = Set(existingCustomExercises.map(\.id))
            for customExerciseDTO in envelope.customExercises where !existingCustomIds.contains(customExerciseDTO.id) {
                let customExercise = model(from: customExerciseDTO)
                context.insert(customExercise)
                importedCustomExercisesCount += 1
            }

            let existingActive = try context.fetch(FetchDescriptor<ActiveWorkout>())
            if existingActive.isEmpty, let activeDTO = envelope.activeWorkout {
                context.insert(model(from: activeDTO))
                importedActiveWorkout = true
            }

            // --- Entites v3, toutes fusionnees par UUID (idempotent).

            // Un seul profil au plus : on n'ecrase jamais celui de l'appareil,
            // l'utilisateur devant rester maitre de ses reglages locaux.
            if try context.fetch(FetchDescriptor<AthleteProfile>()).isEmpty,
               let profileDTO = envelope.profile {
                context.insert(model(from: profileDTO))
                importedProfile = true
            }

            let existingMeasurementIds = Set(try context.fetch(FetchDescriptor<BodyMeasurement>()).map(\.id))
            for dto in envelope.measurements where !existingMeasurementIds.contains(dto.id) {
                context.insert(model(from: dto))
                importedMeasurementsCount += 1
            }

            let existingReadinessIds = Set(try context.fetch(FetchDescriptor<ReadinessEntry>()).map(\.id))
            for dto in envelope.readinessEntries where !existingReadinessIds.contains(dto.id) {
                context.insert(model(from: dto))
                importedReadinessCount += 1
            }

            // Records types : fusion par (exercice, nature, configuration)
            // en gardant la meilleure valeur, jamais un second enregistrement
            // pour la meme cle.
            let existingBests = try context.fetch(FetchDescriptor<PersonalBest>())
            var bestsByKey = Dictionary(existingBests.map { ($0.identityKey, $0) }, uniquingKeysWith: { first, _ in first })
            for dto in envelope.personalBests {
                let key = PersonalBest.identityKey(
                    exerciseId: dto.exerciseId,
                    kind: PersonalBestKind(rawValue: dto.kindRaw) ?? .maxWeight,
                    configurationKey: dto.configurationKey
                )
                if let existing = bestsByKey[key] {
                    guard existing.isImprovement(by: dto.value) else { continue }
                    existing.value = dto.value
                    existing.reps = dto.reps
                    existing.achievedAt = dto.achievedAt
                    existing.updatedAt = dto.updatedAt
                    importedPersonalBestsCount += 1
                } else {
                    let best = model(from: dto)
                    context.insert(best)
                    bestsByKey[key] = best
                    importedPersonalBestsCount += 1
                }
            }

            let existingPlanIds = Set(try context.fetch(FetchDescriptor<TrainingPlan>()).map(\.id))
            for dto in envelope.trainingPlans where !existingPlanIds.contains(dto.id) {
                context.insert(model(from: dto))
                importedPlansCount += 1
            }

            let existingAdaptationIds = Set(try context.fetch(FetchDescriptor<AdaptationEntry>()).map(\.id))
            for dto in envelope.adaptations where !existingAdaptationIds.contains(dto.id) {
                context.insert(model(from: dto))
            }

            let existingGoalIds = Set(try context.fetch(FetchDescriptor<TrainingGoal>()).map(\.id))
            for dto in envelope.goals where !existingGoalIds.contains(dto.id) {
                context.insert(model(from: dto))
            }

            let existingPlaceIds = Set(try context.fetch(FetchDescriptor<PlaceProfile>()).map(\.id))
            for dto in envelope.places where !existingPlaceIds.contains(dto.id) {
                context.insert(model(from: dto))
            }

            let existingScheduleIds = Set(try context.fetch(FetchDescriptor<PlanningSchedule>()).map(\.id))
            for dto in envelope.schedules where !existingScheduleIds.contains(dto.id) {
                context.insert(model(from: dto))
            }

            let existingTemplateIds = Set(try context.fetch(FetchDescriptor<SessionTemplate>()).map(\.id))
            for dto in envelope.templates where !existingTemplateIds.contains(dto.id) {
                context.insert(model(from: dto))
            }

            let existingLibraryIds = Set(try context.fetch(FetchDescriptor<ExerciseLibraryEntry>()).map(\.exerciseId))
            for dto in envelope.libraryEntries where !existingLibraryIds.contains(dto.exerciseId) {
                context.insert(model(from: dto))
            }

            let existingCollectionIds = Set(try context.fetch(FetchDescriptor<ExerciseCollection>()).map(\.id))
            for dto in envelope.collections where !existingCollectionIds.contains(dto.id) {
                context.insert(model(from: dto))
            }

            try context.save()

            // Les preferences ne font pas partie de la transaction SwiftData :
            // elles ne sont appliquees qu'apres la validation et le commit.
            if let settings = envelope.settings {
                UserDefaults.standard.set(settings.soundEnabled, forKey: "soundEnabled")
                UserDefaults.standard.set(settings.hapticsEnabled, forKey: "hapticsEnabled")
                UserDefaults.standard.set(settings.defaultRestSeconds, forKey: "defaultRestSeconds")
            }
        } catch {
            context.rollback()
            throw error
        }

        return ImportSummary(
            programsCount: importedProgramsCount,
            sessionsCount: importedSessionsCount,
            recordsCount: importedRecordsCount,
            customExercisesCount: importedCustomExercisesCount,
            hasActiveWorkout: importedActiveWorkout,
            measurementsCount: importedMeasurementsCount,
            readinessEntriesCount: importedReadinessCount,
            personalBestsCount: importedPersonalBestsCount,
            trainingPlansCount: importedPlansCount,
            hasProfile: importedProfile,
            sourceVersion: sourceVersion
        )
    }

    /// Decode et valide sans modifier SwiftData, pour afficher un apercu
    /// explicite avant que l'utilisateur confirme l'import.
    static func preview(data: Data) throws -> ImportSummary {
        let (envelope, sourceVersion) = try decodedPayload(from: data)
        return ImportSummary(
            programsCount: envelope.programs.count,
            sessionsCount: envelope.sessions.count,
            recordsCount: envelope.records.count,
            customExercisesCount: envelope.customExercises.count,
            hasActiveWorkout: envelope.activeWorkout != nil,
            measurementsCount: envelope.measurements.count,
            readinessEntriesCount: envelope.readinessEntries.count,
            personalBestsCount: envelope.personalBests.count,
            trainingPlansCount: envelope.trainingPlans.count,
            hasProfile: envelope.profile != nil,
            sourceVersion: sourceVersion
        )
    }

    /// Decode et valide une archive SANS toucher au store. Retourne le
    /// contenu et la version d'origine, pour que l'appelant puisse informer
    /// l'utilisateur avant toute mutation.
    private static func decodedPayload(from data: Data) throws -> (payload: Payload, version: Int) {
        guard data.count <= maximumImportBytes else {
            throw ImportError.fileTooLarge(data.count)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Etape 1 : verification de la version sans decoder le reste, pour
        // un message d'erreur precis meme si la structure a change.
        struct VersionProbe: Codable { var version: Int }
        let probe: VersionProbe
        do {
            probe = try decoder.decode(VersionProbe.self, from: data)
        } catch {
            throw ImportError.malformedData(error.localizedDescription)
        }
        guard (1...currentVersion).contains(probe.version) else {
            throw ImportError.unsupportedVersion(probe.version)
        }

        // Etape 2 : decodage complet et strict. Si cette etape echoue, rien
        // n'a ete touche dans le contexte.
        let payload: Payload
        do {
            if probe.version >= 3 {
                let envelope = try decoder.decode(Envelope.self, from: data)
                try verifyChecksum(of: envelope)
                payload = envelope.payload
            } else {
                payload = try decoder.decode(LegacyEnvelope.self, from: data).payload
            }
        } catch let error as ImportError {
            throw error
        } catch {
            throw ImportError.malformedData(error.localizedDescription)
        }

        try validate(payload)
        return (payload, probe.version)
    }

    /// Verifie que le payload recu correspond a l'empreinte du manifeste.
    /// Un manifeste sans empreinte reconnue est refuse plutot qu'ignore.
    private static func verifyChecksum(of envelope: Envelope) throws {
        guard envelope.manifest.checksum.hasPrefix(Manifest.checksumPrefix) else {
            throw ImportError.invalidData("somme de contrôle absente du manifeste")
        }
        let canonical = try makeEncoder(prettyPrinted: false).encode(envelope.payload)
        guard checksum(of: canonical) == envelope.manifest.checksum else {
            throw ImportError.checksumMismatch
        }
        let expected = counts(of: envelope.payload)
        for (key, value) in envelope.manifest.counts where expected[key] != value {
            throw ImportError.invalidData("le manifeste annonce \(value) « \(key) » mais l’archive en contient \(expected[key] ?? 0)")
        }
    }

    private static var defaultRestSeconds: Int {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: "defaultRestSeconds") == nil ? 90 : defaults.integer(forKey: "defaultRestSeconds")
    }

    // MARK: - Fusion nil-safe

    private static func maxNilSafe<T: Comparable>(_ lhs: T?, _ rhs: T?) -> T? {
        switch (lhs, rhs) {
        case (nil, nil): return nil
        case (let value, nil): return value
        case (nil, let value): return value
        case (let a?, let b?): return max(a, b)
        }
    }

    // MARK: - Mapping modele -> DTO

    static func dto(from program: Program) -> ProgramDTO {
        ProgramDTO(
            id: program.id,
            name: program.name,
            notes: program.notes,
            isActive: program.isActive,
            createdAt: program.createdAt,
            sessions: program.sessions
                .sorted { $0.orderIndex < $1.orderIndex }
                .map(Self.dto(from:))
        )
    }

    static func dto(from session: ProgramSession) -> SessionDTO {
        SessionDTO(
            id: session.id,
            name: session.name,
            orderIndex: session.orderIndex,
            warmupEnabled: session.warmupEnabled,
            exercises: session.orderedExercises.map(Self.dto(from:)),
            groups: session.orderedGroups.map(Self.dto(from:))
        )
    }

    static func dto(from group: ExerciseGroup) -> GroupDTO {
        GroupDTO(
            id: group.id,
            kindRaw: group.kindRaw,
            orderIndex: group.orderIndex,
            rounds: group.rounds,
            restBetweenExercisesSeconds: group.restBetweenExercisesSeconds,
            restBetweenRoundsSeconds: group.restBetweenRoundsSeconds,
            transitionSeconds: group.transitionSeconds,
            requiresManualStationValidation: group.requiresManualStationValidation,
            notes: group.notes
        )
    }

    static func dto(from exercise: PrescribedExercise) -> ExerciseDTO {
        ExerciseDTO(
            id: exercise.id,
            exerciseId: exercise.exerciseId,
            displayName: exercise.displayName,
            orderIndex: exercise.orderIndex,
            formatRaw: exercise.formatRaw,
            sets: exercise.sets,
            repsLower: exercise.repsLower,
            repsUpper: exercise.repsUpper,
            restSeconds: exercise.restSeconds,
            percentOneRepMax: exercise.percentOneRepMax,
            percentMaxReps: exercise.percentMaxReps,
            targetWeight: exercise.targetWeight,
            pyramidReps: exercise.pyramidReps,
            pyramidMinRest: exercise.pyramidMinRest,
            pyramidMaxRest: exercise.pyramidMaxRest,
            intervalWork: exercise.intervalWork,
            intervalRest: exercise.intervalRest,
            intervalRounds: exercise.intervalRounds,
            amrapSeconds: exercise.amrapSeconds,
            notes: exercise.notes,
            groupId: exercise.group?.id,
            groupOrderIndex: exercise.groupOrderIndex,
            tempoNotation: exercise.tempoNotation.isEmpty ? nil : exercise.tempoNotation,
            targetEffort: exercise.targetEffort,
            progressionRule: exercise.progressionRule,
            loadKindRaw: exercise.loadKindRaw.isEmpty ? nil : exercise.loadKindRaw,
            sideConventionRaw: exercise.sideConventionRaw,
            targetDurationSeconds: exercise.targetDurationSeconds,
            targetDistanceMeters: exercise.targetDistanceMeters
        )
    }

    static func dto(from session: CompletedSession) -> CompletedSessionDTO {
        CompletedSessionDTO(
            id: session.id,
            date: session.date,
            programId: session.programId,
            programSessionId: session.programSessionId,
            programName: session.programName,
            sessionName: session.sessionName,
            durationSeconds: session.durationSeconds,
            sets: session.orderedSets.map(Self.dto(from:)),
            notes: session.notes.isEmpty ? nil : session.notes,
            scheduledWorkoutId: session.scheduledWorkoutId,
            readinessEntryId: session.readinessEntryId,
            bodyweightKilograms: session.bodyweightKilograms,
            revision: session.revision,
            effortRating: session.effortRating,
            avgHeartRate: session.avgHeartRate,
            maxHeartRate: session.maxHeartRate,
            minHeartRate: session.minHeartRate,
            activeEnergyKcal: session.activeEnergyKcal,
            editedAt: session.editedAt
        )
    }

    static func dto(from set: CompletedSet) -> CompletedSetDTO {
        CompletedSetDTO(
            id: set.id,
            exerciseId: set.exerciseId,
            displayName: set.displayName,
            orderIndex: set.orderIndex,
            setIndex: set.setIndex,
            weight: set.weight,
            reps: set.reps,
            isWarmup: set.isWarmup,
            loadTypeRaw: set.loadTypeRaw,
            roleRaw: set.roleRaw.isEmpty ? nil : set.roleRaw,
            sideConventionRaw: set.sideConventionRaw,
            tempoNotation: set.tempoNotation.isEmpty ? nil : set.tempoNotation,
            effort: set.effort,
            notes: set.notes.isEmpty ? nil : set.notes,
            reachedFailure: set.reachedFailure,
            groupId: set.groupId,
            roundIndex: set.roundIndex,
            subSetIndex: set.subSetIndex,
            durationSeconds: set.durationSeconds,
            distanceMeters: set.distanceMeters,
            calories: set.calories,
            plannedExerciseId: set.plannedExerciseId.isEmpty ? nil : set.plannedExerciseId,
            formatRaw: set.formatRaw,
            sequenceIndex: set.sequenceIndex,
            actualRestSeconds: set.actualRestSeconds
        )
    }

    static func dto(from record: ExerciseRecord) -> RecordDTO {
        RecordDTO(
            id: record.id,
            exerciseId: record.exerciseId,
            displayName: record.displayName,
            oneRepMax: record.oneRepMax,
            maxReps: record.maxReps,
            updatedAt: record.updatedAt
        )
    }

    static func dto(from customExercise: CustomExercise) -> CustomExerciseDTO {
        CustomExerciseDTO(
            id: customExercise.id,
            name: customExercise.name,
            primaryMuscles: customExercise.primaryMuscles,
            equipment: customExercise.equipment,
            notes: customExercise.notes,
            secondaryMuscles: customExercise.secondaryMuscles,
            movementPattern: customExercise.movementPattern.isEmpty ? nil : customExercise.movementPattern,
            defaultLoadKindRaw: customExercise.defaultLoadKindRaw,
            isUnilateral: customExercise.isUnilateral,
            tags: customExercise.tags,
            isFavorite: customExercise.isFavorite,
            mergedIntoExerciseId: customExercise.mergedIntoExerciseId
        )
    }

    static func dto(from profile: AthleteProfile) -> ProfileDTO {
        ProfileDTO(
            id: profile.id,
            firstName: profile.firstName,
            birthDate: profile.birthDate,
            heightCentimeters: profile.heightCentimeters,
            bodyweightKilograms: profile.bodyweightKilograms,
            massUnitRaw: profile.massUnitRaw,
            lengthUnitRaw: profile.lengthUnitRaw,
            availableIncrementsKilograms: profile.availableIncrementsKilograms,
            experienceRaw: profile.experienceRaw,
            primaryGoalRaw: profile.primaryGoalRaw,
            secondaryGoalsRaw: profile.secondaryGoalsRaw,
            availableWeekdays: profile.availableWeekdays,
            sessionMinutesMinimum: profile.sessionMinutesMinimum,
            sessionMinutesMaximum: profile.sessionMinutesMaximum,
            equipmentRaw: profile.equipmentRaw,
            priorityMuscles: profile.priorityMuscles,
            excludedExerciseIds: profile.excludedExerciseIds,
            avoidAreas: profile.avoidAreas,
            weeklyFrequencyByMuscle: profile.weeklyFrequencyByMuscle,
            defaultProgressionRule: profile.defaultProgressionRule,
            createdAt: profile.createdAt,
            updatedAt: profile.updatedAt
        )
    }

    static func dto(from measurement: BodyMeasurement) -> BodyMeasurementDTO {
        BodyMeasurementDTO(
            id: measurement.id,
            kindRaw: measurement.kindRaw,
            customName: measurement.customName,
            measuredAt: measurement.measuredAt,
            value: measurement.value,
            sourceRaw: measurement.sourceRaw,
            notes: measurement.notes,
            createdAt: measurement.createdAt,
            updatedAt: measurement.updatedAt,
            healthSampleUUID: measurement.healthSampleUUID
        )
    }

    static func dto(from entry: ReadinessEntry) -> ReadinessEntryDTO {
        ReadinessEntryDTO(
            id: entry.id,
            recordedAt: entry.recordedAt,
            energy: entry.energy,
            sleepQuality: entry.sleepQuality,
            soreness: entry.soreness,
            stress: entry.stress,
            painIntensity: entry.painIntensity,
            painArea: entry.painArea,
            notes: entry.notes,
            programSessionId: entry.programSessionId,
            createdAt: entry.createdAt,
            updatedAt: entry.updatedAt
        )
    }

    static func dto(from best: PersonalBest) -> PersonalBestDTO {
        PersonalBestDTO(
            id: best.id,
            exerciseId: best.exerciseId,
            displayName: best.displayName,
            kindRaw: best.kindRaw,
            configurationKey: best.configurationKey,
            value: best.value,
            reps: best.reps,
            achievedAt: best.achievedAt,
            sourceSessionId: best.sourceSessionId,
            createdAt: best.createdAt,
            updatedAt: best.updatedAt
        )
    }

    static func dto(from plan: TrainingPlan) -> TrainingPlanDTO {
        TrainingPlanDTO(
            id: plan.id,
            name: plan.name,
            programId: plan.programId,
            startDate: plan.startDate,
            statusRaw: plan.statusRaw,
            version: plan.version,
            notes: plan.notes,
            blocks: plan.orderedBlocks.map(Self.dto(from:)),
            createdAt: plan.createdAt,
            updatedAt: plan.updatedAt
        )
    }

    static func dto(from block: TrainingBlock) -> TrainingBlockDTO {
        TrainingBlockDTO(
            id: block.id,
            kindRaw: block.kindRaw,
            orderIndex: block.orderIndex,
            name: block.name,
            rationale: block.rationale,
            weeks: block.orderedWeeks.map(Self.dto(from:))
        )
    }

    static func dto(from week: TrainingWeek) -> TrainingWeekDTO {
        TrainingWeekDTO(
            id: week.id,
            weekNumber: week.weekNumber,
            startDate: week.startDate,
            stateRaw: week.stateRaw,
            volumeTarget: week.volumeTarget,
            volumeMultiplier: week.volumeMultiplier,
            intensityMultiplier: week.intensityMultiplier,
            scheduledWorkouts: week.orderedWorkouts.map(Self.dto(from:))
        )
    }

    static func dto(from goal: TrainingGoal) -> GoalDTO {
        GoalDTO(
            id: goal.id,
            title: goal.title,
            target: goal.target,
            stateRaw: goal.stateRaw,
            dueDate: goal.dueDate,
            startValue: goal.startValue,
            notes: goal.notes,
            createdAt: goal.createdAt,
            updatedAt: goal.updatedAt
        )
    }

    static func dto(from entry: AdaptationEntry) -> AdaptationDTO {
        AdaptationDTO(
            id: entry.id,
            createdAt: entry.createdAt,
            sourceRaw: entry.sourceRaw,
            decisionRaw: entry.decisionRaw,
            decidedAt: entry.decidedAt,
            prescribedExerciseId: entry.prescribedExerciseId,
            exerciseId: entry.exerciseId,
            displayName: entry.displayName,
            summary: entry.summary,
            factors: entry.factors,
            previousWeightKilograms: entry.previousWeightKilograms,
            newWeightKilograms: entry.newWeightKilograms,
            previousRepsUpper: entry.previousRepsUpper,
            newRepsUpper: entry.newRepsUpper,
            previousSets: entry.previousSets,
            newSets: entry.newSets,
            previousPercentOneRepMax: entry.previousPercentOneRepMax,
            newPercentOneRepMax: entry.newPercentOneRepMax,
            updatedAt: entry.updatedAt
        )
    }

    static func dto(from workout: ScheduledWorkout) -> ScheduledWorkoutDTO {
        ScheduledWorkoutDTO(
            id: workout.id,
            plannedDate: workout.plannedDate,
            programSessionId: workout.programSessionId,
            displayName: workout.displayName,
            stateRaw: workout.stateRaw,
            completedSessionId: workout.completedSessionId,
            notes: workout.notes
        )
    }

    static func dto(from workout: ActiveWorkout) -> ActiveWorkoutDTO {
        ActiveWorkoutDTO(
            id: workout.id,
            startedAt: workout.startedAt,
            programSessionId: workout.programSessionId,
            exerciseIndex: workout.exerciseIndex,
            setIndex: workout.setIndex,
            phaseRaw: workout.phaseRaw,
            runExercisesData: workout.runExercisesData,
            runtimeStateData: workout.runtimeStateData,
            loggedSets: workout.loggedSets.sorted {
                ($0.orderIndex, $0.setIndex) < ($1.orderIndex, $1.setIndex)
            }.map(Self.dto(from:))
        )
    }

    // MARK: - Mapping DTO -> modele (UUID preserves, fusion idempotente)

    static func model(from dto: ProgramDTO) -> Program {
        let program = Program(
            id: dto.id,
            name: dto.name,
            notes: dto.notes,
            isActive: false,
            createdAt: dto.createdAt
        )
        program.sessions = dto.sessions.map { sessionDTO -> ProgramSession in
            let session = model(from: sessionDTO)
            session.program = program
            return session
        }
        return program
    }

    static func model(from dto: SessionDTO) -> ProgramSession {
        let session = ProgramSession(
            id: dto.id,
            name: dto.name,
            orderIndex: dto.orderIndex,
            warmupEnabled: dto.warmupEnabled
        )
        let exercises = dto.exercises.map { exerciseDTO -> PrescribedExercise in
            let exercise = model(from: exerciseDTO)
            exercise.session = session
            return exercise
        }
        session.exercises = exercises

        // Les groupes sont recrees puis relies par identifiant : un groupe
        // dont aucun exercice n'existe reste vide plutot que de rattacher un
        // exercice au hasard.
        let groups = (dto.groups ?? []).map { groupDTO -> ExerciseGroup in
            let group = model(from: groupDTO)
            group.session = session
            return group
        }
        session.groups = groups
        let groupsById = Dictionary(groups.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for (exercise, exerciseDTO) in zip(exercises, dto.exercises) {
            guard let groupId = exerciseDTO.groupId, let group = groupsById[groupId] else { continue }
            exercise.group = group
        }
        return session
    }

    static func model(from dto: GroupDTO) -> ExerciseGroup {
        ExerciseGroup(
            id: dto.id,
            kindRaw: dto.kindRaw,
            orderIndex: dto.orderIndex,
            rounds: dto.rounds,
            restBetweenExercisesSeconds: dto.restBetweenExercisesSeconds,
            restBetweenRoundsSeconds: dto.restBetweenRoundsSeconds,
            transitionSeconds: dto.transitionSeconds,
            requiresManualStationValidation: dto.requiresManualStationValidation,
            notes: dto.notes
        )
    }

    static func model(from dto: ExerciseDTO) -> PrescribedExercise {
        PrescribedExercise(
            id: dto.id,
            exerciseId: dto.exerciseId,
            displayName: dto.displayName,
            orderIndex: dto.orderIndex,
            formatRaw: dto.formatRaw,
            sets: dto.sets,
            repsLower: dto.repsLower,
            repsUpper: dto.repsUpper,
            restSeconds: dto.restSeconds,
            percentOneRepMax: dto.percentOneRepMax,
            percentMaxReps: dto.percentMaxReps,
            targetWeight: dto.targetWeight,
            pyramidReps: dto.pyramidReps,
            pyramidMinRest: dto.pyramidMinRest,
            pyramidMaxRest: dto.pyramidMaxRest,
            intervalWork: dto.intervalWork,
            intervalRest: dto.intervalRest,
            intervalRounds: dto.intervalRounds,
            amrapSeconds: dto.amrapSeconds,
            notes: dto.notes,
            groupOrderIndex: dto.groupOrderIndex ?? 0,
            tempoNotation: dto.tempoNotation ?? "",
            targetEffortData: dto.targetEffort.flatMap { try? JSONEncoder().encode($0) },
            progressionRuleData: dto.progressionRule.flatMap { try? JSONEncoder().encode($0) },
            loadKindRaw: dto.loadKindRaw ?? "",
            sideConventionRaw: dto.sideConventionRaw ?? SideConvention.bilateral.rawValue,
            targetDurationSeconds: dto.targetDurationSeconds ?? 0,
            targetDistanceMeters: dto.targetDistanceMeters ?? 0
        )
    }

    static func model(from dto: CompletedSessionDTO) -> CompletedSession {
        let session = CompletedSession(
            id: dto.id,
            date: dto.date,
            programId: dto.programId,
            programSessionId: dto.programSessionId,
            programName: dto.programName,
            sessionName: dto.sessionName,
            durationSeconds: dto.durationSeconds,
            notes: dto.notes ?? "",
            scheduledWorkoutId: dto.scheduledWorkoutId,
            readinessEntryId: dto.readinessEntryId,
            bodyweightKilograms: dto.bodyweightKilograms,
            revision: dto.revision ?? 1,
            effortRating: dto.effortRating,
            avgHeartRate: dto.avgHeartRate,
            maxHeartRate: dto.maxHeartRate,
            minHeartRate: dto.minHeartRate,
            activeEnergyKcal: dto.activeEnergyKcal,
            editedAt: dto.editedAt
        )
        session.sets = dto.sets.map { setDTO -> CompletedSet in
            let set = model(from: setDTO)
            set.session = session
            return set
        }
        return session
    }

    static func model(from dto: CompletedSetDTO) -> CompletedSet {
        CompletedSet(
            id: dto.id,
            exerciseId: dto.exerciseId,
            displayName: dto.displayName,
            orderIndex: dto.orderIndex,
            setIndex: dto.setIndex,
            weight: dto.weight,
            reps: dto.reps,
            isWarmup: dto.isWarmup,
            loadTypeRaw: dto.loadTypeRaw ?? ExerciseLoadType.unknown.rawValue,
            roleRaw: dto.roleRaw ?? "",
            sideConventionRaw: dto.sideConventionRaw ?? SideConvention.bilateral.rawValue,
            tempoNotation: dto.tempoNotation ?? "",
            effortData: dto.effort.flatMap { try? JSONEncoder().encode($0) },
            notes: dto.notes ?? "",
            reachedFailure: dto.reachedFailure ?? false,
            groupId: dto.groupId,
            roundIndex: dto.roundIndex ?? 0,
            subSetIndex: dto.subSetIndex ?? 0,
            durationSeconds: dto.durationSeconds,
            distanceMeters: dto.distanceMeters,
            calories: dto.calories,
            plannedExerciseId: dto.plannedExerciseId ?? "",
            formatRaw: dto.formatRaw ?? SetFormat.classic.rawValue,
            sequenceIndex: dto.sequenceIndex ?? 0,
            actualRestSeconds: dto.actualRestSeconds
        )
    }

    static func model(from dto: RecordDTO) -> ExerciseRecord {
        ExerciseRecord(
            id: dto.id,
            exerciseId: dto.exerciseId,
            displayName: dto.displayName,
            oneRepMax: dto.oneRepMax,
            maxReps: dto.maxReps,
            updatedAt: dto.updatedAt
        )
    }

    static func model(from dto: CustomExerciseDTO) -> CustomExercise {
        CustomExercise(
            id: dto.id,
            name: dto.name,
            primaryMuscles: dto.primaryMuscles,
            equipment: dto.equipment,
            notes: dto.notes,
            secondaryMuscles: dto.secondaryMuscles ?? [],
            movementPattern: dto.movementPattern ?? "",
            defaultLoadKindRaw: dto.defaultLoadKindRaw ?? LoadKind.external.rawValue,
            isUnilateral: dto.isUnilateral ?? false,
            tags: dto.tags ?? [],
            isFavorite: dto.isFavorite ?? false,
            mergedIntoExerciseId: dto.mergedIntoExerciseId
        )
    }

    static func model(from dto: ProfileDTO) -> AthleteProfile {
        AthleteProfile(
            id: dto.id,
            firstName: dto.firstName,
            birthDate: dto.birthDate,
            heightCentimeters: dto.heightCentimeters,
            bodyweightKilograms: dto.bodyweightKilograms,
            massUnitRaw: dto.massUnitRaw,
            lengthUnitRaw: dto.lengthUnitRaw,
            availableIncrementsKilograms: dto.availableIncrementsKilograms,
            experienceRaw: dto.experienceRaw,
            primaryGoalRaw: dto.primaryGoalRaw,
            secondaryGoalsRaw: dto.secondaryGoalsRaw,
            availableWeekdays: dto.availableWeekdays,
            sessionMinutesMinimum: dto.sessionMinutesMinimum,
            sessionMinutesMaximum: dto.sessionMinutesMaximum,
            equipmentRaw: dto.equipmentRaw,
            priorityMuscles: dto.priorityMuscles,
            excludedExerciseIds: dto.excludedExerciseIds,
            avoidAreas: dto.avoidAreas,
            weeklyFrequencyByMuscleData: try? JSONEncoder().encode(dto.weeklyFrequencyByMuscle),
            defaultProgressionRuleData: dto.defaultProgressionRule.flatMap { try? JSONEncoder().encode($0) },
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }

    static func model(from dto: BodyMeasurementDTO) -> BodyMeasurement {
        BodyMeasurement(
            id: dto.id,
            kindRaw: dto.kindRaw,
            customName: dto.customName,
            measuredAt: dto.measuredAt,
            value: dto.value,
            sourceRaw: dto.sourceRaw,
            notes: dto.notes,
            healthSampleUUID: dto.healthSampleUUID,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }

    static func model(from dto: ReadinessEntryDTO) -> ReadinessEntry {
        ReadinessEntry(
            id: dto.id,
            recordedAt: dto.recordedAt,
            energy: dto.energy,
            sleepQuality: dto.sleepQuality,
            soreness: dto.soreness,
            stress: dto.stress,
            painIntensity: dto.painIntensity,
            painArea: dto.painArea,
            notes: dto.notes,
            programSessionId: dto.programSessionId,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }

    static func model(from dto: PersonalBestDTO) -> PersonalBest {
        PersonalBest(
            id: dto.id,
            exerciseId: dto.exerciseId,
            displayName: dto.displayName,
            kindRaw: dto.kindRaw,
            configurationKey: dto.configurationKey,
            value: dto.value,
            reps: dto.reps,
            achievedAt: dto.achievedAt,
            sourceSessionId: dto.sourceSessionId,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }

    static func model(from dto: GoalDTO) -> TrainingGoal {
        TrainingGoal(
            id: dto.id,
            title: dto.title,
            targetData: dto.target.flatMap { try? JSONEncoder().encode($0) },
            stateRaw: dto.stateRaw,
            dueDate: dto.dueDate,
            startValue: dto.startValue,
            notes: dto.notes,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }

    static func model(from dto: AdaptationDTO) -> AdaptationEntry {
        AdaptationEntry(
            id: dto.id,
            createdAt: dto.createdAt,
            sourceRaw: dto.sourceRaw,
            decisionRaw: dto.decisionRaw,
            decidedAt: dto.decidedAt,
            prescribedExerciseId: dto.prescribedExerciseId,
            exerciseId: dto.exerciseId,
            displayName: dto.displayName,
            summary: dto.summary,
            factors: dto.factors,
            previousWeightKilograms: dto.previousWeightKilograms,
            newWeightKilograms: dto.newWeightKilograms,
            previousRepsUpper: dto.previousRepsUpper,
            newRepsUpper: dto.newRepsUpper,
            previousSets: dto.previousSets,
            newSets: dto.newSets,
            previousPercentOneRepMax: dto.previousPercentOneRepMax,
            newPercentOneRepMax: dto.newPercentOneRepMax,
            updatedAt: dto.updatedAt
        )
    }

    static func model(from dto: TrainingPlanDTO) -> TrainingPlan {
        let plan = TrainingPlan(
            id: dto.id,
            name: dto.name,
            programId: dto.programId,
            startDate: dto.startDate,
            statusRaw: dto.statusRaw,
            version: dto.version,
            notes: dto.notes,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
        plan.blocks = dto.blocks.map { blockDTO in
            let block = TrainingBlock(
                id: blockDTO.id,
                kindRaw: blockDTO.kindRaw,
                orderIndex: blockDTO.orderIndex,
                name: blockDTO.name,
                rationale: blockDTO.rationale
            )
            block.plan = plan
            block.weeks = blockDTO.weeks.map { weekDTO in
                let week = TrainingWeek(
                    id: weekDTO.id,
                    weekNumber: weekDTO.weekNumber,
                    startDate: weekDTO.startDate,
                    stateRaw: weekDTO.stateRaw,
                    volumeTargetData: try? JSONEncoder().encode(weekDTO.volumeTarget),
                    volumeMultiplier: weekDTO.volumeMultiplier,
                    intensityMultiplier: weekDTO.intensityMultiplier
                )
                week.block = block
                week.scheduledWorkouts = weekDTO.scheduledWorkouts.map { workoutDTO in
                    let workout = ScheduledWorkout(
                        id: workoutDTO.id,
                        plannedDate: workoutDTO.plannedDate,
                        programSessionId: workoutDTO.programSessionId,
                        displayName: workoutDTO.displayName,
                        stateRaw: workoutDTO.stateRaw,
                        completedSessionId: workoutDTO.completedSessionId,
                        notes: workoutDTO.notes
                    )
                    workout.week = week
                    return workout
                }
                return week
            }
            return block
        }
        return plan
    }

    static func model(from dto: ActiveWorkoutDTO) -> ActiveWorkout {
        let workout = ActiveWorkout(
            id: dto.id,
            startedAt: dto.startedAt,
            programSessionId: dto.programSessionId,
            exerciseIndex: dto.exerciseIndex,
            setIndex: dto.setIndex,
            phaseRaw: dto.phaseRaw,
            runExercisesData: dto.runExercisesData,
            runtimeStateData: dto.runtimeStateData
        )
        workout.loggedSets = dto.loggedSets.map { setDTO in
            let set = model(from: setDTO)
            set.activeWorkout = workout
            return set
        }
        return workout
    }

    // MARK: - Validation semantique

    private static func validate(_ envelope: Payload) throws {
        guard envelope.programs.count <= 500,
              envelope.sessions.count <= 10_000,
              envelope.records.count <= 5_000,
              envelope.customExercises.count <= 5_000,
              envelope.measurements.count <= 50_000,
              envelope.readinessEntries.count <= 50_000,
              envelope.personalBests.count <= 20_000,
              envelope.trainingPlans.count <= 200 else {
            throw ImportError.invalidData("le nombre d’éléments dépasse les limites de sécurité")
        }

        try requireUnique(envelope.programs.map(\.id), label: "identifiants de programmes")
        try requireUnique(envelope.sessions.map(\.id), label: "identifiants d’historique")
        try requireUnique(envelope.records.map(\.exerciseId), label: "records par exercice")
        try requireUnique(envelope.customExercises.map(\.id), label: "identifiants d’exercices personnalisés")

        for program in envelope.programs {
            try validateText(program.name, label: "nom de programme", maximum: 200, allowEmpty: false)
            try validateText(program.notes, label: "notes de programme", maximum: 10_000)
            guard program.sessions.count <= 50 else { throw ImportError.invalidData("trop de séances dans un programme") }
            try requireUnique(program.sessions.map(\.id), label: "identifiants de séances")
            for session in program.sessions {
                try validateText(session.name, label: "nom de séance", maximum: 200, allowEmpty: false)
                guard (0...1_000).contains(session.orderIndex), session.exercises.count <= 200 else {
                    throw ImportError.invalidData("ordre ou nombre d’exercices invalide")
                }
                try requireUnique(session.exercises.map(\.id), label: "identifiants de prescriptions")
                for exercise in session.exercises { try validate(exercise) }

                let groups = session.groups ?? []
                guard groups.count <= 100 else { throw ImportError.invalidData("trop de groupes dans une séance") }
                try requireUnique(groups.map(\.id), label: "identifiants de groupes")
                let groupIds = Set(groups.map(\.id))
                for group in groups {
                    guard ExerciseGroupKind(rawValue: group.kindRaw) != nil,
                          (1...100).contains(group.rounds),
                          (0...86_400).contains(group.restBetweenExercisesSeconds),
                          (0...86_400).contains(group.restBetweenRoundsSeconds),
                          (0...86_400).contains(group.transitionSeconds),
                          (0...1_000).contains(group.orderIndex) else {
                        throw ImportError.invalidData("groupe d’exercices hors limites")
                    }
                    try validateText(group.notes, label: "notes de groupe", maximum: 2_000)
                }
                for exercise in session.exercises {
                    guard let groupId = exercise.groupId else { continue }
                    guard groupIds.contains(groupId) else {
                        throw ImportError.invalidData("un exercice référence un groupe inexistant")
                    }
                }
            }
        }

        for session in envelope.sessions {
            try validateText(session.programName, label: "nom de programme historique", maximum: 200)
            try validateText(session.sessionName, label: "nom de séance historique", maximum: 200)
            guard (0...604_800).contains(session.durationSeconds), session.sets.count <= 10_000 else {
                throw ImportError.invalidData("durée ou nombre de séries d’une séance invalide")
            }
            for set in session.sets { try validate(set) }
            try validateVersionSevenFields(of: session)
        }

        for record in envelope.records {
            try validateText(record.exerciseId, label: "identifiant de record", maximum: 500, allowEmpty: false)
            try validateText(record.displayName, label: "nom de record", maximum: 500, allowEmpty: false)
            if let value = record.oneRepMax, !value.isFinite || !(0...10_000).contains(value) {
                throw ImportError.invalidData("1RM hors limites")
            }
            if let value = record.maxReps, !(0...100_000).contains(value) {
                throw ImportError.invalidData("maximum de répétitions hors limites")
            }
            if record.oneRepMax == nil && record.maxReps == nil {
                throw ImportError.invalidData("un record ne contient aucune valeur")
            }
        }

        for exercise in envelope.customExercises {
            try validateText(exercise.name, label: "nom d’exercice personnalisé", maximum: 200, allowEmpty: false)
            try validateText(exercise.equipment, label: "équipement", maximum: 200)
            try validateText(exercise.notes, label: "notes d’exercice", maximum: 10_000)
            guard exercise.primaryMuscles.count <= 50 else { throw ImportError.invalidData("trop de muscles") }
            if let target = exercise.mergedIntoExerciseId {
                try validateText(target, label: "exercice de fusion", maximum: 500, allowEmpty: false)
                guard target != exercise.id.uuidString else {
                    throw ImportError.invalidData("exercice fusionné avec lui-même")
                }
            }
        }

        if let active = envelope.activeWorkout {
            let availableSessionIds = Set(envelope.programs.flatMap(\.sessions).map(\.id))
            guard (0...10_000).contains(active.exerciseIndex),
                  (0...10_000).contains(active.setIndex),
                  ["warmup", "running"].contains(active.phaseRaw),
                  active.loggedSets.count <= 10_000,
                  (active.runExercisesData?.count ?? 0) <= 5 * 1_024 * 1_024,
                  (active.runtimeStateData?.count ?? 0) <= 1 * 1_024 * 1_024,
                  availableSessionIds.contains(active.programSessionId) else {
                throw ImportError.invalidData("séance active invalide")
            }
            for set in active.loggedSets { try validate(set) }
        }

        if let settings = envelope.settings, !(15...300).contains(settings.defaultRestSeconds) {
            throw ImportError.invalidData("repos par défaut hors limites")
        }

        try validateVersionThreeEntities(envelope)
        try validateVersionFourEntities(envelope)
    }

    // MARK: - Validation des entites v4

    /// Meme exigence que pour les entites v3 : un fichier invalide est
    /// refuse AVANT toute ecriture, et jamais partiellement applique.
    private static func validateVersionFourEntities(_ envelope: Payload) throws {
        try requireUnique(envelope.places.map(\.id), label: "identifiants de lieux")
        try requireUnique(envelope.schedules.map(\.id), label: "identifiants de récurrences")
        try requireUnique(envelope.templates.map(\.id), label: "identifiants de modèles")
        try requireUnique(envelope.collections.map(\.id), label: "identifiants de collections")
        try requireUnique(envelope.libraryEntries.map(\.exerciseId), label: "identifiants d’annotations")

        guard envelope.places.count <= 200 else {
            throw ImportError.invalidData("le nombre de lieux dépasse les limites de sécurité")
        }
        for place in envelope.places {
            guard PlaceKind(rawValue: place.kindRaw) != nil else {
                throw ImportError.invalidData("type de lieu inconnu")
            }
            try validateText(place.name, label: "nom de lieu", maximum: 200)
            try validateText(place.notes, label: "notes de lieu", maximum: 2_000)
            guard place.inventory.count <= 200 else {
                throw ImportError.invalidData("inventaire de lieu trop volumineux")
            }
            for item in place.inventory {
                try validateText(item.equipmentId, label: "matériel", maximum: 100, allowEmpty: false)
                for value in [item.minimumLoad, item.maximumLoad, item.increment].compactMap({ $0 }) {
                    guard value.isFinite, (0...10_000).contains(value) else {
                        throw ImportError.invalidData("charge de matériel hors limites")
                    }
                }
            }
        }

        guard envelope.schedules.count <= 200 else {
            throw ImportError.invalidData("le nombre de récurrences dépasse les limites de sécurité")
        }
        for schedule in envelope.schedules {
            try validateText(schedule.name, label: "nom de récurrence", maximum: 200)
            guard schedule.weekdays.allSatisfy({ (1...7).contains($0) }) else {
                throw ImportError.invalidData("jour de semaine invalide")
            }
            guard (0...23).contains(schedule.hour), (0...59).contains(schedule.minute) else {
                throw ImportError.invalidData("heure de récurrence invalide")
            }
            guard (0...1_440).contains(schedule.reminderLeadMinutes),
                  (0...365).contains(schedule.reminderComebackAfterDays),
                  schedule.pausedWeekOffsets.count <= 520 else {
                throw ImportError.invalidData("réglage de rappel hors limites")
            }
            if let endDate = schedule.endDate, endDate < schedule.startDate {
                throw ImportError.invalidData("récurrence dont la fin précède le début")
            }
        }

        guard envelope.templates.count <= 2_000 else {
            throw ImportError.invalidData("le nombre de modèles dépasse les limites de sécurité")
        }
        for template in envelope.templates {
            guard TemplateScope(rawValue: template.scopeRaw) != nil else {
                throw ImportError.invalidData("portée de modèle inconnue")
            }
            try validateText(template.name, label: "nom de modèle", maximum: 200)
            try validateText(template.notes, label: "notes de modèle", maximum: 2_000)
            guard (template.payload?.sessions.count ?? 0) <= 100 else {
                throw ImportError.invalidData("modèle trop volumineux")
            }
        }

        guard envelope.libraryEntries.count <= 20_000 else {
            throw ImportError.invalidData("le nombre d’annotations dépasse les limites de sécurité")
        }
        for entry in envelope.libraryEntries {
            try validateText(entry.exerciseId, label: "identifiant d’exercice", maximum: 500, allowEmpty: false)
            guard entry.tags.count <= 50 else { throw ImportError.invalidData("trop de tags") }
            for tag in entry.tags { try validateText(tag, label: "tag", maximum: 100, allowEmpty: false) }
            if let link = entry.demoURL, !link.isEmpty {
                guard DemoLink.isAcceptable(link) else {
                    throw ImportError.invalidData("lien de démonstration invalide")
                }
            }
        }

        guard envelope.collections.count <= 500 else {
            throw ImportError.invalidData("le nombre de collections dépasse les limites de sécurité")
        }
        for collection in envelope.collections {
            try validateText(collection.name, label: "nom de collection", maximum: 200)
            try validateText(collection.notes, label: "notes de collection", maximum: 2_000)
            guard collection.exerciseIds.count <= 2_000 else {
                throw ImportError.invalidData("collection trop volumineuse")
            }
        }
    }

    // MARK: - Validation des entites v3

    private static func validateVersionThreeEntities(_ envelope: Payload) throws {
        try requireUnique(envelope.measurements.map(\.id), label: "identifiants de mesures")
        try requireUnique(envelope.readinessEntries.map(\.id), label: "identifiants de check-in")
        try requireUnique(envelope.personalBests.map(\.id), label: "identifiants de records typés")
        try requireUnique(envelope.trainingPlans.map(\.id), label: "identifiants de plans")
        try requireUnique(envelope.adaptations.map(\.id), label: "identifiants d’adaptations")
        try requireUnique(envelope.goals.map(\.id), label: "identifiants d’objectifs")
        guard envelope.goals.count <= 1_000 else {
            throw ImportError.invalidData("le nombre d’objectifs dépasse les limites de sécurité")
        }
        for goal in envelope.goals {
            guard GoalState(rawValue: goal.stateRaw) != nil else {
                throw ImportError.invalidData("état d’objectif inconnu")
            }
            if let target = goal.target, !target.isWithinSaneBounds {
                throw ImportError.invalidData("objectif hors bornes")
            }
            try validateText(goal.title, label: "titre d’objectif", maximum: 200)
            try validateText(goal.notes, label: "notes d’objectif", maximum: 2_000)
        }
        guard envelope.adaptations.count <= 50_000 else {
            throw ImportError.invalidData("le nombre d’adaptations dépasse les limites de sécurité")
        }
        for adaptation in envelope.adaptations {
            guard AdaptationSource(rawValue: adaptation.sourceRaw) != nil,
                  AdaptationDecision(rawValue: adaptation.decisionRaw) != nil,
                  adaptation.factors.count <= 50 else {
                throw ImportError.invalidData("adaptation invalide")
            }
            try validateText(adaptation.summary, label: "résumé d’adaptation", maximum: 500)
            try validateText(adaptation.displayName, label: "nom d’exercice adapté", maximum: 500)
        }

        if let profile = envelope.profile {
            try validateText(profile.firstName, label: "prénom", maximum: 100)
            if let height = profile.heightCentimeters, !height.isFinite || !(30...280).contains(height) {
                throw ImportError.invalidData("taille hors limites")
            }
            if let weight = profile.bodyweightKilograms, !weight.isFinite || !(20...500).contains(weight) {
                throw ImportError.invalidData("poids de corps hors limites")
            }
            guard MassUnit(rawValue: profile.massUnitRaw) != nil,
                  LengthUnit(rawValue: profile.lengthUnitRaw) != nil,
                  profile.sessionMinutesMinimum >= 0,
                  profile.sessionMinutesMinimum <= profile.sessionMinutesMaximum,
                  profile.sessionMinutesMaximum <= 600,
                  profile.availableWeekdays.allSatisfy({ (1...7).contains($0) }),
                  profile.availableIncrementsKilograms.allSatisfy({ $0.isFinite && (0.1...50).contains($0) }),
                  profile.availableIncrementsKilograms.count <= 20,
                  profile.priorityMuscles.count <= 50,
                  profile.avoidAreas.count <= 50,
                  profile.excludedExerciseIds.count <= 5_000 else {
                throw ImportError.invalidData("profil hors limites")
            }
            if let rule = profile.defaultProgressionRule, !rule.isValid {
                throw ImportError.invalidData("règle de progression du profil invalide")
            }
        }

        for measurement in envelope.measurements {
            guard BodyMeasurementKind(rawValue: measurement.kindRaw) != nil,
                  MeasurementSource(rawValue: measurement.sourceRaw) != nil,
                  measurement.value.isFinite,
                  (-1_000...100_000).contains(measurement.value) else {
                throw ImportError.invalidData("mesure corporelle hors limites")
            }
            try validateText(measurement.customName, label: "nom de mesure", maximum: 100)
            try validateText(measurement.healthSampleUUID ?? "", label: "identifiant d’échantillon Santé", maximum: 100)
            try validateText(measurement.notes, label: "notes de mesure", maximum: 2_000)
        }

        for entry in envelope.readinessEntries {
            for value in [entry.energy, entry.sleepQuality, entry.soreness, entry.stress].compactMap({ $0 })
            where !(1...5).contains(value) {
                throw ImportError.invalidData("valeur de check-in hors échelle")
            }
            if let pain = entry.painIntensity, !(0...10).contains(pain) {
                throw ImportError.invalidData("intensité de douleur hors échelle")
            }
            try validateText(entry.painArea, label: "zone de douleur", maximum: 100)
            try validateText(entry.notes, label: "notes de check-in", maximum: 2_000)
        }

        for best in envelope.personalBests {
            guard PersonalBestKind(rawValue: best.kindRaw) != nil,
                  best.value.isFinite,
                  (0...1_000_000).contains(best.value) else {
                throw ImportError.invalidData("record typé hors limites")
            }
            try validateText(best.exerciseId, label: "identifiant de record typé", maximum: 500, allowEmpty: false)
            try validateText(best.configurationKey, label: "configuration de record", maximum: 200)
            if let reps = best.reps, !(0...100_000).contains(reps) {
                throw ImportError.invalidData("répétitions de record hors limites")
            }
        }

        for plan in envelope.trainingPlans {
            try validateText(plan.name, label: "nom de plan", maximum: 200, allowEmpty: false)
            try validateText(plan.notes, label: "notes de plan", maximum: 10_000)
            guard TrainingPlanStatus(rawValue: plan.statusRaw) != nil,
                  (1...1_000).contains(plan.version),
                  plan.blocks.count <= 50 else {
                throw ImportError.invalidData("plan hors limites")
            }
            try requireUnique(plan.blocks.map(\.id), label: "identifiants de blocs")
            for block in plan.blocks {
                guard TrainingBlockKind(rawValue: block.kindRaw) != nil, block.weeks.count <= 100 else {
                    throw ImportError.invalidData("bloc hors limites")
                }
                try requireUnique(block.weeks.map(\.id), label: "identifiants de semaines")
                for week in block.weeks {
                    guard TrainingWeekState(rawValue: week.stateRaw) != nil,
                          (1...520).contains(week.weekNumber),
                          week.volumeMultiplier.isFinite, (0...5).contains(week.volumeMultiplier),
                          week.intensityMultiplier.isFinite, (0...5).contains(week.intensityMultiplier),
                          week.scheduledWorkouts.count <= 50 else {
                        throw ImportError.invalidData("semaine hors limites")
                    }
                    for workout in week.scheduledWorkouts {
                        guard ScheduledWorkoutState(rawValue: workout.stateRaw) != nil else {
                            throw ImportError.invalidData("état de séance planifiée inconnu")
                        }
                        try validateText(workout.displayName, label: "nom de séance planifiée", maximum: 200)
                        try validateText(workout.notes, label: "notes de séance planifiée", maximum: 2_000)
                    }
                }
            }
        }
    }

    private static func validate(_ exercise: ExerciseDTO) throws {
        try validateText(exercise.exerciseId, label: "identifiant d’exercice", maximum: 500, allowEmpty: false)
        try validateText(exercise.displayName, label: "nom d’exercice", maximum: 500, allowEmpty: false)
        try validateText(exercise.notes, label: "notes de prescription", maximum: 10_000)
        guard SetFormat(rawValue: exercise.formatRaw) != nil,
              (0...1_000).contains(exercise.orderIndex),
              (0...100).contains(exercise.sets),
              (0...100_000).contains(exercise.repsLower),
              (0...100_000).contains(exercise.repsUpper),
              exercise.repsLower <= exercise.repsUpper,
              (0...86_400).contains(exercise.restSeconds),
              exercise.pyramidReps.count <= 100,
              exercise.pyramidReps.allSatisfy({ (1...100_000).contains($0) }),
              (0...86_400).contains(exercise.pyramidMinRest),
              (0...86_400).contains(exercise.pyramidMaxRest),
              exercise.pyramidMinRest <= exercise.pyramidMaxRest,
              (0...86_400).contains(exercise.intervalWork),
              (0...86_400).contains(exercise.intervalRest),
              (0...1_000).contains(exercise.intervalRounds),
              (0...86_400).contains(exercise.amrapSeconds) else {
            throw ImportError.invalidData("prescription hors limites pour \(exercise.displayName)")
        }
        for percent in [exercise.percentOneRepMax, exercise.percentMaxReps].compactMap({ $0 }) {
            guard percent.isFinite, (0...100).contains(percent) else { throw ImportError.invalidData("pourcentage hors limites") }
        }
        if let weight = exercise.targetWeight, !weight.isFinite || !(0...10_000).contains(weight) {
            throw ImportError.invalidData("charge cible hors limites")
        }
        if let notation = exercise.tempoNotation, !notation.isEmpty, Tempo(notation: notation) == nil {
            throw ImportError.invalidData("tempo invalide pour \(exercise.displayName)")
        }
        if let effort = exercise.targetEffort, !effort.isValid {
            throw ImportError.invalidData("effort cible invalide pour \(exercise.displayName)")
        }
        if let rule = exercise.progressionRule, !rule.isValid {
            throw ImportError.invalidData("règle de progression invalide pour \(exercise.displayName)")
        }
        if let raw = exercise.loadKindRaw, !raw.isEmpty, LoadKind(rawValue: raw) == nil {
            throw ImportError.invalidData("type de charge inconnu pour \(exercise.displayName)")
        }
        if let raw = exercise.sideConventionRaw, SideConvention(rawValue: raw) == nil {
            throw ImportError.invalidData("convention unilatérale inconnue pour \(exercise.displayName)")
        }
        guard (0...86_400).contains(exercise.targetDurationSeconds ?? 0),
              (exercise.targetDistanceMeters ?? 0).isFinite,
              (0...1_000_000).contains(exercise.targetDistanceMeters ?? 0),
              (0...1_000).contains(exercise.groupOrderIndex ?? 0) else {
            throw ImportError.invalidData("cible de durée, distance ou position de groupe hors limites")
        }
    }

    private static func validate(_ set: CompletedSetDTO) throws {
        try validateText(set.exerciseId, label: "identifiant de série", maximum: 500, allowEmpty: false)
        try validateText(set.displayName, label: "nom de série", maximum: 500, allowEmpty: false)
        guard (0...10_000).contains(set.orderIndex),
              (0...10_000).contains(set.setIndex),
              set.weight.isFinite,
              (0...10_000).contains(set.weight),
              (0...100_000).contains(set.reps),
              set.loadTypeRaw.map({ ExerciseLoadType(rawValue: $0) != nil }) ?? true,
              set.roleRaw.map({ $0.isEmpty || SetRole(rawValue: $0) != nil }) ?? true,
              set.sideConventionRaw.map({ SideConvention(rawValue: $0) != nil }) ?? true,
              set.formatRaw.map({ SetFormat(rawValue: $0) != nil }) ?? true,
              (0...100_000).contains(set.sequenceIndex ?? 0),
              (0...10_000).contains(set.roundIndex ?? 0),
              (0...10_000).contains(set.subSetIndex ?? 0),
              (0...86_400).contains(set.durationSeconds ?? 0),
              (set.distanceMeters ?? 0).isFinite,
              (0...1_000_000).contains(set.distanceMeters ?? 0),
              (set.calories ?? 0).isFinite,
              (0...100_000).contains(set.calories ?? 0),
              (0...86_400).contains(set.actualRestSeconds ?? 0) else {
            throw ImportError.invalidData("série hors limites")
        }
        if let notation = set.tempoNotation, !notation.isEmpty, Tempo(notation: notation) == nil {
            throw ImportError.invalidData("tempo de série invalide")
        }
        if let effort = set.effort, !effort.isValid {
            throw ImportError.invalidData("effort de série invalide")
        }
        try validateText(set.notes ?? "", label: "notes de série", maximum: 2_000)
    }

    /// Champs ajoutes avec le schema v7. Absents = non renseignes ; presents,
    /// ils doivent rester plausibles : une frequence cardiaque de 0 ou une
    /// note d'effort de 11 trahit une archive alteree.
    private static func validateVersionSevenFields(of session: CompletedSessionDTO) throws {
        if let rating = session.effortRating, !(1...10).contains(rating) {
            throw ImportError.invalidData("note d’effort hors échelle")
        }
        for value in [session.avgHeartRate, session.maxHeartRate, session.minHeartRate].compactMap({ $0 })
        where !value.isFinite || !(20...300).contains(value) {
            throw ImportError.invalidData("fréquence cardiaque hors limites")
        }
        if let energy = session.activeEnergyKcal, !energy.isFinite || !(0...100_000).contains(energy) {
            throw ImportError.invalidData("énergie active hors limites")
        }
    }

    private static func validateText(_ value: String, label: String, maximum: Int, allowEmpty: Bool = true) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count <= maximum, allowEmpty || !trimmed.isEmpty else {
            throw ImportError.invalidData("\(label) vide ou trop long")
        }
    }

    private static func requireUnique<T: Hashable>(_ values: [T], label: String) throws {
        guard Set(values).count == values.count else { throw ImportError.invalidData("\(label) en doublon") }
    }
}
