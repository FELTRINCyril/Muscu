import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import MuscuEngine

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

    @State private var exportDocument: ExportDocument?
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var importAlert: ImportAlert?

    private struct ImportAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    var body: some View {
        NavigationStack {
            Form {
                chronoSection
                imagesSection
                dataSection
                aiSection
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

    // MARK: - IA

    private var aiSection: some View {
        Section {
            NavigationLink("Génération IA (avancé)") {
                AIProviderConfigView()
            }
        } footer: {
            Text("Fonctionnalité optionnelle et non utilisée pour l'instant : permettra dans une future version de générer des programmes via un service IA externe.")
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

        await ImageStore.shared.prefetchAll(paths: paths) { done, total in
            Task { @MainActor in
                downloadDone = done
                downloadTotal = total
            }
        }

        isDownloadingImages = false
        downloadResultMessage = "\(downloadDone) image(s) sur \(downloadTotal) disponible(s) hors-ligne."
        refreshCacheSize()
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
                let summary = try ExportImport.importAll(data: data, context: modelContext)
                importAlert = ImportAlert(
                    title: "Import réussi",
                    message: "\(summary.programsCount) programme(s), \(summary.sessionsCount) séance(s), \(summary.recordsCount) record(s), \(summary.customExercisesCount) exercice(s) personnalisé(s) importés."
                )
            } catch {
                importAlert = ImportAlert(title: "Échec de l'import", message: error.localizedDescription)
            }
        }
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

// Configuration de la generation IA : provider, cle, modele, test de connexion.
private struct AIProviderConfigView: View {
    @State private var provider = AIProviderConfig.selectedProvider
    @State private var apiKey = AIProviderConfig.apiKey(for: AIProviderConfig.selectedProvider)
    @State private var model = AIProviderConfig.model(for: AIProviderConfig.selectedProvider)
    @State private var baseURL = AIProviderConfig.baseURL

    var body: some View {
        Form {
            Section("Fournisseur") {
                Picker("Fournisseur", selection: $provider) {
                    ForEach(AIProviderKind.allCases, id: \.self) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .pickerStyle(.menu)
            }

            Section {
                if provider.requiresBaseURL {
                    TextField("URL de base (https://.../v1)", text: $baseURL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                }
                SecureField("Clé API", text: $apiKey)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                TextField("Modèle", text: $model)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } header: {
                Text("Connexion")
            } footer: {
                Text("La clé API est stockée de façon chiffrée dans le trousseau de l'appareil. Une fois configurée, l'option \"Générer avec l'IA\" apparaît dans le générateur de programme.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Génération IA")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: provider) { _, newValue in
            AIProviderConfig.selectedProvider = newValue
            // Recharge les champs propres au provider selectionne.
            apiKey = AIProviderConfig.apiKey(for: newValue)
            model = AIProviderConfig.model(for: newValue)
        }
        .onChange(of: apiKey) { _, newValue in AIProviderConfig.setApiKey(newValue, for: provider) }
        .onChange(of: model) { _, newValue in AIProviderConfig.setModel(newValue, for: provider) }
        .onChange(of: baseURL) { _, newValue in AIProviderConfig.baseURL = newValue }
    }
}

#Preview {
    SettingsView()
        .environment(CatalogStore())
        .modelContainer(for: Program.self, inMemory: true)
        .preferredColorScheme(.dark)
}
