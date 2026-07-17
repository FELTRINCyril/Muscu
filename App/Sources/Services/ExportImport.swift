import Foundation
import SwiftData

// Export/import complet des donnees utilisateur au format JSON versionne.
// Les modeles @Model ne sont pas rendus Codable directement (SwiftData ne
// le supporte pas proprement pour les relations) : on passe par des DTO
// Codable dedies, mappes explicitement dans les deux sens.
enum ExportImport {
    static let currentVersion = 1

    // MARK: - Enveloppe

    struct Envelope: Codable {
        var version: Int
        var exportedAt: Date
        var programs: [ProgramDTO]
        var sessions: [CompletedSessionDTO]
        var records: [RecordDTO]
        var customExercises: [CustomExerciseDTO]
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
        var pyramidReps: [Int]
        var pyramidMinRest: Int
        var pyramidMaxRest: Int
        var intervalWork: Int
        var intervalRest: Int
        var intervalRounds: Int
        var amrapSeconds: Int
        var notes: String
    }

    // MARK: - DTO Historique

    struct CompletedSessionDTO: Codable {
        var id: UUID
        var date: Date
        var programName: String
        var sessionName: String
        var durationSeconds: Int
        var sets: [CompletedSetDTO]
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
    }

    // MARK: - Resultat d'import

    struct ImportSummary {
        var programsCount: Int
        var sessionsCount: Int
        var recordsCount: Int
        var customExercisesCount: Int
    }

    // MARK: - Erreurs

