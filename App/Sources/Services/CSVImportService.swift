import Foundation
import SwiftData
import MuscuEngine

/// Que faire des seances deja presentes.
enum CSVImportPolicy: String, CaseIterable, Identifiable, Sendable {
    /// Ne rien reecrire : les doublons sont comptes et laisses de cote.
    case skipDuplicates
    /// Importer quand meme, en creant une seconde seance datee a l'identique.
    case importAnyway

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .skipDuplicates: return String(localized: "Ignorer les doublons")
        case .importAnyway: return String(localized: "Importer quand même")
        }
    }
}

struct CSVImportOutcome: Equatable, Sendable {
    var report: ImportReport = ImportReport()
    /// Noms d'exercices qui n'ont pas pu etre relies au catalogue. Ils sont
    /// importes avec leur nom d'origine, jamais perdus.
    var unmatchedExerciseNames: [String] = []
    var importIdentifier: UUID = UUID()
    var didWrite: Bool = false
    /// Seances creees par cet import, pour proposer ensuite d'en tirer des
    /// seances de programme ou des modeles.
    var createdSessionIds: [UUID] = []
}

/// Ou ranger les seances tirees d'un import.
enum ImportedRoutineDestination: String, CaseIterable, Identifiable, Sendable {
    /// Un modele de seance par titre retenu.
    case templates
    /// Un nouveau programme (inactif) contenant une seance par titre.
    case newProgram

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .templates: return String(localized: "Modèles de séance")
        case .newProgram: return String(localized: "Nouveau programme")
        }
    }
}

/// Import CSV : analyse, apercu, puis ecriture confirmee.
///
/// L'ecriture est faite en UNE SEULE sauvegarde. Si elle echoue, SwiftData
/// annule tout le lot (cf. `PersistenceSupport`) : un fichier partiel ou
/// malforme ne peut pas laisser le store a moitie modifie.
@MainActor
enum CSVImportService {
    static func makeParser(for text: String) -> CSVParser {
        CSVParser(delimiter: CSVParser.detectDelimiter(in: text))
    }

    /// Signatures des seances deja presentes, pour detecter les doublons.
    ///
    /// Deux sources : la signature posee lors d'un import precedent, et une
    /// signature recalculee pour les seances saisies dans l'application.
    static func existingSignatures(
        in context: ModelContext,
        calendar: Calendar = .current,
        timeZone: TimeZone = .current
    ) -> Set<String> {
        let sessions = ((try? context.fetch(FetchDescriptor<CompletedSession>())) ?? [])
            .filter { $0.deletedAt == nil }
        var signatures: Set<String> = []
        for session in sessions {
            if !session.importSignature.isEmpty {
                signatures.insert(session.importSignature)
            }
            signatures.insert(CSVImportPlanner.signature(
                date: session.date,
                name: session.sessionName,
                calendar: calendar,
                timeZone: timeZone
            ))
        }
        return signatures
    }

    /// Analyse sans rien ecrire.
    static func preview(
        text: String,
        mapping: ColumnMapping,
        in context: ModelContext,
        calendar: Calendar = .current,
        timeZone: TimeZone = .current
    ) throws -> CSVImportPlan {
        let rows = try makeParser(for: text).parse(text)
        return CSVImportPlanner.plan(
            rows: rows,
            mapping: mapping,
            existingSignatures: existingSignatures(in: context, calendar: calendar, timeZone: timeZone),
            calendar: calendar,
            timeZone: timeZone
        )
    }

