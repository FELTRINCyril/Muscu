import SwiftUI
import SwiftData
import MuscuEngine

/// Réglages du coach IA : disponibilité, fournisseur, consentement, budget
/// et diagnostic.
///
/// L'écran dit d'abord ce qui NE part pas. Un consentement qu'on ne peut pas
/// relire n'en est pas un.
struct AISettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var isEnabled = AISettings.isEnabled
    @State private var endpoint = AISettings.endpoint
    @State private var model = AISettings.model
    @State private var consent = AISettings.consent
    @State private var monthlyLimit = AISettings.budget.monthlyRequestLimit
    @State private var keyInput = ""
    @State private var hasKey = AIKeychain.hasKey
    @State private var message: String?

    var body: some View {
        List {
            availabilitySection
            if isEnabled {
                providerSection
                consentSection
                budgetSection
                diagnosticSection
            }
            if let message {
                Section {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("ai.message")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Coach IA")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Disponibilité

    private var availabilitySection: some View {
        Section {
            Toggle("Activer le coach IA", isOn: $isEnabled)
                .accessibilityIdentifier("ai.enabled")
                .onChange(of: isEnabled) { _, value in
                    AISettings.isEnabled = value
                }

            if let reason = AISettings.unavailabilityReason {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("ai.unavailable")
            } else {
                Label("Coach IA configuré", systemImage: "checkmark.seal")
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
            }
        } header: {
            Text("Disponibilité")
        } footer: {
            Text("Le coach IA est **facultatif** et désactivé par défaut. Aucune fonction d’entraînement n’en dépend : le générateur local, les séances, l’historique et les analyses fonctionnent hors ligne.")
        }
    }

    // MARK: - Fournisseur

    private var providerSection: some View {
        Section {
            TextField("Adresse du service", text: $endpoint)
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("ai.endpoint")
                .onSubmit { AISettings.endpoint = endpoint }

            TextField("Modèle", text: $model)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("ai.model")
                .onSubmit { AISettings.model = model }

            if hasKey {
                LabeledContent("Clé personnelle", value: "enregistrée")
                Button("Supprimer la clé", role: .destructive) {
                    AIKeychain.remove()
                    hasKey = false
                    message = "Clé supprimée du Trousseau."
                }
                .accessibilityIdentifier("ai.removeKey")
            } else {
                SecureField("Clé personnelle", text: $keyInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("ai.key")
                Button("Enregistrer la clé") {
                    saveEndpointAndModel()
                    hasKey = AIKeychain.store(keyInput)
                    keyInput = ""
                    message = hasKey
                        ? "Clé enregistrée dans le Trousseau de cet appareil."
                        : "La clé n’a pas pu être enregistrée."
                }
                .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("ai.saveKey")
            }
        } header: {
            Text("Fournisseur")
        } footer: {
            Text("Votre clé reste dans le Trousseau de cet appareil : elle n’est ni exportée, ni synchronisée, ni écrite dans les journaux. Muscu n’embarque aucune clé.")
        }
    }

    // MARK: - Consentement

    private var consentSection: some View {
        Section {
            ForEach(AIDataCategory.allCases) { category in
                Toggle(isOn: binding(for: category)) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(category.displayName)
                            if category.isSensitive {
                                Text("Sensible")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.orange.opacity(0.2))
                                    .foregroundStyle(.orange)
                                    .clipShape(Capsule())
                            }
                        }
                        Text(category.explanation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("ai.consent.\(category.rawValue)")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Ce qui sera envoyé :")
                    .font(.caption.weight(.semibold))
                ForEach(consent.sharedSummary(), id: \.self) { line in
                    Text("• " + line)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("ai.consent.summary")
        } header: {
            Text("Données partagées")
        } footer: {
            Text("Les catégories sensibles sont exclues par défaut. Vos données de santé (HealthKit), votre identité et vos photos ne sont jamais envoyées.")
        }
    }

    // MARK: - Budget

    private var budgetSection: some View {
        Section {
            Stepper(
                monthlyLimit == 0 ? "Aucune limite" : "Limite : \(monthlyLimit) demandes / mois",
                value: $monthlyLimit,
                in: 0...500,
                step: 10
            )
            .accessibilityIdentifier("ai.limit")
            .onChange(of: monthlyLimit) { _, value in
                AISettings.budget = AIBudget(monthlyRequestLimit: value)
            }

            Text(AIBudgetGuard.summary(usage: AISettings.usage, budget: AISettings.budget, now: .now))
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("ai.usage")
        } header: {
            Text("Usage")
        } footer: {
            Text("Muscu compte les demandes, pas leur coût : seul votre fournisseur connaît sa tarification.")
        }
    }

    // MARK: - Diagnostic

    private var diagnosticSection: some View {
        Section {
            NavigationLink {
                AICoachLogView()
            } label: {
                Label("Journal technique", systemImage: "doc.text.magnifyingglass")
            }
            .accessibilityIdentifier("ai.log")

            Button("Effacer les réglages et la clé", role: .destructive) {
                AISettings.reset()
                AICoachLog.clear()
                isEnabled = false
                endpoint = ""
                model = ""
                consent = .none
                hasKey = false
                message = "Réglages, consentement, usage et clé effacés."
            }
            .accessibilityIdentifier("ai.reset")
        } header: {
            Text("Diagnostic")
        } footer: {
            Text("Le journal ne contient ni vos demandes, ni vos données : seulement la capacité appelée, le modèle, la durée et le résultat.")
        }
    }

    // MARK: - Liaisons

    private func binding(for category: AIDataCategory) -> Binding<Bool> {
        Binding(
            get: { consent.allows(category) },
            set: { isOn in
                var updated = consent
                if isOn { updated.grant(category) } else { updated.revoke(category) }
                consent = updated
                AISettings.consent = updated
            }
        )
    }

    private func saveEndpointAndModel() {
        AISettings.endpoint = endpoint
        AISettings.model = model
    }
}

/// Journal technique, expurgé par construction.
struct AICoachLogView: View {
    @State private var entries = AICoachLog.entries

    var body: some View {
        List {
            Section {
                if entries.isEmpty {
                    Text("Aucune demande enregistrée.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("ai.log.empty")
                }
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(entry.capability?.displayName ?? entry.capabilityRaw) · \(entry.outcome.rawValue)")
                            .font(.subheadline.weight(.semibold))
                        Text("\(entry.modelIdentifier) · \(entry.durationMilliseconds) ms · \(entry.repairCount) correction(s)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(entry.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            } footer: {
                Text("Ni la demande, ni le contexte, ni la réponse ne sont conservés.")
            }

            if !entries.isEmpty {
                Section {
                    Button("Effacer le journal", role: .destructive) {
                        AICoachLog.clear()
                        entries = []
                    }
                    .accessibilityIdentifier("ai.log.clear")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Journal IA")
        .navigationBarTitleDisplayMode(.inline)
    }
}
