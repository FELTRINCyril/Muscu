import Foundation

/// Champ metier auquel une colonne CSV peut etre reliee.
public enum ImportField: String, CaseIterable, Codable, Sendable, Identifiable {
    case ignored
    case date
    case sessionName
    case sessionNotes
    case exerciseName
    case setIndex
    case setKind
    case weight
    case weightUnit
    case reps
    case durationSeconds
    case distanceMeters
    case effort
    case notes

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .ignored: return "Ignorée"
        case .date: return "Date"
        case .sessionName: return "Nom de séance"
        case .sessionNotes: return "Notes de séance"
        case .exerciseName: return "Exercice"
        case .setIndex: return "Numéro de série"
        case .setKind: return "Type de série"
        case .weight: return "Charge"
        case .weightUnit: return "Unité de charge"
        case .reps: return "Répétitions"
        case .durationSeconds: return "Durée (s)"
        case .distanceMeters: return "Distance (m)"
        case .effort: return "Effort (RPE)"
        case .notes: return "Notes de série"
        }
    }

    /// Sans date ni exercice, une ligne ne peut etre rattachee a rien.
    public static let required: [ImportField] = [.date, .exerciseName]

    /// Aliases connus, en francais et en anglais. La comparaison passe par
    /// `TextMatching`, donc accents et casse sont deja neutralises.
    var aliases: [String] {
        switch self {
        case .ignored: return []
        case .date: return ["date", "start time", "workout date", "début", "debut", "horodatage", "timestamp"]
        case .sessionName: return ["workout name", "title", "séance", "seance", "nom de seance", "workout"]
        case .sessionNotes: return ["workout notes", "description", "notes de seance"]
        case .exerciseName: return ["exercise name", "exercise title", "exercice", "exercise", "mouvement"]
        case .setIndex: return ["set order", "set index", "set", "serie", "série", "numero de serie"]
        case .setKind: return ["set type", "type", "type de serie"]
        case .weight: return ["weight", "weight kg", "poids", "charge", "kg", "lbs"]
        case .weightUnit: return ["weight unit", "unit", "unite", "unité"]
        case .reps: return ["reps", "repetitions", "répétitions", "rep"]
        case .durationSeconds: return ["seconds", "duration seconds", "duree", "durée", "temps"]
        case .distanceMeters: return ["distance", "distance km", "distance m", "metres", "mètres"]
        case .effort: return ["rpe", "effort", "rir"]
        case .notes: return ["notes", "note", "commentaire", "comment"]
        }
    }
}

/// Format source reconnu. Un preset ne fait que PRE-remplir la
/// correspondance : l'utilisateur garde la main sur chaque colonne.
public enum CSVImportPreset: String, CaseIterable, Sendable, Identifiable {
    case generic
    case strong
    case hevy

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .generic: return "CSV générique"
        case .strong: return "Strong"
        case .hevy: return "Hevy"
        }
    }

    /// Entetes caracteristiques, tels que documentes publiquement par ces
    /// applications pour leur export CSV.
    var signature: [String] {
        switch self {
        case .generic: return []
        case .strong: return ["workout name", "exercise name", "set order"]
        case .hevy: return ["exercise title", "set index", "start time"]
        }
    }

    public static func detect(header: [String]) -> CSVImportPreset {
        let normalized = Set(header.map { TextMatching.normalize($0) })
        for preset in [CSVImportPreset.strong, .hevy] {
            let expected = preset.signature.map(TextMatching.normalize)
            if expected.allSatisfy({ normalized.contains($0) }) { return preset }
        }
        return .generic
    }
}

/// Correspondance colonne -> champ, plus les conventions du fichier.
public struct ColumnMapping: Hashable, Sendable {
    public var assignments: [Int: ImportField]
    /// Unite appliquee aux charges quand le fichier n'en porte pas.
    public var defaultMassUnit: MassUnit
    /// Vrai quand la colonne distance est en kilometres (cas de Hevy).
    public var distanceIsKilometers: Bool

    public init(
        assignments: [Int: ImportField] = [:],
        defaultMassUnit: MassUnit = .kilograms,
        distanceIsKilometers: Bool = false
    ) {
        self.assignments = assignments
        self.defaultMassUnit = defaultMassUnit
        self.distanceIsKilometers = distanceIsKilometers
    }

    public func column(for field: ImportField) -> Int? {
        assignments.first { $0.value == field }?.key
    }

    public var missingRequiredFields: [ImportField] {
        ImportField.required.filter { column(for: $0) == nil }
    }

    public var isUsable: Bool { missingRequiredFields.isEmpty }

