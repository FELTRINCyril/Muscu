import SwiftUI
import SwiftData
import MuscuEngine

/// Réglages Santé : ce qui sera partagé est expliqué AVANT la demande
/// système, et l'écran reste utile quand tout est refusé.
struct HealthSettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var isEnabled = HealthSettings.isEnabled
    @State private var writesWorkouts = HealthSettings.writesWorkouts
    @State private var sharesBodyweight = HealthSettings.sharesBodyweight
    @State private var importsBodyFat = HealthSettings.importsBodyFat
    @State private var importsWaist = HealthSettings.importsWaist
    /// Types ajoutes depuis l'autorisation donnee (cardio, effort, mesures)
    /// jamais presentes a l'utilisateur.
    @State private var needsNewAuthorization = false
    @State private var authorization: HealthAuthorization = .notDetermined
    @State private var message: String?
    @State private var isWorking = false

    private var store: HealthStoring { AppServices.healthStore }

    var body: some View {
        List {
            explanationSection
            switchSection
            if isEnabled && needsNewAuthorization { newTypesSection }
            if isEnabled { contentSection }
            if let message {
                Section {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("health.message")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Santé")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refreshAuthorization() }
    }

    // MARK: - Sections

    /// L'explication précède la demande système : au moment où iOS affiche sa
    /// feuille d'autorisation, l'utilisateur sait déjà pourquoi.
    private var explanationSection: some View {
        Section {
            Label("Muscu écrit vos séances terminées dans l’app Santé, avec votre note d’effort.", systemImage: "figure.strengthtraining.traditional")
                .font(.callout)
            Label("Sur iOS 26 et plus, Santé suit la séance en direct : fréquence cardiaque d’une montre ou d’un capteur, énergie active.", systemImage: "heart")
                .font(.callout)
            Label("Muscu peut lire et écrire votre poids corporel, et lire votre masse grasse et votre tour de taille, si vous l’activez.", systemImage: "scalemass")
                .font(.callout)
            Label("La fréquence cardiaque et l’énergie ne sont lues que sur la durée de vos séances. Rien d’autre n’est lu : ni sommeil, ni pas, ni activité.", systemImage: "hand.raised")
                .font(.callout)
                .foregroundStyle(.secondary)
        } header: {
            Text("Ce que Muscu partagera")
        } footer: {
            Text("L’autorisation n’est demandée qu’au moment où vous activez la fonction ci-dessous. Toutes les fonctions d’entraînement marchent sans Santé.")
        }
    }

    private var switchSection: some View {
        Section {
            Toggle("Partager avec Santé", isOn: $isEnabled)
                .disabled(isWorking || authorization == .unavailable)
                .accessibilityIdentifier("health.enabled")
                .onChange(of: isEnabled) { _, value in
                    Task { await apply(enabled: value) }
                }

            statusRow
        } header: {
            Text("Autorisation")
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch authorization {
        case .unavailable:
            Label("L’app Santé n’est pas disponible sur cet appareil.", systemImage: "exclamationmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("health.unavailable")
        case .denied:
            Label("Accès refusé. Vous pouvez le modifier dans Réglages → Confidentialité → Santé.", systemImage: "hand.raised")
                .font(.caption)
                .foregroundStyle(.orange)
                .accessibilityIdentifier("health.denied")
        case .notDetermined:
            Text("Aucune autorisation demandée pour l’instant.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("health.notDetermined")
        case .authorized:
            Label("Autorisé", systemImage: "checkmark.seal")
                .font(.caption)
                .foregroundStyle(Theme.accent)
                .accessibilityIdentifier("health.authorized")
        }
    }

    /// Une autorisation donnee avant le cardio, l'effort et les mesures ne
    /// les couvre pas. On l'explique, et la demande systeme ne part que du
    /// bouton.
    private var newTypesSection: some View {
        Section {
            Text("Muscu peut désormais lire la fréquence cardiaque et l’énergie active de vos séances, votre masse grasse et votre tour de taille, et écrire votre note d’effort. Santé vous laissera choisir, donnée par donnée.")
                .font(.callout)
            Button("Choisir les nouvelles données") {
                Task { await requestNewTypes() }
            }
            .disabled(isWorking)
            .accessibilityIdentifier("health.newTypes")
        } header: {
            Text("Nouvelles données")
        }
    }

    private var contentSection: some View {
        Section {
            Toggle("Écrire les séances terminées", isOn: $writesWorkouts)
                .accessibilityIdentifier("health.workouts")
                .onChange(of: writesWorkouts) { _, value in HealthSettings.writesWorkouts = value }

            Toggle("Partager le poids corporel", isOn: $sharesBodyweight)
                .accessibilityIdentifier("health.bodyweight")
                .onChange(of: sharesBodyweight) { _, value in HealthSettings.sharesBodyweight = value }

            Toggle("Importer la masse grasse", isOn: $importsBodyFat)
                .accessibilityIdentifier("health.bodyFat")
                .onChange(of: importsBodyFat) { _, value in HealthSettings.importsBodyFat = value }

            Toggle("Importer le tour de taille", isOn: $importsWaist)
                .accessibilityIdentifier("health.waist")
                .onChange(of: importsWaist) { _, value in HealthSettings.importsWaist = value }

            Button(isWorking ? "Synchronisation…" : "Synchroniser maintenant") {
                Task { await synchronize() }
            }
            .disabled(isWorking || authorization != .authorized)
            .accessibilityIdentifier("health.sync")
        } header: {
            Text("Contenu partagé")
        } footer: {
            Text("Une séance déjà écrite ne l’est jamais deux fois. La masse grasse et le tour de taille sont seulement lus : Muscu ne les écrit jamais dans Santé. Désactiver le partage n’efface pas ce qui a déjà été ajouté à Santé : ces données vous appartiennent, et c’est à vous de les retirer depuis l’app Santé.")
        }
    }

    // MARK: - Actions

    private func refreshAuthorization() async {
        authorization = store.authorizationStatus()
        needsNewAuthorization = authorization == .authorized ? await store.needsAuthorizationRequest() : false
    }

    private func requestNewTypes() async {
        isWorking = true
        defer { isWorking = false }
        authorization = await HealthSyncService.requestNewTypes(store: store)
        needsNewAuthorization = await store.needsAuthorizationRequest()
    }

    private func apply(enabled: Bool) async {
        isWorking = true
        defer { isWorking = false }

        if enabled {
            let outcome = await HealthSyncService.enable(in: modelContext, store: store)
            authorization = outcome.authorization
            isEnabled = HealthSettings.isEnabled
            message = outcome.summary
            needsNewAuthorization = authorization == .authorized ? await store.needsAuthorizationRequest() : false
        } else {
            HealthSyncService.disable()
            authorization = store.authorizationStatus()
            message = "Partage désactivé. Les séances déjà écrites restent dans Santé."
        }
    }

    private func synchronize() async {
        isWorking = true
        defer { isWorking = false }
        let outcome = await HealthSyncService.synchronize(in: modelContext, store: store)
        authorization = outcome.authorization
        message = outcome.failures.isEmpty
            ? outcome.summary
            : outcome.summary + " " + outcome.failures.joined(separator: " ")
    }
}
