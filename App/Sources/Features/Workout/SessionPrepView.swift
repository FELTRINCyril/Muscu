import SwiftUI
import SwiftData
import MuscuEngine

// Ecran propose AVANT de lancer une seance : check-in de forme facultatif et
// propositions de progression issues des seances precedentes.
//
// Rien n'est applique sans decision explicite : l'utilisateur peut tout
// ignorer et commencer directement.
struct SessionPrepView: View {
    let session: ProgramSession
    /// La mise à l'échelle éventuellement acceptée au check-in accompagne le
    /// démarrage : sinon la suggestion resterait une phrase, ce qu'elle était.
    let onStart: (WeekScaling?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    /// Ajustement du check-in accepté par l'utilisateur, `nil` tant qu'il ne
    /// l'a pas explicitement accepté.
    @State private var acceptedAdjustment: WeekScaling?
    @State private var energy: Int?
    @State private var sleepQuality: Int?
    @State private var soreness: Int?
    @State private var stress: Int?
    @State private var painIntensity: Int = 0
    @State private var painArea: String = ""
    @State private var proposals: [ProgressionReview.Item] = []
    @State private var handled: Set<UUID> = []

    var body: some View {
        NavigationStack {
            List {
                if !proposals.isEmpty {
                    progressionSection
                }
                checkInSection
                if let advice, advice.adjustment != .keepAsPlanned || advice.cautionMessage != nil {
                    adviceSection(advice)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Avant la séance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Commencer") {
                        saveCheckIn()
                        journalAcceptedAdjustment()
                        onStart(acceptedAdjustment)
                    }
                    .accessibilityIdentifier("prep.start")
                }
            }
            .onAppear(perform: loadProposals)
        }
    }

    // MARK: - Progression

