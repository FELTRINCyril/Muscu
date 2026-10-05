import SwiftUI
import SwiftData
import MuscuEngine

// Journal des adaptations : ce qui a ete propose, pourquoi, ce qui a ete
// decide, et la possibilite d'annuler une adaptation acceptee.
struct AdaptationJournalView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \AdaptationEntry.createdAt, order: .reverse)
    private var entries: [AdaptationEntry]

    var body: some View {
        List {
            if entries.isEmpty {
                ContentUnavailableView(
                    "Aucune adaptation",
                    systemImage: "arrow.triangle.branch",
                    description: Text("Les propositions de progression et leurs décisions apparaîtront ici.")
                )
            } else {
                ForEach(entries) { entry in
                    row(entry)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Adaptations")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ entry: AdaptationEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.displayName.isEmpty ? "Adaptation" : entry.displayName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(decisionLabel(entry.decision))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(decisionColor(entry.decision))
            }

            Text(entry.summary)
                .font(.callout)

            ForEach(entry.factors, id: \.self) { factor in
                Label(factor, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(Self.dateFormatter.string(from: entry.createdAt))
                .font(.caption2)
                .foregroundStyle(.secondary)

            if entry.canRevert {
                Button("Annuler cette adaptation") {
                    revert(entry)
                }
                .font(.footnote)
                .buttonStyle(.bordered)
                .accessibilityIdentifier("adaptation.revert")
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }

    private func revert(_ entry: AdaptationEntry) {
        guard ProgressionReview.revert(entry, context: modelContext) else { return }
        _ = PersistenceSupport.save(modelContext, action: "Annulation de l’adaptation")
    }

    private func decisionLabel(_ decision: AdaptationDecision) -> String {
        switch decision {
        case .proposed: return "Proposée"
        case .accepted: return "Appliquée"
        case .declined: return "Refusée"
        case .reverted: return "Annulée"
        }
    }

    private func decisionColor(_ decision: AdaptationDecision) -> Color {
        switch decision {
        case .accepted: return Theme.accent
        case .declined, .reverted: return .secondary
        case .proposed: return .orange
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