    /// Propose une correspondance a partir des entetes.
    public static func suggested(header: [String], preset: CSVImportPreset) -> ColumnMapping {
        var assignments: [Int: ImportField] = [:]
        var taken: Set<ImportField> = []

        for (index, rawTitle) in header.enumerated() {
            let title = TextMatching.normalize(rawTitle)
            guard !title.isEmpty else { continue }

            let match = ImportField.allCases.first { field in
                guard field != .ignored, !taken.contains(field) else { return false }
                return field.aliases.contains { TextMatching.normalize($0) == title }
            } ?? ImportField.allCases.first { field in
                guard field != .ignored, !taken.contains(field) else { return false }
                return field.aliases.contains { TextMatching.matches(token: title, reference: TextMatching.normalize($0)) }
            }

            if let match {
                assignments[index] = match
                taken.insert(match)
            }
        }

        return ColumnMapping(
            assignments: assignments,
            defaultMassUnit: .kilograms,
            distanceIsKilometers: preset == .hevy
        )
    }
}

/// Pourquoi une ligne est mise de cote. Une valeur inconnue n'est jamais
/// ignoree en silence : elle est mise en quarantaine, avec sa ligne d'origine.
public enum QuarantineReason: Hashable, Sendable {
    case unreadableDate(String)
    case missingExercise
    case unreadableNumber(field: ImportField, value: String)
    case noMeasure
    case unknownValue(field: ImportField, value: String)

    public var explanation: String {
        switch self {
        case .unreadableDate(let value):
            return value.isEmpty ? "Date absente." : "Date illisible : « \(value) »."
        case .missingExercise:
            return "Nom d’exercice absent."
        case .unreadableNumber(let field, let value):
            return "Valeur non numérique dans « \(field.displayName) » : « \(value) »."
        case .noMeasure:
            return "Aucune répétition, durée ni distance sur la ligne."
        case .unknownValue(let field, let value):
            return "Valeur inconnue dans « \(field.displayName) » : « \(value) »."
        }
    }
}

public struct QuarantinedRow: Hashable, Sendable, Identifiable {
    public let id: UUID
    public let rowNumber: Int
    public let raw: [String]
    public let reason: QuarantineReason

    public init(id: UUID = UUID(), rowNumber: Int, raw: [String], reason: QuarantineReason) {
        self.id = id
        self.rowNumber = rowNumber
        self.raw = raw
        self.reason = reason
    }
}

public struct ImportedSet: Hashable, Sendable {
    public let exerciseName: String
    public let setIndex: Int
    public let weightKilograms: Double?
    public let reps: Int?
    public let durationSeconds: Int?
    public let distanceMeters: Double?
    public let effort: Double?
    public let isWarmup: Bool
    public let notes: String

    public init(
        exerciseName: String,
        setIndex: Int,
        weightKilograms: Double?,
        reps: Int?,
        durationSeconds: Int?,
        distanceMeters: Double?,
        effort: Double?,
        isWarmup: Bool,
        notes: String
    ) {
        self.exerciseName = exerciseName
        self.setIndex = setIndex
        self.weightKilograms = weightKilograms
        self.reps = reps
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.effort = effort
        self.isWarmup = isWarmup
        self.notes = notes
    }
}

public struct ImportedSession: Hashable, Sendable, Identifiable {
    public let id: UUID
    public let date: Date
    public let name: String
    public let notes: String
    public let sets: [ImportedSet]
    /// Cle de deduplication stable : date a la minute + nom normalise.
    public let signature: String

    public init(id: UUID = UUID(), date: Date, name: String, notes: String, sets: [ImportedSet], signature: String) {
        self.id = id
        self.date = date
        self.name = name
        self.notes = notes
        self.sets = sets
        self.signature = signature
    }
}

public struct ImportReport: Hashable, Sendable {
    public var created: Int
    public var merged: Int
    public var ignored: Int
    public var duplicates: Int
    public var quarantined: Int
    public var errors: [String]

    public init(
        created: Int = 0,
        merged: Int = 0,
        ignored: Int = 0,
        duplicates: Int = 0,
        quarantined: Int = 0,
        errors: [String] = []
    ) {
        self.created = created
        self.merged = merged
        self.ignored = ignored
        self.duplicates = duplicates
        self.quarantined = quarantined
        self.errors = errors
    }

    public var summary: String {
        "\(created) créée(s), \(merged) fusionnée(s), \(duplicates) doublon(s), \(ignored) ignorée(s), \(quarantined) en quarantaine."
    }
}

/// Resultat d'une analyse d'import : ce qui SERAIT ecrit, et ce qui ne l'est
/// pas. Rien n'est enregistre a ce stade : l'utilisateur voit l'apercu avant
/// de decider.
public struct CSVImportPlan: Sendable {
    public let sessions: [ImportedSession]
    public let duplicateSignatures: Set<String>
    public let quarantined: [QuarantinedRow]
    public let report: ImportReport

