import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import MuscuEngine

// Gestion des données : export CSV par jeu de données et suppression, par
// catégorie ou totale.
//
// Toute suppression est confirmée et rend compte de ce qui a réellement été
// supprimé : « vérifiable » signifie que l'utilisateur voit le résultat.
struct DataManagementView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var exportDocument: CSVDocument?
    @State private var exportFileName = "muscu"
    @State private var isExporting = false
    @State private var pendingDeletion: DataDeletion.Category?
    @State private var showingDeleteEverything = false
    @State private var resultMessage: ResultMessage?

    private struct ResultMessage: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    var body: some View {
        Form {
            Section {
                ForEach(CSVExport.Dataset.allCases) { dataset in
                    Button {
                        export(dataset)
                    } label: {
                        Label(dataset.displayName, systemImage: "tablecells")
                    }
                    .accessibilityIdentifier("csv.\(dataset.rawValue)")
                }
            } header: {
                Text("Export CSV")
            } footer: {
                Text("Fichiers lisibles par un tableur, en plus de l'export JSON complet. Les valeurs sont exportées dans leur unité de stockage : kilogrammes et centimètres.")
            }

            Section {
                ForEach(DataDeletion.Category.allCases) { category in
                    Button(role: .destructive) {
                        pendingDeletion = category
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(category.displayName)
                            Text(category.explanation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("delete.\(category.rawValue)")
                }
            } header: {
                Text("Supprimer par catégorie")
            } footer: {
                Text("La suppression est immédiate et définitive sur cet appareil. Exportez vos données avant si vous souhaitez les conserver.")
            }

            Section {
                Button(role: .destructive) {
                    showingDeleteEverything = true
                } label: {
                    Label("Tout supprimer", systemImage: "trash")
                }
                .accessibilityIdentifier("delete.everything")
            } footer: {
                Text("Supprime l'intégralité des données de l'application sur cet appareil.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Mes données")
        .navigationBarTitleDisplayMode(.inline)
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .commaSeparatedText,
            defaultFilename: exportFileName
        ) { _ in }
        .confirmationDialog(
            pendingDeletion.map { "Supprimer : \($0.displayName) ?" } ?? "",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive) {
                if let pendingDeletion { delete(pendingDeletion) }
                pendingDeletion = nil
            }
            Button("Annuler", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text(pendingDeletion?.explanation ?? "")
        }
        .confirmationDialog(
            "Supprimer toutes les données ?",
            isPresented: $showingDeleteEverything,
            titleVisibility: .visible
        ) {
            Button("Tout supprimer", role: .destructive) { deleteEverything() }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Programmes, historique, records, mesures, objectifs et profil seront supprimés de cet appareil. Cette action est irréversible.")
        }
        .alert(item: $resultMessage) { result in
            Alert(title: Text(result.title), message: Text(result.message), dismissButton: .default(Text("OK")))
        }
    }

    private func export(_ dataset: CSVExport.Dataset) {
        do {
            let csv = try CSVExport.csv(for: dataset, context: modelContext)
            exportDocument = CSVDocument(text: csv)
            exportFileName = dataset.fileName
            isExporting = true
        } catch {
            resultMessage = ResultMessage(
                title: "Export impossible",
                message: error.localizedDescription
            )
        }
    }

    private func delete(_ category: DataDeletion.Category) {
        do {
            let report = try DataDeletion.delete(category, context: modelContext)
            resultMessage = ResultMessage(title: "Suppression effectuée", message: report.summary)
        } catch {
            PersistenceSupport.report(error, action: "Suppression de \(category.displayName)")
        }
    }

    private func deleteEverything() {
        do {
            let report = try DataDeletion.deleteEverything(context: modelContext)
            resultMessage = ResultMessage(title: "Toutes les données supprimées", message: report.summary)
        } catch {
            PersistenceSupport.report(error, action: "Suppression totale")
        }
    }
}

/// Document CSV exporté via la feuille système.
struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    let text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        let data = configuration.file.regularFileContents ?? Data()
        text = String(data: data, encoding: .utf8) ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