    /// Ecrit le resultat d'une analyse, apres confirmation de l'utilisateur.
    @discardableResult
    static func apply(
        _ plan: CSVImportPlan,
        policy: CSVImportPolicy,
        sourceName: String,
        catalog: ExerciseCatalog?,
        in context: ModelContext,
        now: Date = .now
    ) -> CSVImportOutcome {
        var outcome = CSVImportOutcome(importIdentifier: UUID())
        outcome.report = plan.report
        outcome.report.created = 0
        outcome.report.ignored = 0
        // Une seance terminee est IMMUABLE : l'import ne fusionne jamais dans
        // une seance existante. Le compteur reste donc a zero, et le rapport
        // le dit plutot que de laisser croire a une fusion silencieuse.
        outcome.report.merged = 0

        var unmatched: Set<String> = []

        for session in plan.sessions {
            let isDuplicate = plan.duplicateSignatures.contains(session.signature)
            if isDuplicate, policy == .skipDuplicates {
                outcome.report.ignored += 1
                continue
            }

            let completed = CompletedSession(
                date: session.date,
                programName: sourceName,
                sessionName: session.name,
                durationSeconds: 0,
                notes: session.notes,
                importSource: sourceName,
                importSignature: session.signature,
                createdAt: now,
                updatedAt: now
            )
            context.insert(completed)
            outcome.createdSessionIds.append(completed.id)

            var orderByExercise: [String: Int] = [:]
            var sequence = 0

            for importedSet in session.sets {
                let match = resolveExercise(named: importedSet.exerciseName, catalog: catalog)
                if match == nil { unmatched.insert(importedSet.exerciseName) }

                let exerciseId = match?.id ?? ""
                let orderIndex = orderByExercise[importedSet.exerciseName] ?? orderByExercise.count
                orderByExercise[importedSet.exerciseName] = orderIndex

                let loadKind = match.map(ExerciseClassification.loadKind(for:)) ?? .unknown
                let completedSet = CompletedSet(
                    exerciseId: exerciseId,
                    displayName: match?.nameFr ?? importedSet.exerciseName,
                    orderIndex: orderIndex,
                    setIndex: importedSet.setIndex,
                    weight: importedSet.weightKilograms ?? 0,
                    reps: importedSet.reps ?? 0,
                    isWarmup: importedSet.isWarmup,
                    loadTypeRaw: ExerciseLoadType(loadKind: loadKind).rawValue,
                    roleRaw: (importedSet.isWarmup ? SetRole.warmup : SetRole.working).rawValue,
                    notes: importedSet.notes,
                    durationSeconds: importedSet.durationSeconds,
                    distanceMeters: importedSet.distanceMeters,
                    sequenceIndex: sequence,
                    createdAt: now,
                    updatedAt: now
                )
                completedSet.session = completed
                completed.sets.append(completedSet)
                context.insert(completedSet)
                sequence += 1
            }

            outcome.report.created += 1
        }

        for row in plan.quarantined {
            context.insert(ImportQuarantineEntry(
                importIdentifier: outcome.importIdentifier,
                sourceName: sourceName,
                rowNumber: row.rowNumber,
                rawRow: row.raw.joined(separator: " | "),
                reason: row.reason.explanation,
                createdAt: now
            ))
        }

        outcome.unmatchedExerciseNames = unmatched.sorted()
        outcome.didWrite = PersistenceSupport.save(context, action: "Import CSV")
        if !outcome.didWrite { outcome.createdSessionIds = [] }
        return outcome
    }

    /// Seuil de correspondance : en dessous, deux exercices differents
    /// risqueraient d'etre assimiles.
    private static let matchThreshold = 600

    /// Relie un nom libre au catalogue. Le seuil evite d'assimiler deux
    /// exercices differents : en dessous, on conserve le nom d'origine
    /// plutot que d'inventer une correspondance.
    ///
    /// Un materiel ecrit entre parentheses (« Deadlift (Barbell) », usage de
    /// Strong et Hevy) est d'abord cherche AVEC ce materiel : le nom seul
    /// trouverait aussi bien la variante aux halteres.
    static func resolveExercise(named name: String, catalog: ExerciseCatalog?) -> CatalogExercise? {
        guard let catalog, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let suffix = ExerciseNaming.equipmentSuffix(in: name)
        if let suffix {
            let filtered = LibrarySearch.run(
                query: suffix.baseName,
                filters: LibraryFilters(equipment: [suffix.equipment]),
                catalog: catalog.all,
                limit: 1
            )
            if let best = filtered.first, best.score >= matchThreshold { return best.exercise }
        }
        let results = LibrarySearch.run(query: name, catalog: catalog.all, limit: 1)
        if let best = results.first, best.score >= matchThreshold { return best.exercise }
        if let suffix {
            let unfiltered = LibrarySearch.run(query: suffix.baseName, catalog: catalog.all, limit: 1)
            if let best = unfiltered.first, best.score >= matchThreshold { return best.exercise }
        }
        return nil
    }

