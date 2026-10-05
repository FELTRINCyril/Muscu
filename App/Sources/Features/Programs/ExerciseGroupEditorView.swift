import SwiftUI
import SwiftData
import MuscuEngine

// Reglages d'un groupe d'exercices : type, nombre de tours, repos entre
// exercices et entre tours, transition de circuit. La conversion vers un
// autre type n'est proposee que lorsqu'elle est compatible avec le nombre
// d'exercices reellement presents.
struct ExerciseGroupEditorView: View {
    @Bindable var group: ExerciseGroup

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            Form {
                Section("Type") {
                    Picker("Type de groupe", selection: Binding(
                        get: { group.kind },
                        set: { group.kind = $0 }
                    )) {
                        ForEach(compatibleKinds, id: \.self) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("group.kindPicker")
                }

                Section("Exercices") {
                    ForEach(Array(group.orderedExercises.enumerated()), id: \.element.id) { index, exercise in
                        LabeledContent("A\(index + 1)", value: exercise.displayName)
                    }
                }

                Section("Tours") {
                    Stepper("Tours : \(group.rounds)", value: $group.rounds, in: 1...50)
                }

                Section {
                    Stepper(
                        "Entre exercices : \(restLabel(group.restBetweenExercisesSeconds))",
                        value: $group.restBetweenExercisesSeconds,
                        in: 0...600,
                        step: 5
                    )
                    Stepper(
                        "Entre tours : \(restLabel(group.restBetweenRoundsSeconds))",
                        value: $group.restBetweenRoundsSeconds,
                        in: 0...900,
                        step: 5
                    )
                } header: {
                    Text("Repos")
                } footer: {
                    // Zero seconde n'est valide que pour un groupe enchaine :
                    // c'est justement ce qui definit un superset.
                    Text("Un repos de 0 s enchaîne les exercices sans pause, ce qui est le principe du superset et du circuit.")
                }

                if group.kind == .circuit {
                    Section {
                        Stepper(
                            "Transition : \(restLabel(group.transitionSeconds))",
                            value: $group.transitionSeconds,
                            in: 0...300,
                            step: 5
                        )
                        Toggle("Valider chaque station manuellement", isOn: $group.requiresManualStationValidation)
                    } header: {
                        Text("Circuit")
                    } footer: {
                        Text("La transition est le temps de déplacement entre deux stations.")
                    }
                }

                Section("Notes") {
                    TextField("Notes du groupe", text: $group.notes, axis: .vertical)
                        .lineLimit(1...4)
                }

                Section {
                    LabeledContent("Durée estimée", value: "\(estimatedMinutes) min")
                }
            }
            .navigationTitle(group.kind.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminé") {
                        group.updatedAt = .now
                        group.session?.touch()
                        _ = PersistenceSupport.save(modelContext, action: "Réglages du groupe")
                        dismiss()
                    }
                }
            }
        }
    }

    /// Types compatibles avec le nombre d'exercices du groupe, plus le type
    /// courant : on ne propose jamais une conversion qui casserait le groupe.
    private var compatibleKinds: [ExerciseGroupKind] {
        let count = group.exercises.count
        var kinds = ExerciseGroupKind.allCases.filter { $0 != .single && $0.accepts(exerciseCount: count) }
        if !kinds.contains(group.kind) { kinds.append(group.kind) }
        return kinds
    }

    private var estimatedMinutes: Int {
        let node = WorkoutNode(
            id: group.id,
            kind: WorkoutGroupKind(rawValue: group.kindRaw) ?? .superset,
            exercises: group.orderedExercises.map { WorkoutPlanBuilder.plan(for: $0) },
            rounds: group.rounds,
            restBetweenExercisesSeconds: group.restBetweenExercisesSeconds,
            restBetweenRoundsSeconds: group.restBetweenRoundsSeconds,
            transitionSeconds: group.transitionSeconds
        )
        return SessionDuration.roundedMinutes(SessionDuration.estimatedSeconds(for: node))
    }

    private func restLabel(_ seconds: Int) -> String {
        seconds == 0 ? String(localized: "aucun") : "\(seconds) s"
    }
}
