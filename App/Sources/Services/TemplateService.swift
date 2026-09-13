import Foundation
import SwiftData
import MuscuEngine
import UniformTypeIdentifiers

/// Contenu d'un modele : un INSTANTANE, pas une reference.
///
/// Version explicite : un fichier de modele partage aujourd'hui doit rester
/// lisible par une version ulterieure de l'application.
struct TemplatePayload: Codable, Sendable {
    var formatVersion: Int = 1
    var sessions: [TemplateSession] = []
}

struct TemplateSession: Codable, Sendable {
    var name: String
    var warmupEnabled: Bool = false
    var groups: [TemplateGroup] = []
    var exercises: [TemplateExercise] = []
}

struct TemplateGroup: Codable, Sendable {
    var kindRaw: String
    var orderIndex: Int
    var rounds: Int
    var restBetweenExercisesSeconds: Int
    var restBetweenRoundsSeconds: Int
    var transitionSeconds: Int
    var requiresManualStationValidation: Bool
    var notes: String
}

struct TemplateExercise: Codable, Sendable {
    var exerciseId: String
    var displayName: String
    var orderIndex: Int
    var formatRaw: String
    var sets: Int
    var repsLower: Int
    var repsUpper: Int
    var restSeconds: Int
    var notes: String
    var groupOrderIndex: Int
    /// Rang du groupe dans `TemplateSession.groups`. nil = exercice seul.
    var groupIndex: Int?
    var tempoNotation: String
    var loadKindRaw: String
    var sideConventionRaw: String
    var percentOneRepMax: Double?
    /// Charge cible PRESCRITE. Une charge realisee n'est jamais copiee ici :
    /// un modele decrit une intention, pas une performance passee.
    var targetWeight: Double?
    var pyramidReps: [Int]
    var dropsetDrops: [Double]
    var dropsetUsesPercent: Bool
    var intervalWork: Int
    var intervalRest: Int
    var intervalRounds: Int
    var amrapSeconds: Int
    var forTimeCapSeconds: Int
}

/// Modeles de seance et de programme : creation, application, duplication,
/// archivage et partage par fichier.
@MainActor
enum TemplateService {
    static let fileExtension = "muscutemplate"

    // MARK: - Lecture

    static func templates(in context: ModelContext, includeArchived: Bool = false) -> [SessionTemplate] {
        let all = ((try? context.fetch(FetchDescriptor<SessionTemplate>(sortBy: [SortDescriptor(\.name)]))) ?? [])
            .filter { $0.deletedAt == nil }
        return includeArchived ? all : all.filter { !$0.isArchived }
    }

    static func payload(of template: SessionTemplate) -> TemplatePayload? {
        guard let data = template.payloadData else { return nil }
        return try? JSONDecoder().decode(TemplatePayload.self, from: data)
    }

    // MARK: - Création

    /// Modele a partir d'une seance de PROGRAMME : la prescription est
    /// recopiee telle quelle.
    @discardableResult
    static func makeTemplate(
        from session: ProgramSession,
        named name: String? = nil,
        in context: ModelContext,
        now: Date = .now
    ) -> SessionTemplate {
        let payload = TemplatePayload(sessions: [snapshot(of: session)])
        return store(
            payload: payload,
            name: name ?? session.name,
            scope: .session,
            notes: "",
            in: context,
            now: now
        )
    }

    /// Modele a partir d'un PROGRAMME complet.
    @discardableResult
    static func makeTemplate(
        from program: Program,
        named name: String? = nil,
        in context: ModelContext,
        now: Date = .now
    ) -> SessionTemplate {
        let payload = TemplatePayload(sessions: program.orderedSessions.map(snapshot(of:)))
        return store(
            payload: payload,
            name: name ?? program.name,
            scope: .program,
            notes: program.notes,
            in: context,
            now: now
        )
    }

    /// Modele a partir d'une seance TERMINEE.
    ///
    /// Les performances ne sont PAS recopiees : ni charge, ni repetitions
    /// realisees, ni effort. Un modele decrit ce qu'on prevoit de faire ;
    /// recopier le passe transformerait un record du jour en obligation
    /// permanente. Seuls l'ordre des exercices, leur format et le nombre de
    /// series de travail sont conserves.
    @discardableResult
    static func makeTemplate(
        fromCompleted session: CompletedSession,
        named name: String? = nil,
        in context: ModelContext,
        now: Date = .now
    ) -> SessionTemplate {
        var exercises: [TemplateExercise] = []
        var order = 0

        for group in workingSetsGroupedByExercise(of: session) {
            exercises.append(TemplateExercise(
                exerciseId: group.exerciseId,
                displayName: group.displayName,
                orderIndex: order,
                formatRaw: group.formatRaw,
                sets: group.count,
                repsLower: 0,
                repsUpper: 0,
                restSeconds: 0,
                notes: "",
                groupOrderIndex: 0,
                groupIndex: nil,
                tempoNotation: "",
                loadKindRaw: group.loadTypeRaw,
                sideConventionRaw: SideConvention.bilateral.rawValue,
                percentOneRepMax: nil,
                targetWeight: nil,
                pyramidReps: [],
                dropsetDrops: [],
                dropsetUsesPercent: true,
                intervalWork: 0,
                intervalRest: 0,
                intervalRounds: 0,
                amrapSeconds: 0,
                forTimeCapSeconds: 0
            ))
            order += 1
        }

        let payload = TemplatePayload(sessions: [
            TemplateSession(name: session.sessionName, warmupEnabled: false, groups: [], exercises: exercises),
        ])

        return store(
            payload: payload,
            name: name ?? session.sessionName,
            scope: .session,
            notes: "Créé depuis une séance terminée. Les charges et répétitions réalisées ne sont pas reprises.",
            in: context,
            now: now
        )
    }