    enum ImportError: LocalizedError {
        case unsupportedVersion(Int)
        case malformedData(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedVersion(let version):
                return "Version de fichier non prise en charge (\(version)). Cette version de l'app attend la version \(ExportImport.currentVersion)."
            case .malformedData(let details):
                return "Le fichier importé est illisible ou corrompu : \(details)"
            }
        }
    }

    // MARK: - Export

    static func exportAll(context: ModelContext) throws -> Data {
        let programs = try context.fetch(FetchDescriptor<Program>())
        let sessions = try context.fetch(FetchDescriptor<CompletedSession>())
        let records = try context.fetch(FetchDescriptor<ExerciseRecord>())
        let customExercises = try context.fetch(FetchDescriptor<CustomExercise>())

        let envelope = Envelope(
            version: currentVersion,
            exportedAt: Date(),
            programs: programs.map(Self.dto(from:)),
            sessions: sessions.map(Self.dto(from:)),
            records: records.map(Self.dto(from:)),
            customExercises: customExercises.map(Self.dto(from:))
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(envelope)
    }

    // MARK: - Import

    // Decode et valide l'integralite du JSON AVANT toute insertion dans le
    // contexte : en cas d'erreur (version incompatible ou JSON malforme),
    // aucune donnee n'est touchee. En cas de succes, fusion additive : tous
    // les elements sont inseres avec de nouvelles UUID, sans jamais ecraser
    // l'existant. Les programmes importes sont toujours inactifs.
    @discardableResult
    static func importAll(data: Data, context: ModelContext) throws -> ImportSummary {
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
        guard probe.version == currentVersion else {
            throw ImportError.unsupportedVersion(probe.version)
        }

        // Etape 2 : decodage complet et strict de l'enveloppe. Si cette
        // etape echoue, rien n'a ete touche dans le contexte.
        let envelope: Envelope
        do {
            envelope = try decoder.decode(Envelope.self, from: data)
        } catch {
            throw ImportError.malformedData(error.localizedDescription)
        }

        // Etape 3 : insertion, uniquement une fois tout valide.
        do {
            for programDTO in envelope.programs {
                let program = model(from: programDTO)
                context.insert(program)
            }
            for sessionDTO in envelope.sessions {
                let session = model(from: sessionDTO)
                context.insert(session)
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
                    existing.oneRepMax = Self.maxNilSafe(existing.oneRepMax, recordDTO.oneRepMax)
                    existing.maxReps = Self.maxNilSafe(existing.maxReps, recordDTO.maxReps)
                    existing.updatedAt = max(existing.updatedAt, recordDTO.updatedAt)
                } else {
                    let record = model(from: recordDTO)
                    context.insert(record)
                    recordsByExerciseId[recordDTO.exerciseId] = record
                }
            }
            for customExerciseDTO in envelope.customExercises {
                let customExercise = model(from: customExerciseDTO)
                context.insert(customExercise)
            }

            try context.save()
        } catch {
            context.rollback()
            throw error
        }

        return ImportSummary(
            programsCount: envelope.programs.count,
            sessionsCount: envelope.sessions.count,
            recordsCount: envelope.records.count,
            customExercisesCount: envelope.customExercises.count
        )
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

    private static func dto(from program: Program) -> ProgramDTO {
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

    private static func dto(from session: ProgramSession) -> SessionDTO {
        SessionDTO(
            id: session.id,
            name: session.name,
            orderIndex: session.orderIndex,
            warmupEnabled: session.warmupEnabled,
            exercises: session.exercises
                .sorted { $0.orderIndex < $1.orderIndex }
                .map(Self.dto(from:))
        )
    }

    private static func dto(from exercise: PrescribedExercise) -> ExerciseDTO {
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
            pyramidReps: exercise.pyramidReps,
            pyramidMinRest: exercise.pyramidMinRest,
            pyramidMaxRest: exercise.pyramidMaxRest,
            intervalWork: exercise.intervalWork,
            intervalRest: exercise.intervalRest,
            intervalRounds: exercise.intervalRounds,
            amrapSeconds: exercise.amrapSeconds,
            notes: exercise.notes
        )
    }

    private static func dto(from session: CompletedSession) -> CompletedSessionDTO {
        CompletedSessionDTO(
            id: session.id,
            date: session.date,
            programName: session.programName,
            sessionName: session.sessionName,
            durationSeconds: session.durationSeconds,
            sets: session.sets
                .sorted { $0.orderIndex < $1.orderIndex }
                .map(Self.dto(from:))
        )
    }

    private static func dto(from set: CompletedSet) -> CompletedSetDTO {
        CompletedSetDTO(
            id: set.id,
            exerciseId: set.exerciseId,
            displayName: set.displayName,
            orderIndex: set.orderIndex,
            setIndex: set.setIndex,
            weight: set.weight,
            reps: set.reps,
            isWarmup: set.isWarmup
        )
    }

    private static func dto(from record: ExerciseRecord) -> RecordDTO {
        RecordDTO(
            id: record.id,
            exerciseId: record.exerciseId,
            displayName: record.displayName,
            oneRepMax: record.oneRepMax,
            maxReps: record.maxReps,
            updatedAt: record.updatedAt
        )
    }

    private static func dto(from customExercise: CustomExercise) -> CustomExerciseDTO {
        CustomExerciseDTO(
            id: customExercise.id,
            name: customExercise.name,
            primaryMuscles: customExercise.primaryMuscles,
            equipment: customExercise.equipment,
            notes: customExercise.notes
        )
    }

    // MARK: - Mapping DTO -> modele (toujours de nouvelles UUID, fusion additive)

    private static func model(from dto: ProgramDTO) -> Program {
        let program = Program(
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

    private static func model(from dto: SessionDTO) -> ProgramSession {
        let session = ProgramSession(
            name: dto.name,
            orderIndex: dto.orderIndex,
            warmupEnabled: dto.warmupEnabled
        )
        session.exercises = dto.exercises.map { exerciseDTO -> PrescribedExercise in
            let exercise = model(from: exerciseDTO)
            exercise.session = session
            return exercise
        }
        return session
    }

    private static func model(from dto: ExerciseDTO) -> PrescribedExercise {
        PrescribedExercise(
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
            pyramidReps: dto.pyramidReps,
            pyramidMinRest: dto.pyramidMinRest,
            pyramidMaxRest: dto.pyramidMaxRest,
            intervalWork: dto.intervalWork,
            intervalRest: dto.intervalRest,
            intervalRounds: dto.intervalRounds,
            amrapSeconds: dto.amrapSeconds,
            notes: dto.notes
        )
    }

    private static func model(from dto: CompletedSessionDTO) -> CompletedSession {
        let session = CompletedSession(
            date: dto.date,
            programName: dto.programName,
            sessionName: dto.sessionName,
            durationSeconds: dto.durationSeconds
        )
        session.sets = dto.sets.map { setDTO -> CompletedSet in
            let set = model(from: setDTO)
            set.session = session
            return set
        }
        return session
    }

    private static func model(from dto: CompletedSetDTO) -> CompletedSet {
        CompletedSet(
            exerciseId: dto.exerciseId,
            displayName: dto.displayName,
            orderIndex: dto.orderIndex,
            setIndex: dto.setIndex,
            weight: dto.weight,
            reps: dto.reps,
            isWarmup: dto.isWarmup
        )
    }

    private static func model(from dto: RecordDTO) -> ExerciseRecord {
        ExerciseRecord(
            exerciseId: dto.exerciseId,
            displayName: dto.displayName,
            oneRepMax: dto.oneRepMax,
            maxReps: dto.maxReps,
            updatedAt: dto.updatedAt
        )
    }

    private static func model(from dto: CustomExerciseDTO) -> CustomExercise {
        CustomExercise(
            name: dto.name,
            primaryMuscles: dto.primaryMuscles,
            equipment: dto.equipment,
            notes: dto.notes
        )
    }
}
