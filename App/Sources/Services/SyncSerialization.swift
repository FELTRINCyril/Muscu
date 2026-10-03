import Foundation
import SwiftData
import MuscuEngine

/// Convertit les entités SwiftData en enregistrements synchronisables, et
/// inversement.
///
/// Les charges utiles réutilisent **exactement** les DTO de l'export v3 :
/// un seul format décrit une entité, qu'elle parte dans une sauvegarde ou
/// vers iCloud. Deux formats divergeraient tôt ou tard.
@MainActor
enum SyncSerialization {
    /// Encodeur canonique : clés triées et dates ISO 8601, pour que deux
    /// encodages du même contenu soient identiques octet pour octet. C'est
    /// ce qui permet de détecter « rien n'a changé ».
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    // MARK: - Lecture

    /// Tous les enregistrements locaux, indexés par identifiant.
    static func localRecords(context: ModelContext) throws -> [UUID: SyncRecord] {
        var result: [UUID: SyncRecord] = [:]
        let encoder = encoder()

        /// `comparableValue` n'est renseignee que pour les entites dont la
        /// fusion se fait au MAXIMUM : sans elle, un record distant plus
        /// recent mais inferieur ecraserait un meilleur record local.
        func add<Model, DTO: Encodable>(
            _ kind: SyncEntityKind,
            _ models: [Model],
            metadata: (Model) -> SyncMetadata,
            dto: (Model) -> DTO,
            comparableValue: ((Model) -> Double?)? = nil
        ) throws {
            for model in models {
                let meta = metadata(model)
                result[meta.identifier] = SyncRecord(
                    kind: kind,
                    metadata: meta,
                    payload: try encoder.encode(dto(model)),
                    comparableValue: comparableValue?(model)
                )
            }
        }

        try add(.program, context.fetch(FetchDescriptor<Program>()), metadata: \.syncMetadata, dto: ExportImport.dto(from:))
        try add(.completedSession, context.fetch(FetchDescriptor<CompletedSession>()), metadata: \.syncMetadata, dto: syncDTO(from:))
        try add(.activeWorkout, context.fetch(FetchDescriptor<ActiveWorkout>()), metadata: \.syncMetadata, dto: ExportImport.dto(from:))
        // Un `ExerciseRecord` porte deux performances distinctes (1RM et max
        // de repetitions). On compare la plus structurante, le 1RM, en
        // retombant sur le max de repetitions quand il n'y a pas de 1RM.
        try add(
            .exerciseRecord,
            context.fetch(FetchDescriptor<ExerciseRecord>()),
            metadata: \.syncMetadata,
            dto: ExportImport.dto(from:),
            comparableValue: { $0.oneRepMax ?? $0.maxReps.map(Double.init) }
        )
        // Un record de TEMPS s'ameliore en diminuant : on compare son oppose
        // pour que « le plus grand gagne » reste vrai.
        try add(
            .personalBest,
            context.fetch(FetchDescriptor<PersonalBest>()),
            metadata: \.syncMetadata,
            dto: ExportImport.dto(from:),
            comparableValue: { $0.kind.lowerIsBetter ? -$0.value : $0.value }
        )
        try add(.customExercise, context.fetch(FetchDescriptor<CustomExercise>()), metadata: \.syncMetadata, dto: ExportImport.dto(from:))
        try add(.athleteProfile, context.fetch(FetchDescriptor<AthleteProfile>()), metadata: \.syncMetadata, dto: ExportImport.dto(from:))
        try add(.bodyMeasurement, context.fetch(FetchDescriptor<BodyMeasurement>()), metadata: \.syncMetadata, dto: ExportImport.dto(from:))
        try add(.readinessEntry, context.fetch(FetchDescriptor<ReadinessEntry>()), metadata: \.syncMetadata, dto: ExportImport.dto(from:))
        try add(.trainingPlan, context.fetch(FetchDescriptor<TrainingPlan>()), metadata: \.syncMetadata, dto: ExportImport.dto(from:))
        try add(.trainingGoal, context.fetch(FetchDescriptor<TrainingGoal>()), metadata: \.syncMetadata, dto: ExportImport.dto(from:))
        try add(.adaptationEntry, context.fetch(FetchDescriptor<AdaptationEntry>()), metadata: \.syncMetadata, dto: ExportImport.dto(from:))

        return result
    }

