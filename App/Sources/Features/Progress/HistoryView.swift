import SwiftUI
import SwiftData
import MuscuEngine

// Historique des seances terminees, groupees par mois. Le detail d'une
// seance (lecture, correction, « Refaire », partage) vit dans
// `SessionDetailView`.
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
                    // Les records issus de la seance sont recalcules dans la
                    // meme sauvegarde ; widgets et Sante suivent.
                    if PastSessionEditor.delete(session, in: modelContext) {
                        WidgetSnapshotService.refresh(in: modelContext)
                        Task {
                            await HealthSyncService.synchronize(in: modelContext, store: AppServices.healthStore)
                        }
                    }
                }
                sessionPendingDelete = nil
            }
            Button("Annuler", role: .cancel) {
                sessionPendingDelete = nil
            }
        } message: {
            Text("Les records issus de cette séance seront recalculés depuis le reste de l’historique.")
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
    @Environment(\.massUnit) private var massUnit

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
                Text(WeightFormatter.string(kilograms: tonnage, unit: massUnit))
                if let rating = session.effortRating {
                    Text("Effort \(rating)/10")
                        .foregroundStyle(SessionEffortPresentation.color(for: rating))
                }
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
        String(localized: "\(session.durationSeconds / 60) min")
    }
}

#Preview {
    NavigationStack {
        HistoryView()
    }
    .modelContainer(for: CompletedSession.self, inMemory: true)
    .preferredColorScheme(.dark)
}
