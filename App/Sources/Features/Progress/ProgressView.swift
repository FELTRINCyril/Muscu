import SwiftUI

// Onglet Progression : records / historique / graphiques, dans un seul
// picker segmente. Nomme ProgressTabView pour ne pas entrer en collision
// avec SwiftUI.ProgressView.
struct ProgressTabView: View {
    private enum Segment: String, CaseIterable, Identifiable {
        case records = "Records"
        case history = "Historique"
        case charts = "Graphiques"

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
                }
            }
            .background(Theme.background)
            .navigationTitle("Progression")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    ProgressTabView()
        .environment(CatalogStore())
        .modelContainer(for: ExerciseRecord.self, inMemory: true)
        .preferredColorScheme(.dark)
}