    /// Charge utile synchronisée d'une séance : le DTO d'export, SANS les
    /// mesures issues de Santé (fréquence cardiaque, énergie active).
    ///
    /// Les règles d'Apple interdisent de stocker dans iCloud des données
    /// de santé lues dans HealthKit. Ces valeurs restent donc sur l'appareil
    /// qui les a mesurées — et dans l'export JSON, déclenché explicitement
    /// par l'utilisateur. La note d'effort, saisie dans Muscu, voyage.
    static func syncDTO(from session: CompletedSession) -> ExportImport.CompletedSessionDTO {
        var dto = ExportImport.dto(from: session)
        dto.avgHeartRate = nil
        dto.maxHeartRate = nil
        dto.minHeartRate = nil
        dto.activeEnergyKcal = nil
        return dto
    }

    // MARK: - Écriture

    enum SerializationError: LocalizedError {
        case unsupportedKind(SyncEntityKind)

        var errorDescription: String? {
            switch self {
            case .unsupportedKind(let kind):
                return String(localized: "Type d’entité non pris en charge par la synchronisation : \(kind.rawValue).")
            }
        }
    }

    /// Applique un enregistrement distant : l'agrégat local de même
    /// identifiant est remplacé en entier.
    ///
    /// Remplacer plutôt que fusionner champ par champ est volontaire : un
    /// programme est édité comme un tout, et une fusion partielle
    /// produirait des états impossibles (une séance sans ses exercices).
    /// L'opération est idempotente.
    static func apply(_ record: SyncRecord, into context: ModelContext) throws {
        let decoder = decoder()

        // Un tombstone supprime localement, sans rien recréer.
        guard !record.isDeleted else {
            try deleteLocal(kind: record.kind, identifier: record.identifier, context: context)
            return
        }

        // Les mesures Santé ne voyagent pas (voir `syncDTO`) : remplacer la
        // séance locale par la version distante ne doit pas les effacer.
        let preservedHealth = record.kind == .completedSession
            ? try localHealthMeasures(of: record.identifier, context: context)
            : nil

        try deleteLocal(kind: record.kind, identifier: record.identifier, context: context)

        switch record.kind {
        case .program:
            let dto = try decoder.decode(ExportImport.ProgramDTO.self, from: record.payload)
            let program = ExportImport.model(from: dto)
            // Un seul programme actif : un appareil distant ne doit pas
            // pouvoir en activer un second en silence.
            let hasActive = try context.fetch(FetchDescriptor<Program>()).contains { $0.isActive }
            program.isActive = dto.isActive && !hasActive
            context.insert(program)

        case .completedSession:
            let session = ExportImport.model(from: try decoder.decode(ExportImport.CompletedSessionDTO.self, from: record.payload))
            if let preservedHealth {
                session.avgHeartRate = session.avgHeartRate ?? preservedHealth.avgHeartRate
                session.maxHeartRate = session.maxHeartRate ?? preservedHealth.maxHeartRate
                session.minHeartRate = session.minHeartRate ?? preservedHealth.minHeartRate
                session.activeEnergyKcal = session.activeEnergyKcal ?? preservedHealth.activeEnergyKcal
            }
            context.insert(session)
        case .activeWorkout:
            context.insert(ExportImport.model(from: try decoder.decode(ExportImport.ActiveWorkoutDTO.self, from: record.payload)))
        case .exerciseRecord:
            context.insert(ExportImport.model(from: try decoder.decode(ExportImport.RecordDTO.self, from: record.payload)))
        case .personalBest:
            context.insert(ExportImport.model(from: try decoder.decode(ExportImport.PersonalBestDTO.self, from: record.payload)))
        case .customExercise:
            context.insert(ExportImport.model(from: try decoder.decode(ExportImport.CustomExerciseDTO.self, from: record.payload)))
        case .athleteProfile:
            context.insert(ExportImport.model(from: try decoder.decode(ExportImport.ProfileDTO.self, from: record.payload)))
        case .bodyMeasurement:
            context.insert(ExportImport.model(from: try decoder.decode(ExportImport.BodyMeasurementDTO.self, from: record.payload)))
        case .readinessEntry:
            context.insert(ExportImport.model(from: try decoder.decode(ExportImport.ReadinessEntryDTO.self, from: record.payload)))
        case .trainingPlan:
            context.insert(ExportImport.model(from: try decoder.decode(ExportImport.TrainingPlanDTO.self, from: record.payload)))
        case .trainingGoal:
            context.insert(ExportImport.model(from: try decoder.decode(ExportImport.GoalDTO.self, from: record.payload)))
        case .adaptationEntry:
            context.insert(ExportImport.model(from: try decoder.decode(ExportImport.AdaptationDTO.self, from: record.payload)))
        case .healthWorkoutLink:
            throw SerializationError.unsupportedKind(.healthWorkoutLink)
        }
    }

