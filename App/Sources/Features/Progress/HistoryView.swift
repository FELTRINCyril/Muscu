import SwiftUI
import SwiftData

// Historique des seances terminees, groupees par mois. Le detail d'une
// seance liste chaque serie par exercice, dans l'ordre de la seance ; les
// series d'echauffement sont marquees et attenuees.
struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CompletedSession.date, order: .reverse) private var sessions: [CompletedSession]

    @State private var sessionPendingDelete: CompletedSession?

    var body: some View {
        List {
            ForEach(monthSections, id: \.title) { section in
                Section(section.title) {
                    ForEach(section.sessions) { session in
                        NavigationLink(value: session) {
                            SessionRow(session: session)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                sessionPendingDelete = session
                            } label: {
                                Label("Supprimer", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .overlay {
            if sessions.isEmpty {
                ContentUnavailableView(
                    "Aucune séance",
                    systemImage: "calendar",
                    description: Text("Vos séances terminées apparaîtront ici.")
                )
            }
        }
        .navigationDestination(for: CompletedSession.self) { session in
            SessionDetailView(session: session)
        }
        .confirmationDialog(
            "Supprimer cette séance ?",
            isPresented: Binding(
                get: { sessionPendingDelete != nil },
                set: { if !$0 { sessionPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive) {
                if let session = sessionPendingDelete {
                    modelContext.delete(session)
                    try? modelContext.save()
                }
                sessionPendingDelete = nil
            }
            Button("Annuler", role: .cancel) {
                sessionPendingDelete = nil
            }
        }
    }

    private struct MonthSection {
        let title: String
        let sessions: [CompletedSession]
    }

    private var monthSections: [MonthSection] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: sessions) { session in
            calendar.dateInterval(of: .month, for: session.date)?.start ?? session.date
        }
        return grouped.keys.sorted(by: >).map { monthStart in
            let title = monthStart.formatted(
                .dateTime.month(.wide).year().locale(Locale(identifier: "fr_FR"))
            )
            let monthSessions = (grouped[monthStart] ?? []).sorted { $0.date > $1.date }
            return MonthSection(title: title, sessions: monthSessions)
        }
    }
}

private struct SessionRow: View {
    let session: CompletedSession

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(session.sessionName.isEmpty ? "Séance" : session.sessionName)
                    .foregroundStyle(.primary)
                Spacer()
                Text(session.date.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "fr_FR"))))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Text(durationLabel)
                Text("\(workingSetsCount) séries")
                Text("\(WorkoutState.formatWeight(tonnage)) kg")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var workingSets: [CompletedSet] {
        session.sets.filter { !$0.isWarmup }
    }

    private var workingSetsCount: Int {
        workingSets.count
    }

    private var tonnage: Double {
        workingSets.reduce(0) { $0 + $1.weight * Double($1.reps) }
    }

    private var durationLabel: String {
        "\(session.durationSeconds / 60) min"
    }
}

private struct SessionDetailView: View {
    let session: CompletedSession

    var body: some View {
        List {
            ForEach(groupedSets, id: \.orderIndex) { group in
                Section(group.displayName) {
                    ForEach(group.sets) { set in
                        HStack {
                            Text(set.isWarmup ? "Échauffement" : "Série \(set.setIndex + 1)")
                            Spacer()
                            Text("\(set.reps) reps @ \(WorkoutState.formatWeight(set.weight)) kg")
                        }
                        .font(.subheadline)
                        .foregroundStyle(set.isWarmup ? .secondary : .primary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(session.sessionName.isEmpty ? "Séance" : session.sessionName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private struct ExerciseGroup {
        let orderIndex: Int
        let displayName: String
        let sets: [CompletedSet]
    }

    private var groupedSets: [ExerciseGroup] {
        let grouped = Dictionary(grouping: session.sets, by: \.orderIndex)
        return grouped.keys.sorted().compactMap { orderIndex in
            guard let sets = grouped[orderIndex], let displayName = sets.first?.displayName else { return nil }
            return ExerciseGroup(
                orderIndex: orderIndex,
                displayName: displayName,
                sets: sets.sorted { $0.setIndex < $1.setIndex }
            )
        }
    }
}

#Preview {
    NavigationStack {
        HistoryView()
    }
    .modelContainer(for: CompletedSession.self, inMemory: true)
    .preferredColorScheme(.dark)
}
