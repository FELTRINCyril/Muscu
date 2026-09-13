import SwiftUI
import SwiftData
import MuscuEngine

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
                    _ = PersistenceSupport.save(modelContext, action: "Suppression de la séance")
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
        session.workingSets
    }

    private var workingSetsCount: Int {
        workingSets.count
    }

    // Tonnage calcule par le moteur : l'accueil, l'historique et les
    // graphiques doivent afficher exactement la meme valeur.
    private var tonnage: Double {
        CompletedSetPresentation.tonnage(for: session).total
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
                Section {
                    ForEach(group.sets) { set in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(CompletedSetPresentation.label(for: set, inGroup: group.isGrouped))
                                Spacer()
                                Text(CompletedSetPresentation.performance(for: set))
                            }
                            if let note = CompletedSetPresentation.substitutionNote(for: set) {
                                Text(note)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.subheadline)
                        .foregroundStyle(set.role == .warmup ? .secondary : .primary)
                        .padding(.leading, set.subSetIndex > 0 ? 16 : 0)
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    HStack {
                        Text(group.displayName)
                        if let badge = group.formatBadge {
                            Text(badge)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.accent.opacity(0.2))
                                .foregroundStyle(Theme.accent)
                                .clipShape(Capsule())
                        }
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
        /// L'exercice faisait partie d'un superset, triset ou circuit :
        /// les series se lisent alors par TOUR, pas par numero de serie.
        let isGrouped: Bool
        /// Format affiche a cote du nom quand ce n'est pas du classique.
        let formatBadge: String?
    }

    private var groupedSets: [ExerciseGroup] {
        let grouped = Dictionary(grouping: session.sets, by: \.orderIndex)
        return grouped.keys.sorted().compactMap { orderIndex in
            guard let sets = grouped[orderIndex], let first = sets.first else { return nil }
            let format = first.format
            return ExerciseGroup(
                orderIndex: orderIndex,
                displayName: first.displayName,
                sets: sets.sorted { ($0.roundIndex, $0.setIndex, $0.subSetIndex) < ($1.roundIndex, $1.setIndex, $1.subSetIndex) },
                isGrouped: first.groupId != nil,
                formatBadge: format == .classic ? nil : format.displayName
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
