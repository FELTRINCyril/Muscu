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
        return outcome
    }

    /// Relie un nom libre au catalogue. Le seuil evite d'assimiler deux
    /// exercices differents : en dessous, on conserve le nom d'origine
    /// plutot que d'inventer une correspondance.
    static func resolveExercise(named name: String, catalog: ExerciseCatalog?) -> CatalogExercise? {
        guard let catalog, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let results = LibrarySearch.run(query: name, catalog: catalog.all, limit: 1)
        guard let best = results.first, best.score >= 600 else { return nil }
        return best.exercise
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