    private var progressionSection: some View {
        Section {
            ForEach(proposals) { item in
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.displayName)
                        .font(.subheadline.weight(.semibold))
                    Text(ProgressionReview.summary(for: item.proposal.outcome))
                        .font(.callout)
                        .foregroundStyle(Theme.accent)

                    // Les raisons sont affichees d'office : une adaptation
                    // qu'on ne peut pas expliquer ne doit pas etre proposee.
                    ForEach(item.factors, id: \.self) { factor in
                        Label(factor, systemImage: "chart.line.uptrend.xyaxis")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if handled.contains(item.id) {
                        Text("Décision enregistrée")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        HStack {
                            Button("Appliquer") { accept(item) }
                                .buttonStyle(.borderedProminent)
                                .tint(Theme.accent)
                                .accessibilityIdentifier("prep.accept")
                            Button("Refuser") { decline(item) }
                                .buttonStyle(.bordered)
                        }
                        .font(.subheadline)
                    }
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .contain)
            }
        } header: {
            Text("Progression proposée")
        } footer: {
            Text("Chaque proposition s'appuie sur vos séances précédentes. Elle reste annulable depuis le journal d'adaptation.")
        }
    }

    // MARK: - Check-in

    private var checkInSection: some View {
        Section {
            ScaleRow(label: "Énergie", value: $energy)
            ScaleRow(label: "Sommeil", value: $sleepQuality)
            ScaleRow(label: "Courbatures", value: $soreness)
            ScaleRow(label: "Stress", value: $stress)

            Stepper("Douleur : \(painIntensity)/10", value: $painIntensity, in: 0...10)
                .accessibilityIdentifier("prep.pain")
            if painIntensity > 0 {
                TextField("Zone concernée (optionnel)", text: $painArea)
            }
        } header: {
            Text("Comment vous sentez-vous ?")
        } footer: {
            Text("Facultatif. Ces informations restent sur l'appareil et servent uniquement à adapter la séance.")
        }
    }

    private func adviceSection(_ advice: ReadinessAdvice) -> some View {
        Section {
            Text(adjustmentLabel(advice.adjustment))
                .font(.callout.weight(.medium))
            // Une suggestion chiffrée peut désormais être APPLIQUÉE. Elle ne
            // l'est jamais d'office : l'accepter reste un geste, et la
            // séance part inchangée si on ne fait rien.
            if let scaling = WeekScaling(readiness: advice.adjustment, loadIncrementKilograms: loadIncrement) {
                Toggle("Appliquer à cette séance", isOn: Binding(
                    get: { acceptedAdjustment != nil },
                    set: { acceptedAdjustment = $0 ? scaling : nil }
                ))
                .accessibilityIdentifier("prep.applyAdjustment")
            }
            ForEach(advice.factors, id: \.self) { factor in
                Label(factor, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let caution = advice.cautionMessage {
                Label(caution, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("prep.caution")
            }
        } header: {
            Text("Suggestion")
        } footer: {
            Text("Une suggestion, pas une consigne : la séance reste telle que vous la lancez.")
        }
    }

    private func adjustmentLabel(_ adjustment: ReadinessAdjustment) -> String {
        switch adjustment {
        case .keepAsPlanned:
            return "Séance normale."
        case .reduceVolume(let multiplier):
            return "Réduire le volume d'environ \(Int((1 - multiplier) * 100)) % (moins de séries)."
        case .reduceLoad(let multiplier):
            return "Réduire les charges d'environ \(Int((1 - multiplier) * 100)) %."
        case .suggestSubstitution(let area):
            return "Remplacer les exercices qui sollicitent la zone : \(area)."
        case .suggestRest:
            return "Envisager du repos ou une séance très légère aujourd'hui."
        }
    }

    /// Trace l'allègement accepté dans le journal d'adaptation.
    ///
    /// `AdaptationSource.readiness` était déclaré et n'était **jamais
    /// écrit** : le check-in ne laissait aucune trace. Une séance allégée
    /// sans trace est inexplicable après coup — « pourquoi seulement deux
    /// séries ce jour-là ? ».
    ///
    /// L'entrée n'est pas annulable : l'allègement vaut pour cette séance
    /// seulement et ne modifie aucun programme. Il n'y a rien à restaurer.
    private func journalAcceptedAdjustment() {
        guard let scaling = acceptedAdjustment, let advice else { return }
        let volume = Int((scaling.volumeMultiplier * 100).rounded())
        let intensity = Int((scaling.intensityMultiplier * 100).rounded())
        let entry = AdaptationEntry(
            sourceRaw: AdaptationSource.readiness.rawValue,
            decisionRaw: AdaptationDecision.accepted.rawValue,
            decidedAt: .now,
            displayName: session.name,
            summary: String(localized: "Séance allégée : volume \(volume) %, intensité \(intensity) %"),
            factors: advice.factors
        )
        modelContext.insert(entry)
        _ = PersistenceSupport.save(modelContext, action: "Allègement accepté au check-in")
    }

    /// Palier de charge réellement disponible, pour ne pas proposer 47,3 kg.
    private var loadIncrement: Double {
        ProfileStore.currentProfile(in: modelContext)?
            .availableIncrementsKilograms.filter { $0 > 0 }.min() ?? 0
    }

    // MARK: - Données

    private var checkIn: ReadinessCheckIn {
        ReadinessCheckIn(
            energy: energy,
            sleepQuality: sleepQuality,
            soreness: soreness,
            stress: stress,
            painIntensity: painIntensity > 0 ? painIntensity : nil,
            painArea: painArea
        )
    }

    private var advice: ReadinessAdvice? {
        guard checkIn.hasAnyValue else { return nil }
        return ReadinessAdvisor.advise(checkIn)
    }

    private func loadProposals() {
        proposals = ProgressionReview.proposals(for: session, context: modelContext)
    }

    private func accept(_ item: ProgressionReview.Item) {
        ProgressionReview.accept(item, context: modelContext)
        handled.insert(item.id)
        _ = PersistenceSupport.save(modelContext, action: "Application de la progression")
    }

    private func decline(_ item: ProgressionReview.Item) {
        ProgressionReview.decline(item, context: modelContext)
        handled.insert(item.id)
        _ = PersistenceSupport.save(modelContext, action: "Refus de la progression")
    }

    private func saveCheckIn() {
        guard checkIn.hasAnyValue else { return }
        let entry = ReadinessEntry(
            energy: energy,
            sleepQuality: sleepQuality,
            soreness: soreness,
            stress: stress,
            painIntensity: painIntensity > 0 ? painIntensity : nil,
            painArea: painArea.trimmingCharacters(in: .whitespacesAndNewlines),
            programSessionId: session.id
        )
        modelContext.insert(entry)
        _ = PersistenceSupport.save(modelContext, action: "Enregistrement du check-in")
    }
}

/// Ligne d'echelle 1...5, avec un etat « non renseigne » explicite.
private struct ScaleRow: View {
    let label: String
    @Binding var value: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                Spacer()
                Text(value.map { "\($0)/5" } ?? "—")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { level in
                    Button {
                        value = (value == level) ? nil : level
                    } label: {
                        Text("\(level)")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 40, height: 40)
                            .background(value == level ? Theme.accent : Color.white.opacity(0.08))
                            .foregroundStyle(value == level ? Color.black : Color.white)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(label) \(level) sur 5")
                    .accessibilityAddTraits(value == level ? [.isSelected] : [])
                }
            }
        }
        .padding(.vertical, 2)
    }
}
