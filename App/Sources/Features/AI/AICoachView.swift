import SwiftUI
import SwiftData
import MuscuEngine

/// Demande au coach IA : capacité, demande en français, aperçu du brouillon,
/// puis confirmation.
///
/// Rien n'est écrit depuis cet écran : la proposition passe par l'aperçu de
/// programme existant, où l'utilisateur confirme comme pour le générateur.
struct AICoachView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(CatalogStore.self) private var catalogStore
    @Environment(NetworkStatus.self) private var networkStatus

    @State private var capability: AICoachCapability = .generateProgram
    @State private var prompt = ""
    @State private var isWorking = false
    @State private var task: Task<Void, Never>?
    @State private var outcome: AICoachOutcome?
    @State private var errorMessage: String?
    @State private var showingPreview = false
    @State private var pendingConfirmation = false

    var body: some View {
        List {
            if let reason = AISettings.unavailabilityReason {
                unavailableSection(reason)
            } else {
                requestSection
            }

            if isWorking { workingSection }
            if let outcome { resultSection(outcome) }
            if let errorMessage { errorSection(errorMessage) }
            disclaimerSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Coach IA")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    AISettingsView()
                } label: {
                    Label("Réglages", systemImage: "gearshape")
                }
                .accessibilityIdentifier("aiCoach.settings")
            }
        }
        .sheet(isPresented: $showingPreview) {
            if let draft = outcome?.draft {
                NavigationStack {
                    DraftPreviewView(
                        draft: draft.toDraftProgram(catalog: catalogStore.catalog),
                        regenerate: nil,
                        onSaved: { showingPreview = false }
                    )
                }
            }
        }
        .confirmationDialog(
            "Envoyer cette demande ?",
            isPresented: $pendingConfirmation,
            titleVisibility: .visible
        ) {
            Button("Envoyer") { start() }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text(confirmationMessage)
        }
        .onDisappear { task?.cancel() }
    }

    // MARK: - Sections

    private func unavailableSection(_ reason: String) -> some View {
        Section {
            Text(reason)
                .font(.callout)
                .accessibilityIdentifier("aiCoach.unavailable")
            NavigationLink {
                AISettingsView()
            } label: {
                Label("Configurer le coach IA", systemImage: "gearshape")
            }
        } header: {
            Text("Coach IA indisponible")
        } footer: {
            Text("Le générateur local reste disponible depuis l’onglet Programmes : il fonctionne hors ligne et donne toujours le même programme pour les mêmes réponses.")
        }
    }

    private var requestSection: some View {
        Section {
            Picker("Demande", selection: $capability) {
                ForEach(AICoachCapability.allCases) { value in
                    Text(value.displayName).tag(value)
                }
            }
            .pickerStyle(.navigationLink)
            .accessibilityIdentifier("aiCoach.capability")

            TextField("Votre demande, en français", text: $prompt, axis: .vertical)
                .lineLimit(2...6)
                .accessibilityIdentifier("aiCoach.prompt")

            if !missingConsent.isEmpty {
                Label(
                    "Accord manquant : " + missingConsent.map(\.displayName).joined(separator: ", "),
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .accessibilityIdentifier("aiCoach.consentMissing")
            }

            Button(isWorking ? "Envoi en cours…" : "Demander") { requestSend() }
                .disabled(isWorking || prompt.trimmingCharacters(in: .whitespaces).isEmpty || !missingConsent.isEmpty)
                .accessibilityIdentifier("aiCoach.send")
        } header: {
            Text("Demande")
        } footer: {
            Text("Ce qui sera envoyé : " + AISettings.consent.sharedSummary().joined(separator: " "))
        }
    }

    private var workingSection: some View {
        Section {
            HStack {
                ProgressView()
                Text("Le coach réfléchit…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Annuler", role: .destructive) {
                task?.cancel()
                isWorking = false
                errorMessage = AICoachError.cancelled.userMessage
            }
            .accessibilityIdentifier("aiCoach.cancel")
        }
    }

    private func resultSection(_ outcome: AICoachOutcome) -> some View {
        Section {
            switch outcome.source {
            case .model(let identifier):
                Label("Proposé par \(identifier)", systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .localFallback(let reason):
                // Le repli est DIT : laisser croire que l'IA a répondu serait
                // un mensonge sur l'origine de la proposition.
                VStack(alignment: .leading, spacing: 2) {
                    Label("Produit par le générateur local", systemImage: "gearshape.2")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("aiCoach.fallback")
            }

            Text(outcome.explanation)
                .font(.callout)
                .accessibilityIdentifier("aiCoach.explanation")

            if !outcome.repairs.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Corrections appliquées :")
                        .font(.caption.weight(.semibold))
                    ForEach(outcome.repairs, id: \.self) { repair in
                        Text("• " + repair)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("aiCoach.repairs")
            }

            if outcome.draft != nil {
                Button("Voir le brouillon") { showingPreview = true }
                    .accessibilityIdentifier("aiCoach.preview")
            }
        } header: {
            Text("Proposition")
        } footer: {
            Text("Rien n’est enregistré tant que vous n’avez pas confirmé dans l’aperçu.")
        }
    }

    private func errorSection(_ message: String) -> some View {
        Section {
            Text(message)
                .font(.caption)
                .foregroundStyle(.orange)
                .accessibilityIdentifier("aiCoach.error")
        }
    }

    private var disclaimerSection: some View {
        Section {
            Text("Les suggestions d’un modèle peuvent contenir des erreurs : vérifiez-les avant de les appliquer. Muscu ne pose aucun diagnostic et ne remplace pas un professionnel de santé. En cas de douleur inhabituelle, arrêtez et consultez.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("aiCoach.disclaimer")
        }
    }

    // MARK: - Actions

    private var missingConsent: [AIDataCategory] {
        AISettings.consent.missingCategories(for: capability)
    }

    private var confirmationMessage: String {
        let categories = AISettings.consent.sharedSummary().joined(separator: "\n")
        return "Catégories partagées :\n\(categories)\n\n\(AIBudgetGuard.summary(usage: AISettings.usage, budget: AISettings.budget, now: .now))"
    }

    private func requestSend() {
        // Une demande longue coûte plus cher : on la fait confirmer.
        if AIBudgetGuard.requiresConfirmation(payloadCharacters: prompt.count, budget: AISettings.budget) {
            pendingConfirmation = true
        } else {
            start()
        }
    }

    private func start() {
        errorMessage = nil
        outcome = nil
        isWorking = true

        let service = RemoteAICoachService(
            endpoint: AISettings.endpoint,
            model: AISettings.model,
            apiKey: AIKeychain.read()
        )
        let requestedCapability = capability
        let requestedPrompt = prompt

        task = Task {
            let result = await AICoachCoordinator.perform(
                capability: requestedCapability,
                prompt: requestedPrompt,
                service: service,
                consent: AISettings.consent,
                budget: AISettings.budget,
                usage: AISettings.usage,
                catalog: catalogStore.catalog,
                localFallback: { localDraft() },
                in: modelContext
            )

            guard !Task.isCancelled else { return }
            AISettings.usage = AIBudgetGuard.recording(AISettings.usage, payloadCharacters: requestedPrompt.count, now: .now)

            switch result {
            case .success(let value): outcome = value
            case .failure(let error): errorMessage = error.userMessage
            }
            isWorking = false
        }
    }

    /// Repli déterministe : le générateur local, avec le profil connu.
    private func localDraft() -> AIProgramDraft? {
        let profile = ProfileStore.currentProfile(in: modelContext)
        let input = GeneratorInput(
            goal: profile?.primaryGoal ?? .hypertrophy,
            experience: profile?.experience ?? .intermediate,
            daysPerWeek: max(2, min(6, profile?.availableWeekdays.count ?? 3)),
            sessionMinutes: profile?.sessionMinutesMaximum ?? 60,
            equipment: profile?.equipment ?? .fullGym,
            splitPreference: .auto,
            priorityMuscles: [],
            avoidAreas: []
        )
        guard let draft = try? RuleBasedGenerator(catalog: catalogStore.catalog).generate(input) else { return nil }

        return AIProgramDraft(
            name: draft.name,
            notes: draft.notes,
            sessions: draft.sessions.map { session in
                AISessionDraft(
                    name: session.name,
                    exercises: session.exercises.map { exercise in
                        AIExerciseDraft(
                            exerciseId: exercise.exerciseId,
                            sets: exercise.sets,
                            repsLower: exercise.repsLower,
                            repsUpper: exercise.repsUpper,
                            restSeconds: exercise.restSeconds
                        )
                    }
                )
            }
        )
    }
}
