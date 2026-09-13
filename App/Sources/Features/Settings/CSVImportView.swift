import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import MuscuEngine

/// Assistant d'import CSV : fichier, correspondance des colonnes, aperçu,
/// puis écriture confirmée.
///
/// Rien n'est écrit avant la dernière étape. L'aperçu montre exactement ce
/// qui sera créé et ce qui sera mis de côté.
struct CSVImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(CatalogStore.self) private var catalogStore

    @State private var isPickingFile = false
    @State private var fileName = ""
    @State private var header: [String] = []
    @State private var rows: [[String]] = []
    @State private var preset: CSVImportPreset = .generic
    @State private var mapping = ColumnMapping()
    @State private var plan: CSVImportPlan?
    @State private var policy: CSVImportPolicy = .skipDuplicates
    @State private var outcome: CSVImportOutcome?
    @State private var errorMessage: String?

    var body: some View {
        List {
            fileSection
            if !header.isEmpty { mappingSection }
            if let plan { previewSection(plan) }
            if let outcome { reportSection(outcome) }
            quarantineSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Importer un CSV")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $isPickingFile,
            allowedContentTypes: [.commaSeparatedText, .plainText, .text, .data]
        ) { result in
            load(result)
        }
    }

    // MARK: - Fichier

    private var fileSection: some View {
        Section {
            Button("Choisir un fichier") { isPickingFile = true }
                .accessibilityIdentifier("csv.pick")
            if !fileName.isEmpty {
                LabeledContent("Fichier", value: fileName)
                LabeledContent("Format détecté", value: preset.displayName)
                LabeledContent("Lignes de données", value: "\(max(0, rows.count - 1))")
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("csv.error")
            }
        } header: {
            Text("Source")
        } footer: {
            Text("Formats reconnus : CSV générique, Strong et Hevy. Les exports de ces applications sont publiquement documentés.")
        }
    }

    // MARK: - Correspondance

    private var mappingSection: some View {
        Section {
            ForEach(Array(header.enumerated()), id: \.offset) { index, title in
                Picker(title.isEmpty ? "Colonne \(index + 1)" : title, selection: binding(for: index)) {
                    ForEach(ImportField.allCases) { field in
                        Text(field.displayName).tag(field)
                    }
                }
                .pickerStyle(.navigationLink)
            }

            if !mapping.missingRequiredFields.isEmpty {
                Label(
                    "Colonnes obligatoires manquantes : " + mapping.missingRequiredFields.map(\.displayName).joined(separator: ", "),
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }

            Picker("Unité des charges", selection: unitBinding) {
                Text("Kilogrammes").tag(MassUnit.kilograms)
                Text("Livres").tag(MassUnit.pounds)
            }
            Toggle("Distances en kilomètres", isOn: distanceBinding)

            Button("Analyser") { analyse() }
                .disabled(!mapping.isUsable)
                .accessibilityIdentifier("csv.analyse")
        } header: {
            Text("Colonnes")
        } footer: {
            Text("Une colonne « Ignorée » n’est jamais lue. La date et le nom d’exercice sont obligatoires.")
        }
    }

    // MARK: - Aperçu

    private func previewSection(_ plan: CSVImportPlan) -> some View {
        Section {
            LabeledContent("Séances trouvées", value: "\(plan.sessions.count)")
            LabeledContent("Doublons", value: "\(plan.duplicateSignatures.count)")
            LabeledContent("En quarantaine", value: "\(plan.quarantined.count)")

            ForEach(plan.sessions.prefix(5)) { session in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(session.name)
                        if plan.duplicateSignatures.contains(session.signature) {
                            Text("Doublon")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                    Text("\(session.date.formatted(date: .abbreviated, time: .shortened)) · \(session.sets.count) série(s)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            if plan.sessions.count > 5 {
                Text("… et \(plan.sessions.count - 5) autre(s).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(plan.quarantined.prefix(5)) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ligne \(row.rowNumber) : \(row.reason.explanation)")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text(row.raw.joined(separator: " | "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Picker("Doublons", selection: $policy) {
                ForEach(CSVImportPolicy.allCases) { value in
                    Text(value.displayName).tag(value)
                }
            }
            .pickerStyle(.segmented)

            Button("Importer") { apply(plan) }
                .disabled(plan.sessions.isEmpty)
                .accessibilityIdentifier("csv.import")

            ForEach(plan.report.errors, id: \.self) { error in
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Aperçu")
        } footer: {
            Text("Une séance terminée est immuable : l’import ne fusionne jamais dans une séance existante, il crée ou il laisse de côté.")
        }
    }

    private func reportSection(_ outcome: CSVImportOutcome) -> some View {
        Section {
            Text(outcome.report.summary)
                .accessibilityIdentifier("csv.report")
            if !outcome.didWrite {
                Text("L’enregistrement a échoué : rien n’a été modifié.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if !outcome.unmatchedExerciseNames.isEmpty {
                Text("Exercices non reconnus, importés sous leur nom d’origine : " + outcome.unmatchedExerciseNames.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Rapport")
        }
    }

    private var quarantineSection: some View {
        let entries = CSVImportService.quarantine(in: modelContext)
        return Section {
            if entries.isEmpty {
                Text("Aucune ligne en quarantaine.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(entries.prefix(20), id: \.id) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ligne \(entry.rowNumber) · \(entry.sourceName)")
                        .font(.caption.weight(.semibold))
                    Text(entry.reason)
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text(entry.rawRow)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            if !entries.isEmpty {
                Button("Marquer comme traitées", role: .destructive) {
                    CSVImportService.clearQuarantine(in: modelContext)
                }
                .accessibilityIdentifier("csv.clearQuarantine")
            }
        } header: {
            Text("Quarantaine")
        } footer: {
            Text("Les lignes conservées ici n’ont pas pu être interprétées. Elles sont gardées telles quelles pour que vous puissiez corriger le fichier.")
        }
    }

    // MARK: - Liaisons

    private func binding(for index: Int) -> Binding<ImportField> {
        Binding(
            get: { mapping.assignments[index] ?? .ignored },
            set: { field in
                // Un champ ne peut etre associe qu'a UNE colonne : sinon
                // deux colonnes se disputeraient la meme valeur.
                if field != .ignored {
                    for (key, value) in mapping.assignments where value == field && key != index {
                        mapping.assignments[key] = .ignored
                    }
                }
                mapping.assignments[index] = field
                plan = nil
            }
        )
    }

    private var unitBinding: Binding<MassUnit> {
        Binding(get: { mapping.defaultMassUnit }, set: { mapping.defaultMassUnit = $0; plan = nil })
    }

    private var distanceBinding: Binding<Bool> {
        Binding(get: { mapping.distanceIsKilometers }, set: { mapping.distanceIsKilometers = $0; plan = nil })
    }

    // MARK: - Actions

    private func load(_ result: Result<URL, Error>) {
        reset()
        switch result {
        case .success(let url):
            let needsAccess = url.startAccessingSecurityScopedResource()
            defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                    errorMessage = "Le fichier n’est pas un texte lisible."
                    return
                }
                let parsed = try CSVImportService.makeParser(for: text).parse(text)
                fileName = url.lastPathComponent
                rows = parsed
                header = parsed[0]
                preset = CSVImportPreset.detect(header: header)
                mapping = ColumnMapping.suggested(header: header, preset: preset)
            } catch {
                errorMessage = "Fichier illisible : \(error). Rien n’a été modifié."
            }
        case .failure(let error):
            errorMessage = "Import annulé : \(error.localizedDescription)"
        }
    }

    private func reset() {
        errorMessage = nil
        plan = nil
        outcome = nil
        header = []
        rows = []
        fileName = ""
    }

    private func analyse() {
        plan = CSVImportPlanner.plan(
            rows: rows,
            mapping: mapping,
            existingSignatures: CSVImportService.existingSignatures(in: modelContext),
            calendar: .current,
            timeZone: .current
        )
        outcome = nil
    }

    private func apply(_ plan: CSVImportPlan) {
        outcome = CSVImportService.apply(
            plan,
            policy: policy,
            sourceName: preset == .generic ? "CSV" : preset.displayName,
            catalog: catalogStore.catalog,
            in: modelContext
        )
        self.plan = nil
    }
}
