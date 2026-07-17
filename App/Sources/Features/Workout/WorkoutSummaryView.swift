import SwiftUI

// Recap de fin de seance : duree, tonnage, nb de series, detail par exercice.
// La detection des records battus est le hook laisse pour la Task 20 : cet
// ecran ne calcule et n'affiche rien a ce sujet pour l'instant.
struct WorkoutSummaryView: View {
    let state: WorkoutState
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(spacing: 4) {
                        Text("Séance terminée")
                            .font(.title2.weight(.bold))
                        Text(state.programSession.name)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)

                    HStack(spacing: 12) {
                        StatCard(title: "Durée", value: formattedDuration)
                        StatCard(title: "Tonnage", value: "\(WorkoutState.formatWeight(totalTonnage)) kg")
                        StatCard(title: "Séries", value: "\(workingSets.count)")
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(groupedByExercise, id: \.orderIndex) { group in
                            ExerciseSummaryCard(displayName: group.displayName, sets: group.sets)
                        }
                    }
                }
                .padding()
            }

            Button {
                _ = state.finish()
                onFinish()
            } label: {
                Text("Terminer")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .controlSize(.large)
            .padding()
        }
        .background(Theme.background)
    }

    // Les series d'echauffement (isWarmup) sont loggees pour l'historique
    // mais ne comptent ni dans le tonnage ni dans le nombre de series de
    // travail affiches ici (ce ne sont pas des series de travail).
    private var workingSets: [CompletedSet] {
        state.loggedSets.filter { !$0.isWarmup }
    }

    private var totalTonnage: Double {
        workingSets.reduce(0) { $0 + $1.weight * Double($1.reps) }
    }

    private var formattedDuration: String {
        let seconds = max(0, Int(Date.now.timeIntervalSince(state.startedAt)))
        let minutes = seconds / 60
        let remainder = seconds % 60
        return String(format: "%d:%02d", minutes, remainder)
    }

    private struct ExerciseGroup {
        let orderIndex: Int
        let displayName: String
        let sets: [CompletedSet]
    }

    private var groupedByExercise: [ExerciseGroup] {
        let grouped = Dictionary(grouping: workingSets, by: \.orderIndex)
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

private struct StatCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.weight(.semibold))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct ExerciseSummaryCard: View {
    let displayName: String
    let sets: [CompletedSet]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(displayName)
                .font(.subheadline.weight(.semibold))

            ForEach(sets) { set in
                Text("Série \(set.setIndex + 1) : \(set.reps) reps @ \(WorkoutState.formatWeight(set.weight)) kg")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
