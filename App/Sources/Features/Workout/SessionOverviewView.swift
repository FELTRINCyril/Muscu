import SwiftUI
import MuscuEngine

// Apercu de la seance en cours : tous les noeuds, leur avancement, et la
// possibilite de sauter a un exercice precedent ou a venir.
//
// Sauter n'efface jamais une serie deja enregistree : l'historique de la
// seance reste ce qui a ete reellement fait.
struct SessionOverviewView: View {
    let state: WorkoutState
    let onSelect: (WorkoutPosition) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Avancement", value: progressLabel)
                    LabeledContent("Séries enregistrées", value: "\(state.loggedSets.count)")
                } footer: {
                    Text("Se déplacer dans la séance ne supprime aucune série déjà enregistrée.")
                }

                ForEach(Array(state.plan.nodes.enumerated()), id: \.element.id) { nodeIndex, node in
                    Section(header: Text(sectionTitle(for: node))) {
                        ForEach(Array(node.exercises.enumerated()), id: \.element.id) { memberIndex, exercise in
                            Button {
                                onSelect(position(nodeIndex: nodeIndex, memberIndex: memberIndex, node: node))
                                dismiss()
                            } label: {
                                row(exercise: exercise, nodeIndex: nodeIndex, memberIndex: memberIndex, node: node)
                            }
                            .accessibilityIdentifier("overview.exercise.\(nodeIndex).\(memberIndex)")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Aperçu de la séance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }

    private func row(exercise: WorkoutExercisePlan, nodeIndex: Int, memberIndex: Int, node: WorkoutNode) -> some View {
        HStack(spacing: 12) {
            Image(systemName: statusIcon(nodeIndex: nodeIndex, memberIndex: memberIndex))
                .foregroundStyle(statusColor(nodeIndex: nodeIndex, memberIndex: memberIndex))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.displayName)
                    .foregroundStyle(.primary)
                Text(subtitle(for: exercise, in: node))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(exercise.displayName), \(subtitle(for: exercise, in: node)), \(statusLabel(nodeIndex: nodeIndex, memberIndex: memberIndex))")
    }

    private func sectionTitle(for node: WorkoutNode) -> String {
        switch node.kind {
        case .single: return String(localized: "Exercice")
        case .superset: return String(localized: "Superset · \(node.rounds) tours")
        case .triset: return String(localized: "Triset · \(node.rounds) tours")
        case .giantSet: return String(localized: "Giant set · \(node.rounds) tours")
        case .circuit: return String(localized: "Circuit · \(node.rounds) tours")
        }
    }

    private func subtitle(for exercise: WorkoutExercisePlan, in node: WorkoutNode) -> String {
        if !exercise.objectiveLabel.isEmpty { return exercise.objectiveLabel }
        let reps = exercise.repsLower == exercise.repsUpper
            ? "\(exercise.repsLower)"
            : "\(exercise.repsLower)-\(exercise.repsUpper)"
        return node.isGroup
            ? String(localized: "\(reps) reps par tour")
            : String(localized: "\(exercise.setCount) x \(reps) reps")
    }

    /// Position visee : le debut de l'exercice choisi. Pour un groupe, on
    /// reste sur le tour courant si l'on y est deja, sinon on repart du
    /// premier tour.
    private func position(nodeIndex: Int, memberIndex: Int, node: WorkoutNode) -> WorkoutPosition {
        let current = WorkoutStateMachine.clamp(state.position, in: state.plan)
        let round = (node.isGroup && current.nodeIndex == nodeIndex) ? current.round : 0
        return WorkoutPosition(
            nodeIndex: nodeIndex,
            round: round,
            memberIndex: memberIndex,
            setIndex: node.isGroup ? round : 0
        )
    }

    private enum Status { case done, current, upcoming }

    private func status(nodeIndex: Int, memberIndex: Int) -> Status {
        let current = WorkoutStateMachine.clamp(state.position, in: state.plan)
        if nodeIndex < current.nodeIndex { return .done }
        if nodeIndex > current.nodeIndex { return .upcoming }
        if memberIndex < current.memberIndex { return .done }
        if memberIndex > current.memberIndex { return .upcoming }
        return .current
    }

    private func statusIcon(nodeIndex: Int, memberIndex: Int) -> String {
        switch status(nodeIndex: nodeIndex, memberIndex: memberIndex) {
        case .done: return "checkmark.circle.fill"
        case .current: return "play.circle.fill"
        case .upcoming: return "circle"
        }
    }

    private func statusColor(nodeIndex: Int, memberIndex: Int) -> Color {
        switch status(nodeIndex: nodeIndex, memberIndex: memberIndex) {
        case .done: return Theme.accent
        case .current: return .white
        case .upcoming: return .secondary
        }
    }

    private func statusLabel(nodeIndex: Int, memberIndex: Int) -> String {
        switch status(nodeIndex: nodeIndex, memberIndex: memberIndex) {
        case .done: return String(localized: "terminé")
        case .current: return String(localized: "en cours")
        case .upcoming: return String(localized: "à venir")
        }
    }

    private var progressLabel: String {
        let progress = state.progress
        return String(localized: "\(progress.completed)/\(progress.total)")
    }
}
