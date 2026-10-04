import SwiftUI
import SwiftData
import MuscuEngine

// Revue des exercices en double. Chaque paire est confirmee a la main :
// rien n'est jamais fusionne automatiquement. Inspire de l'ecran
// « merge-duplicates » d'Ischys (MIT), reecrit en SwiftUI.
struct MergeDuplicatesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(CatalogStore.self) private var catalogStore

    @State private var pairs: [DuplicatePair] = []
    @State private var swappedPairIds: Set<String> = []
    @State private var pendingMerge: DuplicatePair?
    @State private var resultMessage: ResultMessage?
    @State private var hasLoaded = false

    private struct ResultMessage: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    var body: some View {
        List {
            if hasLoaded && pairs.isEmpty {
                ContentUnavailableView(
                    "Aucun doublon détecté",
                    systemImage: "checkmark.circle",
                    description: Text("Vos exercices personnalisés ne recoupent ni le catalogue ni un autre exercice personnalisé.")
                )
                .listRowBackground(Color.clear)
            }

            ForEach(displayedPairs) { pair in
                Section {
                    PairRow(role: String(localized: "Conservé"), candidate: pair.survivor)
                    PairRow(role: String(localized: "Fusionné puis redirigé"), candidate: pair.duplicate)

                    Button {
                        pendingMerge = pair
                    } label: {
                        Label("Fusionner…", systemImage: "arrow.triangle.merge")
                    }
                    .accessibilityIdentifier("merge.confirm.\(pair.duplicate.id)")

                    if pair.canSwap {
                        Button {
                            toggleSwap(pair)
                        } label: {
                            Label("Garder plutôt « \(pair.duplicate.name) »", systemImage: "arrow.up.arrow.down")
                        }
                    }

                    Button(role: .destructive) {
                        ExerciseMergeService.dismiss(pair)
                        reload()
                    } label: {
                        Label("Ce ne sont pas des doublons", systemImage: "xmark")
                    }
                } header: {
                    Text(reasonTitle(pair.reason))
                } footer: {
                    Text(reasonExplanation(pair))
                }
            }

            if !pairs.isEmpty {
                Section {
                    EmptyView()
                } footer: {
                    Text("La fusion déplace tout l’historique du doublon (séries, records, programmes, modèles, objectifs, favoris et tags) vers l’exercice conservé. Le doublon n’est pas supprimé : il est masqué et redirigé, pour qu’une ancienne référence retrouve l’exercice conservé. Un exercice du catalogue est toujours conservé.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Doublons")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
        .confirmationDialog(
            "Fusionner ces exercices ?",
            isPresented: Binding(
                get: { pendingMerge != nil },
                set: { if !$0 { pendingMerge = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Fusionner", role: .destructive) {
                if let pendingMerge { merge(pendingMerge) }
                pendingMerge = nil
            }
            Button("Annuler", role: .cancel) { pendingMerge = nil }
        } message: {
            if let pair = pendingMerge {
                Text(confirmationMessage(pair))
            }
        }
        .alert(item: $resultMessage) { result in
            Alert(title: Text(result.title), message: Text(result.message), dismissButton: .default(Text("OK")))
        }
    }

    private var displayedPairs: [DuplicatePair] {
        pairs.map { swappedPairIds.contains($0.id) ? $0.swapped() : $0 }
    }

    private func toggleSwap(_ pair: DuplicatePair) {
        if swappedPairIds.contains(pair.id) {
            swappedPairIds.remove(pair.id)
        } else {
            swappedPairIds.insert(pair.id)
        }
    }

    private func reload() {
        pairs = ExerciseMergeService.pairs(in: modelContext, catalog: catalogStore.all)
        hasLoaded = true
    }

    private func merge(_ pair: DuplicatePair) {
        do {
            let report = try ExerciseMergeService.merge(
                duplicateId: pair.duplicate.id,
                into: pair.survivor.id,
                survivorName: pair.survivor.name,
                in: modelContext
            )
            swappedPairIds.remove(pair.id)
            reload()
            resultMessage = ResultMessage(title: String(localized: "Exercices fusionnés"), message: summary(of: report, pair: pair))
        } catch {
            resultMessage = ResultMessage(title: String(localized: "Fusion impossible"), message: error.localizedDescription)
        }
    }

    private func reasonTitle(_ reason: DuplicateReason) -> String {
        switch reason {
        case .sameName: return String(localized: "Même nom")
        case .sameImportName: return String(localized: "Même nom d’import")
        case .similarName: return String(localized: "Noms proches — à vérifier")
        }
    }

    private func reasonExplanation(_ pair: DuplicatePair) -> String {
        switch pair.reason {
        case .sameName:
            return String(localized: "Les deux noms sont identiques une fois les accents, majuscules et ponctuation ignorés, et le matériel est compatible.")
        case .sameImportName:
            return String(localized: "Un import écrit le matériel entre parenthèses (« Deadlift (Barbell) ») : le nom et le matériel désignent l’autre exercice.")
        case .similarName:
            return String(localized: "Noms proches (\(Int((pair.similarity * 100).rounded())) % de similarité ou mots inclus). Vérifiez qu’il s’agit bien du même mouvement avant de fusionner.")
        }
    }

    private func confirmationMessage(_ pair: DuplicatePair) -> String {
        String(localized: "« \(pair.duplicate.name) » (\(pair.duplicate.sessionCount) séance(s), \(pair.duplicate.setCount) série(s)) sera fusionné dans « \(pair.survivor.name) ». Pour chaque record, le meilleur des deux est conservé. Le doublon sera masqué et redirigé.")
    }

    private func summary(of report: ExerciseMergeService.Report, pair: DuplicatePair) -> String {
        var parts = [String(localized: "\(report.sets) série(s) sur \(report.sessions) séance(s)")]
        if report.prescriptions > 0 { parts.append(String(localized: "\(report.prescriptions) prescription(s) de programme")) }
        if report.templates > 0 { parts.append(String(localized: "\(report.templates) modèle(s)")) }
        if report.goals > 0 { parts.append(String(localized: "\(report.goals) objectif(s)")) }
        var message = String(localized: "Déplacé vers « \(pair.survivor.name) » : \(parts.joined(separator: ", ")).")
        if report.recordsGained > 0 {
            message += " " + String(localized: "\(report.recordsGained) record(s) repris du doublon, car meilleurs.")
        }
        return message
    }
}

private struct PairRow: View {
    let role: String
    let candidate: DuplicateCandidate

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(role)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Text(candidate.name)
                    .font(.body.weight(.medium))
                if candidate.isCatalog {
                    Text("Catalogue")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.2))
                        .clipShape(Capsule())
                } else {
                    PersoBadge()
                }
            }
            Text(details)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var details: String {
        var parts: [String] = []
        if !candidate.equipment.isEmpty { parts.append(FrenchLabels.equipment(candidate.equipment)) }
        parts.append(candidate.hasHistory
            ? String(localized: "\(candidate.sessionCount) séance(s), \(candidate.setCount) série(s)")
            : String(localized: "Aucun historique"))
        return parts.joined(separator: " · ")
    }
}

#Preview {
    NavigationStack {
        MergeDuplicatesView()
    }
    .environment(CatalogStore())
    .modelContainer(for: CustomExercise.self, inMemory: true)
    .preferredColorScheme(.dark)
}
