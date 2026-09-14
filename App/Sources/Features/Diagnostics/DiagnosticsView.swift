import SwiftUI
import SwiftData
import MuscuEngine

/// Écran de diagnostic.
///
/// Il montre l'état du stockage, laisse couper le journal et permet d'en
/// partager le contenu — après l'avoir lu. Rien n'est envoyé
/// automatiquement : l'export est un geste volontaire, et le texte partagé
/// est exactement celui affiché ici.
struct DiagnosticsView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var isEnabled = DiagnosticsCenter.isEnabled
    @State private var events: [DiagnosticEvent] = []
    @State private var health: DiagnosticStoreHealth?
    @State private var isShowingReport = false

    var body: some View {
        List {
            explanationSection
            switchSection
            healthSection
            journalSection
            exportSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Diagnostic")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refresh)
        .sheet(isPresented: $isShowingReport) {
            DiagnosticReportSheet(text: reportText)
        }
    }

    // MARK: - Sections

    private var explanationSection: some View {
        Section {
            Label("Le journal ne retient que des codes d’erreur, des versions et des compteurs.", systemImage: "doc.text.magnifyingglass")
                .font(.callout)
            Label("Aucune séance, mesure, donnée de santé ni clé d’API n’y figure.", systemImage: "hand.raised")
                .font(.callout)
                .foregroundStyle(.secondary)
            Label("Rien n’est envoyé : le partage se fait depuis cet écran, après lecture.", systemImage: "wifi.slash")
                .font(.callout)
                .foregroundStyle(.secondary)
        } header: {
            Text("Ce que contient le journal")
        }
    }

    private var switchSection: some View {
        Section {
            Toggle("Journal local", isOn: $isEnabled)
                .accessibilityIdentifier("diagnostics.enabled")
                .onChange(of: isEnabled) { _, value in
                    DiagnosticsCenter.isEnabled = value
                    refresh()
                }
        } footer: {
            Text(isEnabled
                 ? "Le journal garde au plus \(DiagnosticsBuffer.defaultCapacity) lignes ; les plus anciennes disparaissent d’elles-mêmes."
                 : "Le journal est éteint et les lignes déjà enregistrées ont été effacées.")
        }
    }

    @ViewBuilder
    private var healthSection: some View {
        if let health {
            Section("Santé du stockage") {
                LabeledContent("Schéma", value: "v\(health.schemaVersion)")
                    .accessibilityIdentifier("diagnostics.schema")
                LabeledContent("Migration") {
                    Label(
                        health.migrationSucceeded ? "Réussie" : "Échouée",
                        systemImage: health.migrationSucceeded ? "checkmark.circle" : "exclamationmark.triangle"
                    )
                    // L'information n'est jamais portée par la seule couleur :
                    // le symbole ET le texte la donnent.
                    .foregroundStyle(health.migrationSucceeded ? Color.secondary : Color.orange)
                    .labelStyle(.titleAndIcon)
                }
                .accessibilityIdentifier("diagnostics.migration")

                ForEach(health.entityCounts.keys.sorted(), id: \.self) { name in
                    LabeledContent(name, value: countText(health.entityCounts[name] ?? 0))
                }

                LabeledContent("Synchronisation en attente", value: "\(health.pendingSyncOperations)")
                LabeledContent("Conflits non résolus", value: "\(health.unresolvedConflicts)")
                LabeledContent("Dernière synchronisation", value: dateText(health.lastSyncSuccess))
                LabeledContent("Dernière sauvegarde", value: dateText(health.lastBackup))
                    .accessibilityIdentifier("diagnostics.lastBackup")
            }
        }
    }

    @ViewBuilder
    private var journalSection: some View {
        Section {
            if !isEnabled {
                Text("Journal désactivé.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("diagnostics.disabled")
            } else if events.isEmpty {
                Text("Aucun événement enregistré. C’est le cas normal.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("diagnostics.empty")
            } else {
                ForEach(events) { event in
                    row(for: event)
                }
            }
        } header: {
            Text("Journal (\(events.count))")
        }
    }

    private func row(for event: DiagnosticEvent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: symbol(for: event.level))
                    .foregroundStyle(color(for: event.level))
                Text(event.code)
                    .font(.callout.monospaced())
                Spacer()
                Text(event.date, format: .dateTime.day().month().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !event.detail.isEmpty {
                Text(event.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(event.category.displayName)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        // Une seule annonce VoiceOver, dans l'ordre utile : gravité, sujet,
        // code, puis détail.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(levelName(event.level)), \(event.category.displayName), \(event.code)"
                + (event.detail.isEmpty ? "" : ", \(event.detail)")
        )
    }

    private var exportSection: some View {
        Section {
            Button {
                isShowingReport = true
            } label: {
                Label("Lire et partager le diagnostic", systemImage: "square.and.arrow.up")
            }
            .accessibilityIdentifier("diagnostics.export")

            Button(role: .destructive) {
                DiagnosticsCenter.clear()
                refresh()
            } label: {
                Label("Effacer le journal", systemImage: "trash")
            }
            .accessibilityIdentifier("diagnostics.clear")
            .disabled(events.isEmpty)
        } footer: {
            Text("Le diagnostic s’affiche en entier avant d’être partagé : vous voyez exactement ce qui part.")
        }
    }

    // MARK: - Etat

    private func refresh() {
        isEnabled = DiagnosticsCenter.isEnabled
        events = DiagnosticsCenter.events
        health = DiagnosticsHealth.snapshot(context: modelContext, migrationSucceeded: true)
    }

    private var reportText: String {
        DiagnosticReportBuilder.text(
            environment: DiagnosticsCenter.environment,
            health: health ?? DiagnosticsHealth.snapshot(context: modelContext, migrationSucceeded: true),
            events: events,
            generatedAt: .now
        )
    }

    private func countText(_ value: Int) -> String {
        value < 0 ? "illisible" : "\(value)"
    }

    private func dateText(_ date: Date?) -> String {
        guard let date else { return "aucune" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func symbol(for level: DiagnosticLevel) -> String {
        switch level {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .failure: return "xmark.octagon"
        }
    }

    private func color(for level: DiagnosticLevel) -> Color {
        switch level {
        case .info: return .secondary
        case .warning: return .orange
        case .failure: return .red
        }
    }

    private func levelName(_ level: DiagnosticLevel) -> String {
        switch level {
        case .info: return "Information"
        case .warning: return "Avertissement"
        case .failure: return "Échec"
        }
    }
}

/// Le rapport est affiché en entier avant tout partage : c'est la seule
/// façon honnête de demander un consentement.
private struct DiagnosticReportSheet: View {
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .accessibilityIdentifier("diagnostics.reportText")
            }
            .background(Theme.background)
            .navigationTitle("Diagnostic")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                        .accessibilityIdentifier("diagnostics.reportClose")
                }
                ToolbarItem(placement: .confirmationAction) {
                    ShareLink(item: text) {
                        Label("Partager", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("diagnostics.share")
                }
            }
        }
    }
}
