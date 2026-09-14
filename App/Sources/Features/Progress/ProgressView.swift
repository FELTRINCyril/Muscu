import SwiftUI

// Onglet Progression : records / historique / graphiques, dans un seul
// picker segmente. Nomme ProgressTabView pour ne pas entrer en collision
// avec SwiftUI.ProgressView.
struct ProgressTabView: View {
    private enum Segment: String, CaseIterable, Identifiable {
        case records = "Records"
        case history = "Historique"
        case charts = "Graphiques"
        case measurements = "Mesures"

        var id: String { rawValue }
    }

    @State private var segment: Segment = .records

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Vue", selection: $segment) {
                    ForEach(Segment.allCases) { segment in
                        Text(segment.rawValue).tag(segment)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                switch segment {
                case .records:
                    RecordsView()
                case .history:
                    HistoryView()
                case .charts:
                    ChartsView()
                case .measurements:
                    MeasurementsView()
                }
            }
            .background(Theme.background)
            .navigationTitle("Progression")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        NavigationLink {
                            GoalsView()
                        } label: {
                            Label("Objectifs", systemImage: "target")
                        }
                        NavigationLink {
                            AdaptationJournalView()
                        } label: {
                            Label("Adaptations", systemImage: "arrow.triangle.branch")
                        }
                        NavigationLink {
                            PlateauView()
                        } label: {
                            Label("Plateaux", systemImage: "chart.line.flattrend.xyaxis")
                        }
                        .accessibilityIdentifier("progress.plateaus")
                    } label: {
                        Label("Plus", systemImage: "ellipsis.circle")
                    }
                    .accessibilityIdentifier("progress.moreMenu")
                }
            }
        }
    }
}

#Preview {
    ProgressTabView()
        .environment(CatalogStore())
        .modelContainer(for: ExerciseRecord.self, inMemory: true)
        .preferredColorScheme(.dark)
}