    public init(
        sessions: [ImportedSession],
        duplicateSignatures: Set<String>,
        quarantined: [QuarantinedRow],
        report: ImportReport
    ) {
        self.sessions = sessions
        self.duplicateSignatures = duplicateSignatures
        self.quarantined = quarantined
        self.report = report
    }
}

public enum CSVImportPlanner {
    /// Analyse les lignes deja decoupees (entete comprise).
    ///
    /// `existingSignatures` porte les seances deja presentes : un fichier
    /// importe deux fois ne cree jamais de doublon.
    public static func plan(
        rows: [[String]],
        mapping: ColumnMapping,
        existingSignatures: Set<String> = [],
        calendar: Calendar,
        timeZone: TimeZone
    ) -> CSVImportPlan {
        guard mapping.isUsable, rows.count > 1 else {
            let missing = mapping.missingRequiredFields.map(\.displayName).joined(separator: ", ")
            let error = rows.count <= 1
                ? "Le fichier ne contient aucune ligne de données."
                : "Colonnes obligatoires non associées : \(missing)."
            return CSVImportPlan(
                sessions: [],
                duplicateSignatures: [],
                quarantined: [],
                report: ImportReport(errors: [error])
            )
        }

        var grouped: [String: (date: Date, name: String, notes: String, sets: [ImportedSet])] = [:]
        var order: [String] = []
        var quarantined: [QuarantinedRow] = []

        for (offset, row) in rows.dropFirst().enumerated() {
            let rowNumber = offset + 2

            guard let rawDate = value(row, mapping.column(for: .date)),
                  let date = DateParsing.date(from: rawDate, timeZone: timeZone) else {
                quarantined.append(QuarantinedRow(
                    rowNumber: rowNumber,
                    raw: row,
                    reason: .unreadableDate(value(row, mapping.column(for: .date)) ?? "")
                ))
                continue
            }

            guard let exerciseName = value(row, mapping.column(for: .exerciseName))?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !exerciseName.isEmpty else {
                quarantined.append(QuarantinedRow(rowNumber: rowNumber, raw: row, reason: .missingExercise))
                continue
            }

            var failure: QuarantineReason?
            let weight = number(row, mapping.column(for: .weight), field: .weight, failure: &failure)
            let reps = number(row, mapping.column(for: .reps), field: .reps, failure: &failure)
            let duration = number(row, mapping.column(for: .durationSeconds), field: .durationSeconds, failure: &failure)
            let distance = number(row, mapping.column(for: .distanceMeters), field: .distanceMeters, failure: &failure)
            let effort = number(row, mapping.column(for: .effort), field: .effort, failure: &failure)
            let index = number(row, mapping.column(for: .setIndex), field: .setIndex, failure: &failure)

            if let failure {
                quarantined.append(QuarantinedRow(rowNumber: rowNumber, raw: row, reason: failure))
                continue
            }

            guard reps != nil || duration != nil || distance != nil else {
                quarantined.append(QuarantinedRow(rowNumber: rowNumber, raw: row, reason: .noMeasure))
                continue
            }

            let unit = massUnit(row, mapping: mapping)
            let kilograms = weight.map { unit.toKilograms($0) }
            let meters = distance.map { mapping.distanceIsKilometers ? $0 * 1000 : $0 }

            let rawKind = value(row, mapping.column(for: .setKind)) ?? ""
            let kind = SetKindParsing.parse(rawKind)
            if kind == nil, !rawKind.trimmingCharacters(in: .whitespaces).isEmpty {
                quarantined.append(QuarantinedRow(
                    rowNumber: rowNumber,
                    raw: row,
                    reason: .unknownValue(field: .setKind, value: rawKind)
                ))
                continue
            }

            let sessionName = value(row, mapping.column(for: .sessionName))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let signature = self.signature(date: date, name: sessionName, calendar: calendar, timeZone: timeZone)

            let importedSet = ImportedSet(
                exerciseName: exerciseName,
                setIndex: index.map { max(0, Int($0) - 1) } ?? (grouped[signature]?.sets.count ?? 0),
                weightKilograms: kilograms,
                reps: reps.map { Int($0) },
                durationSeconds: duration.map { Int($0) },
                distanceMeters: meters,
                effort: effort,
                isWarmup: kind == .warmup,
                notes: value(row, mapping.column(for: .notes)) ?? ""
            )

            if grouped[signature] == nil {
                order.append(signature)
                grouped[signature] = (
                    date: date,
                    name: sessionName.isEmpty ? "Séance importée" : sessionName,
                    notes: value(row, mapping.column(for: .sessionNotes)) ?? "",
                    sets: []
                )
            }
            grouped[signature]?.sets.append(importedSet)
        }

        var sessions: [ImportedSession] = []
        var duplicates: Set<String> = []
        for signature in order {
            guard let entry = grouped[signature] else { continue }
            if existingSignatures.contains(signature) { duplicates.insert(signature) }
            sessions.append(ImportedSession(
                date: entry.date,
                name: entry.name,
                notes: entry.notes,
                sets: entry.sets.sorted { $0.setIndex < $1.setIndex },
                signature: signature
            ))
        }

        let report = ImportReport(
            created: sessions.count - duplicates.count,
            merged: 0,
            ignored: 0,
            duplicates: duplicates.count,
            quarantined: quarantined.count,
            errors: []
        )

        return CSVImportPlan(
            sessions: sessions,
            duplicateSignatures: duplicates,
            quarantined: quarantined,
            report: report
        )
    }

