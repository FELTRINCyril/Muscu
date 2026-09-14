import SwiftUI
import SwiftData
import MuscuEngine

/// Exercices qui stagnent, avec la fenêtre et le seuil visibles, et les deux
/// sorties possibles : décharge ou variante.
///
/// Rien n'est appliqué sans accord explicite, et chaque décision part au
/// journal d'adaptation, d'où elle reste annulable.
struct PlateauView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(CatalogStore.self) private var catalogStore

    @Query private var completedSets: [CompletedSet]
    @Query private var adaptations: [AdaptationEntry]

    @State private var items: [PlateauReview.Item] = []
    @State private var variantTarget: PlateauReview.Item?
    @State private var message: String?

    var body: some View {
        List {
            Section {
                if items.isEmpty {
                    Text(emptyMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("plateau.empty")
                }
                ForEach(items) { item in
                    row(item)
                }
            } header: {
                Text("Stagnation")
            } footer: {
                Text("Un plateau est signalé quand la progression reste sous \(Int(PlateauDetector.defaultThreshold * 100)) % sur \(PlateauDetector.minimumExposures) séances comparables. Rien n’est appliqué sans votre accord.")
            }

            if let message {
                Section {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("plateau.message")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Plateaux")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refresh)
        .onChange(of: completedSets.count) { _, _ in refresh() }
        .onChange(of: adaptations.count) { _, _ in refresh() }
        .sheet(item: $variantTarget) { item in
            variantPicker(item)
        }
    }

    private var emptyMessage: String {
        completedSets.isEmpty
            ? String(localized: "Aucune séance enregistrée : il n’y a encore rien à comparer.")
            : String(localized: "Aucune stagnation détectée sur les exercices de vos programmes.")
    }

    private func row(_ item: PlateauReview.Item) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.displayName)
                .font(.subheadline.weight(.semibold))

            // La fenêtre et le seuil sont toujours affichés : une détection
            // qu'on ne peut pas juger ne vaut rien.
            ForEach(Array(item.finding.factors.enumerated()), id: \.offset) { _, factor in
                Text(factor)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let current = item.currentLoadKilograms, let proposed = item.proposedLoadKilograms {
                Text("Décharge proposée : \(WeightFormatter.number(current)) → \(WeightFormatter.number(proposed)) kg")
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
            } else {
                Text("Aucune charge prescrite : la décharge ne s’applique pas ici.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                if item.proposedLoadKilograms != nil {
                    Button("Décharger") {
                        _ = PlateauReview.acceptDeload(item, in: modelContext)
                        message = "Décharge enregistrée. Annulable depuis le journal d’adaptation."
                        refresh()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .accessibilityIdentifier("plateau.deload")
                }

                Button("Changer d’exercice") { variantTarget = item }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("plateau.variant")

                Button("Ignorer") {
                    PlateauReview.decline(item, in: modelContext)
                    message = "Décision enregistrée au journal."
                    refresh()
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("plateau.decline")
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }

    private func variantPicker(_ item: PlateauReview.Item) -> some View {
        NavigationStack {
            List {
                Section {
                    ForEach(variants(for: item)) { candidate in
                        Button {
                            _ = PlateauReview.acceptVariant(
                                item,
                                replacement: candidate.exercise,
                                in: modelContext
                            )
                            message = "Exercice remplacé dans le programme. Décision tracée au journal."
                            variantTarget = nil
                            refresh()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(candidate.exercise.nameFr)
                                Text(candidate.reasons.first?.explanation ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    Text("Le programme est modifié ; l’historique déjà enregistré ne l’est jamais.")
                }
            }
            .navigationTitle("Variantes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { variantTarget = nil }
                }
            }
        }
    }

    private func variants(for item: PlateauReview.Item) -> [SubstitutionCandidate] {
        guard let exercise = catalogStore.exercise(id: item.prescription.exerciseId) else { return [] }
        return SubstitutionFinder.candidates(
            for: exercise,
            in: catalogStore.all,
            level: exercise.level,
            limit: 8
        )
    }

    private func refresh() {
        items = PlateauReview.findings(in: modelContext).filter {
            !PlateauReview.hasRecentDecision(exerciseId: $0.prescription.exerciseId, in: modelContext)
        }
    }
}