    // MARK: - Programmes a partir de l'import

    /// Titres de seance importes qui peuvent devenir des seances de
    /// programme ou des modeles. Seuls les exercices relies au catalogue
    /// sont proposes : un exercice non reconnu n'a pas d'identite stable a
    /// prescrire.
    static func routineCandidates(
        for outcome: CSVImportOutcome,
        in context: ModelContext
    ) -> [ImportedRoutineCandidate] {
        let ids = Set(outcome.createdSessionIds)
        guard !ids.isEmpty else { return [] }
        let sessions = ((try? context.fetch(FetchDescriptor<CompletedSession>())) ?? [])
            .filter { ids.contains($0.id) }
        return ImportedRoutines.candidates(from: sessions.map(importedRoutineSession(from:)))
    }

    static func importedRoutineSession(from session: CompletedSession) -> ImportedRoutineSession {
        let working = session.sets.filter { $0.role.countsAsWorkingSet && $0.subSetIndex == 0 && !$0.exerciseId.isEmpty }
        let byOrder = Dictionary(grouping: working, by: \.orderIndex)
        let exercises = byOrder.keys.sorted().compactMap { orderIndex -> ImportedRoutineExercise? in
            guard let sets = byOrder[orderIndex], let first = sets.first else { return nil }
            return ImportedRoutineExercise(
                exerciseId: first.exerciseId,
                displayName: first.displayName,
                workingSetCount: sets.count
            )
        }
        return ImportedRoutineSession(title: session.sessionName, date: session.date, exercises: exercises)
    }

    /// Cree les seances choisies, apres confirmation. Les noms ne remplacent
    /// jamais un modele ou une seance existante : ils sont suffixes.
    /// Retourne le nombre de seances creees, `nil` en cas d'echec.
    @discardableResult
    static func createRoutines(
        _ candidates: [ImportedRoutineCandidate],
        destination: ImportedRoutineDestination,
        programName: String,
        in context: ModelContext,
        now: Date = .now
    ) -> Int? {
        guard !candidates.isEmpty else { return 0 }
        switch destination {
        case .templates:
            var taken = TemplateService.templates(in: context, includeArchived: true).map(\.name)
            for candidate in candidates {
                let name = ImportedRoutines.uniqueName(candidate.name, taken: taken)
                taken.append(name)
                TemplateService.makeTemplate(fromImported: candidate, named: name, in: context, now: now)
            }
            return candidates.count
        case .newProgram:
            let programs = ((try? context.fetch(FetchDescriptor<Program>())) ?? []).filter { $0.deletedAt == nil }
            let trimmed = programName.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = ImportedRoutines.uniqueName(
                trimmed.isEmpty ? String(localized: "Programme importé") : trimmed,
                taken: programs.map(\.name)
            )
            // Inactif : activer un programme reste une decision explicite.
            let program = Program(name: name, isActive: false, createdAt: now, updatedAt: now)
            context.insert(program)
            var taken: [String] = []
            let payload = TemplatePayload(sessions: candidates.map { candidate in
                let sessionName = ImportedRoutines.uniqueName(candidate.name, taken: taken)
                taken.append(sessionName)
                return TemplateService.importedSession(candidate, named: sessionName)
            })
            let created = TemplateService.insertSessions(from: payload, into: program, in: context, now: now)
            guard PersistenceSupport.save(context, action: "Création du programme importé") else { return nil }
            return created.count
        }
    }

    // MARK: - Quarantaine

    static func quarantine(in context: ModelContext) -> [ImportQuarantineEntry] {
        ((try? context.fetch(FetchDescriptor<ImportQuarantineEntry>(sortBy: [SortDescriptor(\.createdAt, order: .reverse), SortDescriptor(\.rowNumber)]))) ?? [])
            .filter { $0.resolvedAt == nil }
    }

    static func clearQuarantine(in context: ModelContext, now: Date = .now) {
        for entry in quarantine(in: context) {
            entry.resolvedAt = now
        }
        _ = PersistenceSupport.save(context, action: "Nettoyage de la quarantaine")
    }
}