    /// Cle de deduplication : date a la MINUTE et nom normalise. Deux
    /// exports du meme entrainement produisent la meme cle, meme si les
    /// secondes different d'un fichier a l'autre.
    public static func signature(date: Date, name: String, calendar: Calendar, timeZone: TimeZone) -> String {
        var calendar = calendar
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let stamp = String(
            format: "%04d-%02d-%02dT%02d:%02d",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0
        )
        return stamp + "|" + TextMatching.normalize(name)
    }

    private static func value(_ row: [String], _ index: Int?) -> String? {
        guard let index, index >= 0, index < row.count else { return nil }
        let trimmed = row[index].trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func number(
        _ row: [String],
        _ index: Int?,
        field: ImportField,
        failure: inout QuarantineReason?
    ) -> Double? {
        guard failure == nil, let raw = value(row, index) else { return nil }
        guard let parsed = NumberParsing.double(from: raw) else {
            failure = .unreadableNumber(field: field, value: raw)
            return nil
        }
        return parsed
    }

    private static func massUnit(_ row: [String], mapping: ColumnMapping) -> MassUnit {
        guard let raw = value(row, mapping.column(for: .weightUnit)) else { return mapping.defaultMassUnit }
        switch TextMatching.normalize(raw) {
        case "kg", "kgs", "kilogram", "kilograms", "kilogramme", "kilogrammes": return .kilograms
        case "lb", "lbs", "pound", "pounds", "livre", "livres": return .pounds
        default: return mapping.defaultMassUnit
        }
    }
}

enum SetKindParsing {
    enum Kind: Sendable { case normal, warmup }

    static func parse(_ raw: String) -> Kind? {
        let value = TextMatching.normalize(raw)
        guard !value.isEmpty else { return Kind.normal }
        switch value {
        case "normal", "working", "travail", "regular", "standard": return .normal
        case "warmup", "warm up", "echauffement", "prep": return .warmup
        // Ces types existent dans les exports tiers et restent des series
        // reelles : les traiter comme du travail est fidele, les rejeter ne
        // le serait pas.
        case "failure", "drop", "dropset", "echec", "restpause", "rest pause": return .normal
        default: return nil
        }
    }
}

enum NumberParsing {
    /// Accepte le point ET la virgule decimale, les espaces (y compris
    /// insecables) comme separateurs de milliers.
    static func double(from raw: String) -> Double? {
        let cleaned = raw
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: "\u{202F}", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty else { return nil }
        return Double(cleaned)
    }
}

enum DateParsing {
    private static let patterns = [
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd'T'HH:mm:ss",
        "yyyy-MM-dd HH:mm",
        "yyyy-MM-dd",
        "dd/MM/yyyy HH:mm",
        "dd/MM/yyyy",
        "MM/dd/yyyy HH:mm:ss",
        "d MMM yyyy, HH:mm",
        "d MMM yyyy HH:mm",
        "dd MMM yyyy, HH:mm",
    ]

    static func date(from raw: String, timeZone: TimeZone) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let iso = ISO8601DateFormatter()
        iso.timeZone = timeZone
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: trimmed) { return date }

        // Les formats explicites passent AVANT la date seule : avec l'option
        // `withFullDate`, « 2026-01-05 18:00:00 » serait accepte en ne lisant
        // que « 2026-01-05 », et l'heure disparaitrait en silence — au point
        // de faire echouer la deduplication.
        for pattern in patterns {
            let formatter = DateFormatter()
            // Locale POSIX : sans elle, « Jan » serait illisible sur un
            // appareil configure en francais, et l'import echouerait selon
            // la langue du telephone.
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timeZone
            formatter.dateFormat = pattern
            if let date = formatter.date(from: trimmed) { return date }
        }

        iso.formatOptions = [.withFullDate]
        if let date = iso.date(from: trimmed) { return date }
        return nil
    }
}