    private struct CompletedExerciseGroup {
        let exerciseId: String
        let displayName: String
        let formatRaw: String
        let loadTypeRaw: String
        var count: Int
    }

    private static func workingSetsGroupedByExercise(of session: CompletedSession) -> [CompletedExerciseGroup] {
        var groups: [CompletedExerciseGroup] = []
        for set in session.orderedSets where !set.isWarmup && set.subSetIndex == 0 {
            if let index = groups.firstIndex(where: { $0.exerciseId == set.exerciseId }) {
                groups[index].count += 1
            } else {
                groups.append(CompletedExerciseGroup(
                    exerciseId: set.exerciseId,
                    displayName: set.displayName,
                    formatRaw: set.formatRaw,
                    loadTypeRaw: set.loadTypeRaw,
                    count: 1
                ))
            }
        }
        return groups
    }

    private static func snapshot(of session: ProgramSession) -> TemplateSession {
        let groups = session.orderedGroups
        let groupIndexById = Dictionary(
            groups.enumerated().map { ($1.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        return TemplateSession(
            name: session.name,
            warmupEnabled: session.warmupEnabled,
            groups: groups.map { group in
                TemplateGroup(
                    kindRaw: group.kindRaw,
                    orderIndex: group.orderIndex,
                    rounds: group.rounds,
                    restBetweenExercisesSeconds: group.restBetweenExercisesSeconds,
                    restBetweenRoundsSeconds: group.restBetweenRoundsSeconds,
                    transitionSeconds: group.transitionSeconds,
                    requiresManualStationValidation: group.requiresManualStationValidation,
                    notes: group.notes
                )
            },
            exercises: session.orderedExercises.map { exercise in
                TemplateExercise(
                    exerciseId: exercise.exerciseId,
                    displayName: exercise.displayName,
                    orderIndex: exercise.orderIndex,
                    formatRaw: exercise.formatRaw,
                    sets: exercise.sets,
                    repsLower: exercise.repsLower,
                    repsUpper: exercise.repsUpper,
                    restSeconds: exercise.restSeconds,
                    notes: exercise.notes,
                    groupOrderIndex: exercise.groupOrderIndex,
                    groupIndex: exercise.group.flatMap { groupIndexById[$0.id] },
                    tempoNotation: exercise.tempoNotation,
                    loadKindRaw: exercise.loadKindRaw,
                    sideConventionRaw: exercise.sideConventionRaw,
                    percentOneRepMax: exercise.percentOneRepMax,
                    targetWeight: exercise.targetWeight,
                    pyramidReps: exercise.pyramidReps,
                    dropsetDrops: exercise.dropsetDrops,
                    dropsetUsesPercent: exercise.dropsetUsesPercent,
                    intervalWork: exercise.intervalWork,
                    intervalRest: exercise.intervalRest,
                    intervalRounds: exercise.intervalRounds,
                    amrapSeconds: exercise.amrapSeconds,
                    forTimeCapSeconds: exercise.forTimeCapSeconds
                )
            }
        )
    }

    /// Enregistre le modele. Un modele portant deja ce nom et cette portee
    /// n'est pas ecrase : une NOUVELLE VERSION est creee, et l'ancienne
    /// reste consultable.
    @discardableResult
    private static func store(
        payload: TemplatePayload,
        name: String,
        scope: TemplateScope,
        notes: String,
        in context: ModelContext,
        now: Date
    ) -> SessionTemplate {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "Modèle" : trimmed
        let previous = templates(in: context, includeArchived: true)
            .filter { $0.name == finalName && $0.scope == scope }
            .map(\.version)
            .max() ?? 0

        let template = SessionTemplate(
            name: finalName,
            scopeRaw: scope.rawValue,
            notes: notes,
            payloadData: try? JSONEncoder().encode(payload),
            version: previous + 1,
            createdAt: now,
            updatedAt: now
        )
        context.insert(template)
        _ = PersistenceSupport.save(context, action: "Enregistrement du modèle")
        return template
    }

    // MARK: - Application

    /// Applique un modele a un programme existant : chaque seance du modele
    /// est AJOUTEE, jamais substituee a l'existant.
    @discardableResult
    static func apply(
        _ template: SessionTemplate,
        to program: Program,
        in context: ModelContext,
        now: Date = .now
    ) -> [ProgramSession] {
        guard let payload = payload(of: template) else { return [] }

        var created: [ProgramSession] = []
        var order = program.sessions.count

        for templateSession in payload.sessions {
            let session = ProgramSession(name: templateSession.name, orderIndex: order, warmupEnabled: templateSession.warmupEnabled)
            session.program = program
            program.sessions.append(session)
            context.insert(session)
            order += 1

            var groups: [ExerciseGroup] = []
            for templateGroup in templateSession.groups {
                let group = ExerciseGroup(
                    kindRaw: templateGroup.kindRaw,
                    orderIndex: templateGroup.orderIndex,
                    rounds: templateGroup.rounds,
                    restBetweenExercisesSeconds: templateGroup.restBetweenExercisesSeconds,
                    restBetweenRoundsSeconds: templateGroup.restBetweenRoundsSeconds
                )
                group.transitionSeconds = templateGroup.transitionSeconds
                group.requiresManualStationValidation = templateGroup.requiresManualStationValidation
                group.notes = templateGroup.notes
                group.session = session
                session.groups.append(group)
                context.insert(group)
                groups.append(group)
            }

            for templateExercise in templateSession.exercises {
                let exercise = PrescribedExercise(
                    exerciseId: templateExercise.exerciseId,
                    displayName: templateExercise.displayName,
                    orderIndex: templateExercise.orderIndex,
                    formatRaw: templateExercise.formatRaw,
                    sets: templateExercise.sets,
                    repsLower: templateExercise.repsLower,
                    repsUpper: templateExercise.repsUpper,
                    restSeconds: templateExercise.restSeconds,
                    percentOneRepMax: templateExercise.percentOneRepMax,
                    targetWeight: templateExercise.targetWeight,
                    pyramidReps: templateExercise.pyramidReps,
                    notes: templateExercise.notes,
                    groupOrderIndex: templateExercise.groupOrderIndex,
                    tempoNotation: templateExercise.tempoNotation,
                    loadKindRaw: templateExercise.loadKindRaw,
                    sideConventionRaw: templateExercise.sideConventionRaw,
                    dropsetDrops: templateExercise.dropsetDrops,
                    dropsetUsesPercent: templateExercise.dropsetUsesPercent
                )
                exercise.intervalWork = templateExercise.intervalWork
                exercise.intervalRest = templateExercise.intervalRest
                exercise.intervalRounds = templateExercise.intervalRounds
                exercise.amrapSeconds = templateExercise.amrapSeconds
                exercise.forTimeCapSeconds = templateExercise.forTimeCapSeconds
                exercise.session = session
                session.exercises.append(exercise)
                if let groupIndex = templateExercise.groupIndex, groups.indices.contains(groupIndex) {
                    exercise.group = groups[groupIndex]
                }
                context.insert(exercise)
            }

            created.append(session)
        }

        template.lastUsedAt = now
        template.updatedAt = now
        program.touch(now: now)
        _ = PersistenceSupport.save(context, action: "Application du modèle")
        return created
    }

    // MARK: - Cycle de vie

    static func duplicate(_ template: SessionTemplate, in context: ModelContext, now: Date = .now) {
        let copy = SessionTemplate(
            name: template.name + " (copie)",
            scopeRaw: template.scopeRaw,
            notes: template.notes,
            payloadData: template.payloadData,
            version: 1,
            createdAt: now,
            updatedAt: now
        )
        context.insert(copy)
        _ = PersistenceSupport.save(context, action: "Duplication du modèle")
    }

    static func setArchived(_ template: SessionTemplate, _ archived: Bool, in context: ModelContext, now: Date = .now) {
        template.isArchived = archived
        template.updatedAt = now
        _ = PersistenceSupport.save(context, action: "Archivage du modèle")
    }

    static func toggleFavorite(_ template: SessionTemplate, in context: ModelContext, now: Date = .now) {
        template.isFavorite.toggle()
        template.updatedAt = now
        _ = PersistenceSupport.save(context, action: "Favori du modèle")
    }

    static func delete(_ template: SessionTemplate, in context: ModelContext, now: Date = .now) {
        template.deletedAt = now
        template.updatedAt = now
        _ = PersistenceSupport.save(context, action: "Suppression du modèle")
    }

    // MARK: - Partage par fichier

    /// Fichier partageable. Il ne contient QUE la prescription : aucun
    /// identifiant de compte, aucun jeton, aucune donnee personnelle.
    struct SharedTemplate: Codable, Sendable {
        var formatVersion: Int = 1
        var name: String
        var scopeRaw: String
        var notes: String
        var payload: TemplatePayload
    }

    static func exportData(_ template: SessionTemplate) throws -> Data {
        let shared = SharedTemplate(
            name: template.name,
            scopeRaw: template.scopeRaw,
            notes: template.notes,
            payload: payload(of: template) ?? TemplatePayload()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(shared)
    }

    @discardableResult
    static func importTemplate(from data: Data, in context: ModelContext, now: Date = .now) throws -> SessionTemplate {
        let shared = try JSONDecoder().decode(SharedTemplate.self, from: data)
        return store(
            payload: shared.payload,
            name: shared.name,
            scope: TemplateScope(rawValue: shared.scopeRaw) ?? .session,
            notes: shared.notes,
            in: context,
            now: now
        )
    }
}
