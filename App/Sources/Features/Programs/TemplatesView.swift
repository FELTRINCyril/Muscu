import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import MuscuEngine

/// Modeles de seance et de programme : creer, appliquer, dupliquer,
/// archiver et partager par fichier.
struct TemplatesView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \SessionTemplate.name) private var templates: [SessionTemplate]
    @Query(sort: \Program.name) private var programs: [Program]
    @Query(sort: \CompletedSession.date, order: .reverse) private var completedSessions: [CompletedSession]

    @State private var showArchived = false
    @State private var applying: SessionTemplate?
    @State private var creatingFromProgram = false
    @State private var creatingFromHistory = false
    @State private var exportDocument: ExportDocument?
    @State private var exportFilename = "modele"
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var message: String?

    private var visibleTemplates: [SessionTemplate] {
        templates
            .filter { $0.deletedAt == nil && (showArchived || !$0.isArchived) }
            .sorted { left, right in
                if left.isFavorite != right.isFavorite { return left.isFavorite }
                let leftDate = left.lastUsedAt ?? left.updatedAt
                let rightDate = right.lastUsedAt ?? right.updatedAt
                return leftDate > rightDate
            }
    }

    var body: some View {
        List {
            Section {
                Button("Depuis un programme existant") { creatingFromProgram = true }
                    .accessibilityIdentifier("templates.fromProgram")
                Button("Depuis une séance terminée") { creatingFromHistory = true }
                    .accessibilityIdentifier("templates.fromHistory")
                Button("Importer un fichier") { isImporting = true }
                    .accessibilityIdentifier("templates.import")
            } header: {
                Text("Créer")
            } footer: {
                Text("Un modèle créé depuis une séance terminée conserve les exercices et le nombre de séries, jamais les charges ni les répétitions réalisées.")
            }

            Section {
                Toggle("Afficher les modèles archivés", isOn: $showArchived)
                    .accessibilityIdentifier("templates.showArchived")
                if visibleTemplates.isEmpty {
                    Text("Aucun modèle.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(visibleTemplates, id: \.id) { template in
                    row(template)
                }
            } header: {
                Text("Modèles")
            }

            if let message {
                Section {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("templates.message")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Modèles")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $creatingFromProgram) { programPicker }
        .sheet(isPresented: $creatingFromHistory) { historyPicker }
        .sheet(item: $applying) { template in applyPicker(template) }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .json,
            defaultFilename: exportFilename
        ) { _ in }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            importTemplate(result)
        }
    }

    private func row(_ template: SessionTemplate) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(template.name)
                if template.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
                if template.isArchived {
                    Text("Archivé")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Text(subtitle(template))
                .font(.caption)
                .foregroundStyle(.secondary)
            if !template.notes.isEmpty {
                Text(template.notes)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .contextMenu {
            Button("Appliquer à un programme") { applying = template }
            Button("Dupliquer") { TemplateService.duplicate(template, in: modelContext) }
            Button(template.isFavorite ? "Retirer des favoris" : "Mettre en favori") {
                TemplateService.toggleFavorite(template, in: modelContext)
            }
            Button(template.isArchived ? "Désarchiver" : "Archiver") {
                TemplateService.setArchived(template, !template.isArchived, in: modelContext)
            }
            Button("Partager un fichier") { export(template) }
            Divider()
            Button("Supprimer", role: .destructive) { TemplateService.delete(template, in: modelContext) }
        }
        .swipeActions(edge: .trailing) {
            Button("Appliquer") { applying = template }
                .tint(Theme.accent)
        }
    }

    private func subtitle(_ template: SessionTemplate) -> String {
        let sessions = TemplateService.payload(of: template)?.sessions.count ?? 0
        return "\(template.scope.displayName) · version \(template.version) · \(sessions) séance(s)"
    }

    // MARK: - Feuilles

    private var programPicker: some View {
        NavigationStack {
            List {
                ForEach(programs.filter { $0.deletedAt == nil }, id: \.id) { program in
                    Section(program.name) {
                        Button("Tout le programme") {
                            TemplateService.makeTemplate(from: program, in: modelContext)
                            message = "Modèle « \(program.name) » créé."
                            creatingFromProgram = false
                        }
                        ForEach(program.orderedSessions, id: \.id) { session in
                            Button(session.name) {
                                TemplateService.makeTemplate(from: session, in: modelContext)
                                message = "Modèle « \(session.name) » créé."
                                creatingFromProgram = false
                            }
                        }
                    }
                }
            }
            .navigationTitle("Choisir la source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { creatingFromProgram = false }
                }
            }
        }
    }

    private var historyPicker: some View {
        NavigationStack {
            List {
                ForEach(completedSessions.filter { $0.deletedAt == nil }.prefix(50), id: \.id) { session in
                    Button {
                        TemplateService.makeTemplate(fromCompleted: session, in: modelContext)
                        message = "Modèle créé depuis « \(session.sessionName) », sans les performances."
                        creatingFromHistory = false
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.sessionName.isEmpty ? "Séance" : session.sessionName)
                            Text(session.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Séance terminée")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { creatingFromHistory = false }
                }
            }
        }
    }

    private func applyPicker(_ template: SessionTemplate) -> some View {
        NavigationStack {
            List {
                Section {
                    ForEach(programs.filter { $0.deletedAt == nil }, id: \.id) { program in
                        Button(program.name) {
                            let created = TemplateService.apply(template, to: program, in: modelContext)
                            message = "\(created.count) séance(s) ajoutée(s) à « \(program.name) »."
                            applying = nil
                        }
                    }
                } footer: {
                    Text("Les séances du modèle sont ajoutées au programme choisi. Rien n’est remplacé.")
                }
            }
            .navigationTitle("Appliquer à")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { applying = nil }
                }
            }
        }
    }

    // MARK: - Fichier

    private func export(_ template: SessionTemplate) {
        do {
            exportDocument = ExportDocument(data: try TemplateService.exportData(template))
            exportFilename = "modele-" + TextMatching.normalize(template.name).replacingOccurrences(of: " ", with: "-")
            isExporting = true
        } catch {
            message = "Export impossible : \(error.localizedDescription)"
        }
    }

    private func importTemplate(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let needsAccess = url.startAccessingSecurityScopedResource()
            defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let template = try TemplateService.importTemplate(from: data, in: modelContext)
                message = "Modèle « \(template.name) » importé."
            } catch {
                message = "Fichier illisible : \(error.localizedDescription). Rien n’a été modifié."
            }
        case .failure(let error):
            message = "Import annulé : \(error.localizedDescription)"
        }
    }
}
