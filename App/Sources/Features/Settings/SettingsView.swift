import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// Onglet Reglages : chrono, cache d'images, export/import des donnees,
// configuration IA (avancee, masquee) et a propos.
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(CatalogStore.self) private var catalogStore

    @AppStorage("soundEnabled") private var soundEnabled = true
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @AppStorage("defaultRestSeconds") private var defaultRestSeconds = 90

    @State private var cacheSizeBytes: Int64 = 0
    @State private var isDownloadingImages = false
    @State private var downloadDone = 0
    @State private var downloadTotal = 0
    @State private var downloadResultMessage: String?
    @State private var showingClearCacheConfirmation = false

    @State private var exportDocument: ExportDocument?
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var importAlert: ImportAlert?
    @State private var pendingImport: PendingImport?

    private struct ImportAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    private struct PendingImport {
        let data: Data
        let summary: ExportImport.ImportSummary
    }

    var body: some View {
        NavigationStack {
            Form {
            Section {
                NavigationLink {
                    ProfileView()
                } label: {
                    Label("Profil", systemImage: "person.crop.circle")
                }
                .accessibilityIdentifier("settings.profile")

                NavigationLink {
                    DataManagementView()
                } label: {
                    Label("Mes données", systemImage: "externaldrive")
                }
                .accessibilityIdentifier("settings.data")
            } footer: {
                Text("Objectif, niveau, matériel, jours disponibles et charges réellement disponibles. Facultatif.")
            }

                chronoSection
                imagesSection
                dataSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Réglages")
            .task {
                refreshCacheSize()
            }
            .fileExporter(
                isPresented: $isExporting,
                document: exportDocument,
                contentType: .json,
                defaultFilename: exportFilename
            ) { _ in }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.json]
            ) { result in
                handleImport(result)
            }
            .alert(item: $importAlert) { alert in
                Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")))
            }
            .confirmationDialog("Vider toutes les images hors ligne ?", isPresented: $showingClearCacheConfirmation) {
                Button("Vider le cache", role: .destructive) { clearImageCache() }
                Button("Annuler", role: .cancel) {}
            }
            .confirmationDialog(
                "Confirmer l’import ?",
                isPresented: Binding(
                    get: { pendingImport != nil },
                    set: { if !$0 { pendingImport = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Importer") { confirmImport() }
                Button("Annuler", role: .cancel) { pendingImport = nil }
            } message: {
                if let summary = pendingImport?.summary {
                    Text(importSummaryMessage(summary, suffix: summary.hasActiveWorkout ? " Une séance en cours est aussi incluse." : ""))
                }
            }
        }
    }

    // MARK: - Chrono

    private var chronoSection: some View {
        Section("Chrono") {
            Toggle("Sons", isOn: $soundEnabled)
            Toggle("Vibrations", isOn: $hapticsEnabled)
            Stepper(
                "Repos par défaut : \(Self.formatDuration(defaultRestSeconds))",
                value: $defaultRestSeconds,
                in: 15...300,
                step: 15
            )
        }
    }

    // MARK: - Images

    private var imagesSection: some View {
        Section {
            LabeledContent("Cache utilisé", value: Self.formatBytes(cacheSizeBytes))

            Button {
                Task { await downloadAllImages() }
            } label: {
                if isDownloadingImages {
                    HStack {
                        ProgressView()
                        Text("\(downloadDone)/\(downloadTotal)")
                    }
                } else {
                    Text("Tout télécharger")
                }
            }
            .disabled(isDownloadingImages)

            Button("Vider le cache", role: .destructive) {
                showingClearCacheConfirmation = true
            }
            .disabled(isDownloadingImages || cacheSizeBytes == 0)

            if let downloadResultMessage {
                Text(downloadResultMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Images des exercices")
        } footer: {
            Text("Nécessite une connexion internet.")
        }
    }

    // MARK: - Donnees

    private var dataSection: some View {
        Section("Données") {
            Button("Exporter mes données") {
                exportData()
            }

            Button("Importer des données") {
                isImporting = true
            }
        }
    }

    // MARK: - A propos

    private var aboutSection: some View {
        Section("À propos") {
            LabeledContent("Version", value: appVersion)
            Link(destination: URL(string: "https://github.com/FELTRINCyril/Muscu")!) {
                Text("Code source sur GitHub")
            }
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
    }

    // MARK: - Actions

    private func refreshCacheSize() {
        Task {
            let bytes = await ImageStore.shared.cacheSizeBytes()
            cacheSizeBytes = bytes
        }
    }

    private func downloadAllImages() async {
        let paths = catalogStore.all.flatMap(\.images)
        isDownloadingImages = true
        downloadDone = 0
        downloadTotal = paths.count
        downloadResultMessage = nil

        let result = await ImageStore.shared.prefetchAll(paths: paths) { done, total in
            Task { @MainActor in
                downloadDone = done
                downloadTotal = total
            }
        }

        isDownloadingImages = false
        downloadResultMessage = result.failed == 0
            ? "\(result.available) image(s) disponible(s) hors-ligne."
            : "\(result.available)/\(result.total) disponible(s), \(result.failed) échec(s). Réessayez lorsque la connexion est stable."
        refreshCacheSize()
    }

    private func clearImageCache() {
        Task {
            do {
                try await ImageStore.shared.clearCache()
                downloadDone = 0
                downloadTotal = 0
                downloadResultMessage = "Cache d’images vidé."
                refreshCacheSize()
            } catch {
                importAlert = ImportAlert(title: "Échec", message: error.localizedDescription)
            }
        }
    }

    private func exportData() {
        do {
            let data = try ExportImport.exportAll(context: modelContext)
            exportDocument = ExportDocument(data: data)
            isExporting = true
        } catch {
            importAlert = ImportAlert(
                title: "Échec de l'export",
                message: error.localizedDescription
            )
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            importAlert = ImportAlert(title: "Échec de l'import", message: error.localizedDescription)
        case .success(let url):
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }

            do {
                let data = try Data(contentsOf: url)
                pendingImport = PendingImport(data: data, summary: try ExportImport.preview(data: data))
            } catch {
                importAlert = ImportAlert(title: "Échec de l'import", message: error.localizedDescription)
            }
        }
    }

    private func confirmImport() {
        guard let pendingImport else { return }
        self.pendingImport = nil
        do {
            let summary = try ExportImport.importAll(data: pendingImport.data, context: modelContext)
            importAlert = ImportAlert(
                title: "Import réussi",
                message: importSummaryMessage(summary, suffix: summary.hasActiveWorkout ? " La séance en cours a été restaurée." : "")
            )
        } catch {
            importAlert = ImportAlert(title: "Échec de l'import", message: error.localizedDescription)
        }
    }

    // Resume lisible d'une archive : seuls les types reellement presents sont
    // listes, pour que l'apercu reste court sur une sauvegarde v1/v2.
    private func importSummaryMessage(_ summary: ExportImport.ImportSummary, suffix: String) -> String {
        var parts = [
            "\(summary.programsCount) programme(s)",
            "\(summary.sessionsCount) séance(s)",
            "\(summary.recordsCount) record(s)",
            "\(summary.customExercisesCount) exercice(s) personnalisé(s)",
        ]
        if summary.hasProfile { parts.append("1 profil") }
        if summary.measurementsCount > 0 { parts.append("\(summary.measurementsCount) mesure(s)") }
        if summary.readinessEntriesCount > 0 { parts.append("\(summary.readinessEntriesCount) check-in") }
        if summary.personalBestsCount > 0 { parts.append("\(summary.personalBestsCount) record(s) typé(s)") }
        if summary.trainingPlansCount > 0 { parts.append("\(summary.trainingPlansCount) plan(s)") }

        let version = summary.sourceVersion < ExportImport.currentVersion
            ? " Sauvegarde au format v\(summary.sourceVersion), convertie au format actuel."
            : ""
        return parts.joined(separator: ", ") + "." + version + suffix
    }

    private var exportFilename: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "muscu-export-\(formatter.string(from: Date()))"
    }

    // MARK: - Formatage

    private static func formatDuration(_ seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds) s"
        }
        let minutes = seconds / 60
        let remainder = seconds % 60
        return remainder == 0 ? "\(minutes) min" : "\(minutes) min \(remainder)"
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// Document minimal pour l'export : enveloppe des octets JSON deja produits
// par ExportImport.exportAll, sans re-encodage.
struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

#Preview {
    SettingsView()
        .environment(CatalogStore())
        .modelContainer(for: Program.self, inMemory: true)
        .preferredColorScheme(.dark)
}