    private struct HealthMeasures {
        var avgHeartRate: Double?
        var maxHeartRate: Double?
        var minHeartRate: Double?
        var activeEnergyKcal: Double?
    }

    private static func localHealthMeasures(of identifier: UUID, context: ModelContext) throws -> HealthMeasures? {
        let descriptor = FetchDescriptor<CompletedSession>(predicate: #Predicate { $0.id == identifier })
        guard let session = try context.fetch(descriptor).first else { return nil }
        return HealthMeasures(
            avgHeartRate: session.avgHeartRate,
            maxHeartRate: session.maxHeartRate,
            minHeartRate: session.minHeartRate,
            activeEnergyKcal: session.activeEnergyKcal
        )
    }

    /// Supprime l'agrégat local portant cet identifiant, s'il existe. Les
    /// enfants partent en cascade avec leur parent.
    private static func deleteLocal(kind: SyncEntityKind, identifier: UUID, context: ModelContext) throws {
        switch kind {
        case .program:
            try delete(Program.self, identifier, context)
        case .completedSession:
            try delete(CompletedSession.self, identifier, context)
        case .activeWorkout:
            try delete(ActiveWorkout.self, identifier, context)
        case .exerciseRecord:
            try delete(ExerciseRecord.self, identifier, context)
        case .personalBest:
            try delete(PersonalBest.self, identifier, context)
        case .customExercise:
            try delete(CustomExercise.self, identifier, context)
        case .athleteProfile:
            try delete(AthleteProfile.self, identifier, context)
        case .bodyMeasurement:
            try delete(BodyMeasurement.self, identifier, context)
        case .readinessEntry:
            try delete(ReadinessEntry.self, identifier, context)
        case .trainingPlan:
            try delete(TrainingPlan.self, identifier, context)
        case .trainingGoal:
            try delete(TrainingGoal.self, identifier, context)
        case .adaptationEntry:
            try delete(AdaptationEntry.self, identifier, context)
        case .healthWorkoutLink:
            try delete(HealthWorkoutLink.self, identifier, context)
        }
    }

    private static func delete<T: PersistentModel & SyncIdentifiable>(
        _ type: T.Type,
        _ identifier: UUID,
        _ context: ModelContext
    ) throws {
        let existing = try context.fetch(FetchDescriptor<T>()).filter { $0.syncIdentifier == identifier }
        for item in existing { context.delete(item) }
    }
}

/// Entité portant un identifiant stable de synchronisation.
protocol SyncIdentifiable {
    var syncIdentifier: UUID { get }
}

extension Program: SyncIdentifiable { var syncIdentifier: UUID { id } }
extension CompletedSession: SyncIdentifiable { var syncIdentifier: UUID { id } }
extension ActiveWorkout: SyncIdentifiable { var syncIdentifier: UUID { id } }
extension ExerciseRecord: SyncIdentifiable { var syncIdentifier: UUID { id } }
extension PersonalBest: SyncIdentifiable { var syncIdentifier: UUID { id } }
extension CustomExercise: SyncIdentifiable { var syncIdentifier: UUID { id } }
extension AthleteProfile: SyncIdentifiable { var syncIdentifier: UUID { id } }
extension BodyMeasurement: SyncIdentifiable { var syncIdentifier: UUID { id } }
extension ReadinessEntry: SyncIdentifiable { var syncIdentifier: UUID { id } }
extension TrainingPlan: SyncIdentifiable { var syncIdentifier: UUID { id } }
extension TrainingGoal: SyncIdentifiable { var syncIdentifier: UUID { id } }
extension AdaptationEntry: SyncIdentifiable { var syncIdentifier: UUID { id } }
extension HealthWorkoutLink: SyncIdentifiable { var syncIdentifier: UUID { id } }
