import Foundation
import SwiftData
import MuscuEngine

/// Export CSV lisible, en plus de l'export JSON complet.
///
/// Format stable et documenté : séparateur virgule, guillemets doublés,
/// dates ISO 8601, nombres au point décimal et **toujours en unité
/// canonique** (kg, cm). Un tableur ou un autre outil doit pouvoir le lire
/// sans connaître Muscu.
enum CSVExport {
    /// Jeux de données exportables séparément.
    enum Dataset: String, CaseIterable, Identifiable {
        case sessions
        case sets
        case measurements
        case checkIns

        var id: String { rawValue }

        var fileName: String {
            switch self {
            case .sessions: return "muscu-seances"
            case .sets: return "muscu-series"
            case .measurements: return "muscu-mesures"
            case .checkIns: return "muscu-checkins"
            }
        }

        var displayName: String {
            switch self {
            case .sessions: return String(localized: "Séances")
            case .sets: return String(localized: "Séries")
            case .measurements: return String(localized: "Mesures")
            case .checkIns: return String(localized: "Check-in")
            }
        }
    }

    // MARK: - Génération

    @MainActor
    static func csv(for dataset: Dataset, context: ModelContext) throws -> String {
        switch dataset {
        case .sessions: return try sessionsCSV(context: context)
        case .sets: return try setsCSV(context: context)
        case .measurements: return try measurementsCSV(context: context)
        case .checkIns: return try checkInsCSV(context: context)
        }
    }

    @MainActor
    private static func sessionsCSV(context: ModelContext) throws -> String {
        let sessions = try context.fetch(
            FetchDescriptor<CompletedSession>(sortBy: [SortDescriptor(\.date)])
        )
        var rows: [[String]] = [[
            "id", "date", "programme", "seance", "duree_secondes",
            "series_de_travail", "repetitions", "tonnage_kg", "series_sans_tonnage",
            "poids_de_corps_kg", "notes",
            // Colonnes ajoutees apres coup : toujours EN FIN de ligne, pour
            // qu'un lecteur par position reste juste (cf. docs/formats/csv.md).
            "effort_seance",
        ]]
        for session in sessions {
            let working = session.workingSets
            let tonnage = SetMetrics.totalTonnage(session.metricsInputs())
            rows.append([
                session.id.uuidString,
                isoDate(session.date),
                session.programName,
                session.sessionName,
                String(session.durationSeconds),
                String(working.count),
                String(working.reduce(0) { $0 + $1.reps }),
                number(tonnage.total),
                String(tonnage.unknownSets),
                session.bodyweightKilograms.map(number) ?? "",
                session.notes,
                session.effortRating.map(String.init) ?? "",
            ])
        }
        return render(rows)
    }

    @MainActor
    private static func setsCSV(context: ModelContext) throws -> String {
        let sessions = try context.fetch(
            FetchDescriptor<CompletedSession>(sortBy: [SortDescriptor(\.date)])
        )
        var rows: [[String]] = [[
            "seance_id", "date", "exercice_id", "exercice", "exercice_prevu_id",
            "format", "role", "tour", "serie", "sous_serie",
            "charge_kg", "type_de_charge", "repetitions", "duree_secondes",
            "effort", "echec", "tempo", "cote", "notes",
            "distance_m", "repos_reel_secondes",
        ]]
        for session in sessions {
            for set in session.orderedSets {
                rows.append([
                    session.id.uuidString,
                    isoDate(session.date),
                    set.exerciseId,
                    set.displayName,
                    set.plannedExerciseId,
                    set.formatRaw,
                    set.role.rawValue,
                    String(set.roundIndex + 1),
                    String(set.setIndex + 1),
                    String(set.subSetIndex),
                    number(set.weight),
                    set.loadTypeRaw,
                    String(set.reps),
                    set.durationSeconds.map(String.init) ?? "",
                    set.effort?.displayText ?? "",
                    set.reachedFailure ? "oui" : "non",
                    set.tempoNotation,
                    set.sideConventionRaw,
                    set.notes,
                    set.distanceMeters.map(number) ?? "",
                    set.actualRestSeconds.map(String.init) ?? "",
                ])
            }
        }
        return render(rows)
    }

    @MainActor
    private static func measurementsCSV(context: ModelContext) throws -> String {
        let measurements = try context.fetch(
            FetchDescriptor<BodyMeasurement>(sortBy: [SortDescriptor(\.measuredAt)])
        )
        var rows: [[String]] = [["id", "date", "type", "nom_personnalise", "valeur", "unite", "source", "notes", "supprimee"]]
        for measurement in measurements {
            rows.append([
                measurement.id.uuidString,
                isoDate(measurement.measuredAt),
                measurement.kindRaw,
                measurement.customName,
                number(measurement.value),
                measurement.canonicalUnitSymbol,
                measurement.sourceRaw,
                measurement.notes,
                measurement.deletedAt == nil ? "non" : "oui",
            ])
        }
        return render(rows)
    }

    @MainActor
    private static func checkInsCSV(context: ModelContext) throws -> String {
        let entries = try context.fetch(
            FetchDescriptor<ReadinessEntry>(sortBy: [SortDescriptor(\.recordedAt)])
        )
        var rows: [[String]] = [[
            "id", "date", "energie", "sommeil", "courbatures", "stress",
            "douleur", "zone_douleur", "notes",
        ]]
        for entry in entries {
            rows.append([
                entry.id.uuidString,
                isoDate(entry.recordedAt),
                entry.energy.map(String.init) ?? "",
                entry.sleepQuality.map(String.init) ?? "",
                entry.soreness.map(String.init) ?? "",
                entry.stress.map(String.init) ?? "",
                entry.painIntensity.map(String.init) ?? "",
                entry.painArea,
                entry.notes,
            ])
        }
        return render(rows)
    }

    // MARK: - Mise en forme

    /// Rendu CSV : chaque champ est échappé, aucune ligne n'est tronquée.
    static func render(_ rows: [[String]]) -> String {
        rows.map { row in row.map(escape).joined(separator: ",") }.joined(separator: "\n") + "\n"
    }

    /// Échappement CSV standard : guillemets doublés, champ encadré dès qu'il
    /// contient une virgule, un guillemet, un retour à la ligne — ou qu'il
    /// commence par un caractère que les tableurs interprètent comme une
    /// formule.
    static func escape(_ field: String) -> String {
        let isFormula = startsWithFormulaCharacter(field)
        let body = isFormula ? "'" + field : field
        let needsQuotes = isFormula
            || body.contains(",")
            || body.contains("\"")
            || body.contains("\n")
            || body.contains("\r")
        guard needsQuotes else { return body }
        return "\"" + body.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Un champ commençant par `=`, `+`, `-` ou `@` est interprété comme une
    /// formule par Excel et Numbers. On le neutralise en le citant ET en le
    /// préfixant d'une apostrophe, pour qu'une note utilisateur ne puisse pas
    /// devenir du code exécuté à l'ouverture du fichier.
    private static func startsWithFormulaCharacter(_ field: String) -> Bool {
        guard let first = field.first else { return false }
        return ["=", "+", "@"].contains(String(first))
            || (first == "-" && Double(field) == nil)
    }

    static func number(_ value: Double) -> String {
        guard value.isFinite else { return "" }
        return value == value.rounded()
            ? String(Int(value))
            : String(format: "%.3f", value)
    }

    static func isoDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
