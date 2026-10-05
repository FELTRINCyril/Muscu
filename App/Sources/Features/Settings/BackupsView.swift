import SwiftUI
import SwiftData
import MuscuEngine

// Sauvegardes automatiques : reglage, liste (date, taille), restauration et
// partage. La restauration passe par l'import existant en mode Remplacer.
struct BackupsView: View {
    @Environment(\.modelContext) private var modelContext

    @AppStorage(AutoBackupService.enabledKey) private var isEnabled = false
    @State private var backups: [AutoBackupService.Backup] = []
    @State private var pendingRestore: AutoBackupService.Backup?
    @State private var resultMessage: ResultMessage?

    private struct ResultMessage: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    var body: some View {
        Form {
            Section {
                Toggle("Sauvegarde automatique", isOn: $isEnabled)
                    .accessibilityIdentifier("backups.toggle")
                    .onChange(of: isEnabled) { _, enabled in
                        // Premiere sauvegarde des l'activation : attendre le
                        // passage en arriere-plan laisserait croire que rien
                        // ne se passe.
                        if enabled { backUpIfDue() }
                    }
                Button("Sauvegarder maintenant") { backUpNow() }
                    .accessibilityIdentifier("backups.now")
            } footer: {
                Text("Au plus une fois par jour, au passage en arrière-plan ou après une séance terminée, l’export complet de vos données est écrit dans l’app Fichiers (Sur mon iPhone › Muscu › Sauvegardes). Les \(AutoBackupPolicy.defaultRetainedCount) plus récentes sont conservées. Les photos de progression n’y figurent pas, comme dans l’export.")
            }

            Section {
                if backups.isEmpty {
                    Text("Aucune sauvegarde pour l’instant.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(backups) { backup in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(backup.date.formatted(date: .abbreviated, time: .shortened))
                            Text(ByteCountFormatter.string(fromByteCount: backup.sizeBytes, countStyle: .file))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        ShareLink(item: backup.url) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Partager")
                        Button("Restaurer") { pendingRestore = backup }
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("backups.restore")
                    }
                    .accessibilityElement(children: .contain)
                }
            } header: {
                Text("Sauvegardes")
            } footer: {
                Text("Restaurer remplace toutes les données de l’appareil par celles de la sauvegarde. Une sauvegarde de sécurité de l’état actuel est créée avant, et rétablie si la restauration échoue.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Sauvegardes")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
        .confirmationDialog(
            "Restaurer cette sauvegarde ?",
            isPresented: Binding(
                get: { pendingRestore != nil },
                set: { if !$0 { pendingRestore = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Restaurer", role: .destructive) {
                if let pendingRestore { restore(pendingRestore) }
                pendingRestore = nil
            }
            Button("Annuler", role: .cancel) { pendingRestore = nil }
        } message: {
            if let backup = pendingRestore {
                Text("Les données actuelles seront remplacées par celles du \(backup.date.formatted(date: .long, time: .shortened)). \(ExportImport.ImportMode.replace.explanation)")
            }
        }
        .alert(item: $resultMessage) { result in
            Alert(title: Text(result.title), message: Text(result.message), dismissButton: .default(Text("OK")))
        }
    }

    private func reload() {
        backups = AutoBackupService.backups()
    }

    private func backUpIfDue() {
        AutoBackupService.runIfDue(context: modelContext)
        reload()
    }

    private func backUpNow() {
        do {
            try AutoBackupService.backUpNow(context: modelContext)
            reload()
        } catch {
            resultMessage = ResultMessage(title: String(localized: "Sauvegarde impossible"), message: error.localizedDescription)
        }
    }

    private func restore(_ backup: AutoBackupService.Backup) {
        do {
            let result = try AutoBackupService.restore(backup, context: modelContext)
            reload()
            resultMessage = ResultMessage(
                title: String(localized: "Sauvegarde restaurée"),
                message: String(localized: "\(result.summary.sessionsCount) séance(s), \(result.summary.programsCount) programme(s) et \(result.summary.recordsCount) record(s) restaurés. Une sauvegarde de sécurité de l’état précédent a été créée sur cet appareil.")
            )
        } catch {
            resultMessage = ResultMessage(title: String(localized: "Restauration impossible"), message: error.localizedDescription)
        }
    }
}
