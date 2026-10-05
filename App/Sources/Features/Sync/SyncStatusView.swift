import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import MuscuEngine

// État de la synchronisation : ce qui est activé, ce qui reste à envoyer, ce
// qui a échoué et pourquoi, les conflits à trancher, et un diagnostic
// exportable.
//
// L'écran dit toujours la vérité sur l'état réel, y compris « pas encore
// configuré » : c'est préférable à une case à cocher qui ne ferait rien.
struct SyncStatusView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var service: SyncService?
    @State private var availability: SyncAvailability?
    @State private var diagnosticDocument: DiagnosticDocument?
    @State private var isExportingDiagnostic = false

    var body: some View {
        Form {
            statusSection
            if let service, service.status.isEnabled {
                pendingSection(service)
            }
            if let service, !service.conflicts.isEmpty {
                conflictSection(service)
            }
            diagnosticSection
            explanationSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Synchronisation")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if service == nil {
                service = SyncService(modelContext: modelContext, transport: CloudKitSyncTransport())
            }
            availability = await CloudKitSyncTransport().availability()
        }
        .fileExporter(
            isPresented: $isExportingDiagnostic,
            document: diagnosticDocument,
            contentType: .plainText,
            defaultFilename: "muscu-diagnostic-synchronisation"
        ) { _ in }
    }

    // MARK: - Sections

    @ViewBuilder
    private var statusSection: some View {
        Section {
            if let blocking = availability?.failure, blocking == .notConfigured {
                // On ne propose pas un interrupteur qui ne ferait rien.
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Synchronisation indisponible")
                            .font(.body.weight(.medium))
                        Text(SyncFailureKind.notConfigured.userMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "icloud.slash")
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("sync.unavailable")
            } else if let service {
                Toggle("Synchroniser avec iCloud", isOn: Binding(
                    get: { service.status.isEnabled },
                    set: { enable in
                        service.setEnabled(enable)
                        if enable { try? service.enqueueEverything() }
                    }
                ))
                .accessibilityIdentifier("sync.toggle")
            }

            if let service {
                LabeledContent("État", value: service.status.summary)
                    .accessibilityIdentifier("sync.summary")
            }
        } header: {
            Text("iCloud")
        } footer: {
            Text("Vos données restent utilisables hors ligne en permanence. La synchronisation ne fait que les recopier entre vos appareils.")
        }
    }

    private func pendingSection(_ service: SyncService) -> some View {
        Section {
            LabeledContent("En attente d'envoi", value: "\(service.status.pendingCount)")
            LabeledContent(
                "Dernière synchronisation",
                value: service.status.lastSuccessAt.map(Self.dateFormatter.string(from:)) ?? "aucune"
            )
            if let failure = service.status.lastFailure {
                Label(failure.userMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Button {
                Task { await service.synchronize() }
            } label: {
                Label("Synchroniser maintenant", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(service.isSyncing)
            .accessibilityIdentifier("sync.now")
        } header: {
            Text("File d'attente")
        }
    }

    private func conflictSection(_ service: SyncService) -> some View {
        Section {
            ForEach(service.conflicts, id: \.identifier) { conflict in
                VStack(alignment: .leading, spacing: 6) {
                    Text(Self.kindLabel(conflict.kind))
                        .font(.subheadline.weight(.semibold))
                    Text("Modifié ici le \(Self.dateFormatter.string(from: conflict.localUpdatedAt)), et sur un autre appareil le \(Self.dateFormatter.string(from: conflict.remoteUpdatedAt)).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Garder cet appareil") { service.resolveKeepingLocal(conflict) }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.accent)
                        Button("Prendre l'autre") { service.resolveTakingRemote(conflict) }
                            .buttonStyle(.bordered)
                    }
                    .font(.footnote)
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Conflits à trancher")
        } footer: {
            Text("Les deux versions ont été conservées. Rien n'a été supprimé : choisissez celle à garder.")
        }
    }

    private var diagnosticSection: some View {
        Section {
            Button {
                guard let service else { return }
                diagnosticDocument = DiagnosticDocument(text: service.diagnosticReport())
                isExportingDiagnostic = true
            } label: {
                Label("Exporter un diagnostic", systemImage: "doc.text")
            }
            .accessibilityIdentifier("sync.diagnostic")
        } footer: {
            Text("Le diagnostic contient des dates, des compteurs et des codes d'erreur. Il ne contient aucune séance, aucune mesure et aucune donnée personnelle.")
        }
    }

    private var explanationSection: some View {
        Section {
            Text("Une séance terminée n'est jamais réécrite par un autre appareil. Une suppression ne l'emporte que si elle est plus récente que la modification concurrente. En cas de doute, les deux versions sont conservées et vous tranchez.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Comment les conflits sont résolus")
        }
    }

    // MARK: - Libellés

    private static func kindLabel(_ kind: SyncEntityKind) -> String {
        switch kind {
        case .program: return "Programme"
        case .completedSession: return "Séance terminée"
        case .activeWorkout: return "Séance en cours"
        case .exerciseRecord, .personalBest: return "Record"
        case .customExercise: return "Exercice personnalisé"
        case .athleteProfile: return "Profil"
        case .bodyMeasurement: return "Mesure"
        case .readinessEntry: return "Check-in"
        case .healthWorkoutLink: return "Lien Santé"
        case .trainingPlan: return "Plan"
        case .trainingGoal: return "Objectif"
        case .adaptationEntry: return "Adaptation"
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

/// Diagnostic exporté : texte brut, sans donnée métier.
struct DiagnosticDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }

    let text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        text = String(data: configuration.file.regularFileContents ?? Data(), encoding: .utf8) ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
