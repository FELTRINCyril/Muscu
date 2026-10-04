import SwiftUI
import MuscuEngine

// MARK: - Seance libre en attente d'exercice

/// Seance libre dont le deroule est epuise (ou vide au demarrage) : on
/// ajoute l'exercice suivant, ou on termine. Rien ne se termine tout seul.
struct FreeSessionIdleView: View {
    let state: WorkoutState
    let onAddExercise: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 24)
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 48))
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            VStack(spacing: 6) {
                Text(state.exercises.isEmpty ? "Séance libre" : "Exercice terminé")
                    .font(.title3.weight(.semibold))
                Text(state.exercises.isEmpty
                    ? "Ajoute ton premier exercice : les séries se saisissent comme d’habitude."
                    : "Ajoute un autre exercice ou termine la séance.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                onAddExercise()
            } label: {
                Label("Ajouter un exercice", systemImage: "plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .controlSize(.large)
            .accessibilityIdentifier("freeSession.addExercise")

            Button {
                state.requestEnd()
            } label: {
                Text("Terminer la séance")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            // Une seance sans aucune serie n'a rien a enregistrer : on la
            // quitte par « Abandonner » (bouton de fermeture).
            .disabled(state.loggedSets.isEmpty)
            .accessibilityIdentifier("freeSession.finish")

            if state.loggedSets.isEmpty {
                Text("Aucune série enregistrée pour l’instant.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
    }
}

// MARK: - Ordre des exercices restants

/// Reordonne les exercices qui restent a faire. Les exercices deja
/// commences n'apparaissent pas : ils ne bougent jamais. Rien n'est applique
/// avant « Enregistrer ».
struct ReorderExercisesView: View {
    let state: WorkoutState

    @Environment(\.dismiss) private var dismiss
    @State private var nodes: [WorkoutNode] = []
    @State private var didLoad = false
    @State private var saveFailed = false

    var body: some View {
        NavigationStack {
            List {
                if nodes.count < 2 {
                    Text("Il faut au moins deux exercices restants, non commencés, pour changer leur ordre.")
                        .foregroundStyle(.secondary)
                } else {
                    Section {
                        ForEach(nodes) { node in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(title(for: node))
                                if node.isGroup {
                                    Text(node.exercises.map(\.displayName).joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onMove { source, destination in
                            nodes.move(fromOffsets: source, toOffset: destination)
                        }
                    } footer: {
                        Text("Les exercices déjà commencés gardent leur place.")
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Exercices restants")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        if state.reorderRemaining(nodes.map(\.id)) {
                            dismiss()
                        } else {
                            saveFailed = true
                        }
                    }
                    .disabled(nodes.count < 2)
                    .accessibilityIdentifier("reorder.save")
                }
            }
            .alert("Ordre non enregistré", isPresented: $saveFailed) {
                Button("OK", role: .cancel) { dismiss() }
            } message: {
                Text("La séance a changé entre-temps. Rouvre la liste pour réessayer.")
            }
            .onAppear {
                guard !didLoad else { return }
                didLoad = true
                nodes = state.reorderableNodes
            }
        }
    }

    private func title(for node: WorkoutNode) -> String {
        switch node.kind {
        case .single: return node.exercises.first?.displayName ?? ""
        case .superset: return String(localized: "Superset")
        case .triset: return String(localized: "Triset")
        case .giantSet: return String(localized: "Giant set")
        case .circuit: return String(localized: "Circuit")
        }
    }
}

// MARK: - Libelles de mesure

extension SetMeasure {
    var displayName: String {
        switch self {
        case .weightReps: return String(localized: "Poids × répétitions")
        case .duration: return String(localized: "Temps")
        case .distance: return String(localized: "Distance")
        case .durationAndDistance: return String(localized: "Temps + distance")
        }
    }
}
