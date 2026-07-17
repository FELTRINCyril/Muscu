import SwiftUI
import SwiftData
import MuscuEngine

// Editeur d'une seance : nom, echauffement, liste d'exercices reordonnable.
struct SessionEditorView: View {
    @Bindable var session: ProgramSession

    @Environment(\.modelContext) private var modelContext

    @State private var editMode: EditMode = .inactive
    @State private var showingPicker = false
    @State private var editingExercise: PrescribedExercise?

    private var sortedExercises: [PrescribedExercise] {
        session.exercises.sorted { $0.orderIndex < $1.orderIndex }
    }

    var body: some View {
        List {
            Section("Nom") {
                TextField("Nom de la séance", text: $session.name)
            }

            Section {
                Toggle("Échauffement", isOn: $session.warmupEnabled)
            }

            Section("Exercices") {
                ForEach(sortedExercises) { exercise in
                    Button {
                        editingExercise = exercise
                    } label: {
                        ExercisePrescriptionRow(exercise: exercise)
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            delete(exercise)
                        } label: {
                            Label("Supprimer", systemImage: "trash")
                        }
                    }
                }
                .onMove(perform: moveExercises)
                .onDelete(perform: deleteExercises)

                Button {
                    showingPicker = true
                } label: {
                    Label("Ajouter un exercice", systemImage: "plus")
                }
            }
        }
        .environment(\.editMode, $editMode)
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(session.name.isEmpty ? "Séance" : session.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(editMode.isEditing ? "Terminé" : "Modifier") {
                    withAnimation { toggleEditing() }
                }
            }
        }
        .sheet(isPresented: $showingPicker) {
            ExercisePickerView { id, displayName in
                addExercise(exerciseId: id, displayName: displayName)
            }
        }
        .sheet(item: $editingExercise) { exercise in
            PrescriptionEditorView(exercise: exercise)
        }
        .onDisappear {
            try? modelContext.save()
        }
    }

    private func addExercise(exerciseId: String, displayName: String) {
        let defaultRest = UserDefaults.standard.object(forKey: "defaultRestSeconds") != nil ? UserDefaults.standard.integer(forKey: "defaultRestSeconds") : 90
        let exercise = PrescribedExercise(
            exerciseId: exerciseId,
            displayName: displayName,
            orderIndex: session.exercises.count,
            sets: 3,
            repsLower: 8,
            repsUpper: 12,
            restSeconds: defaultRest
        )
        exercise.session = session
        session.exercises.append(exercise)
        modelContext.insert(exercise)
        try? modelContext.save()
    }

    private func moveExercises(from source: IndexSet, to destination: Int) {
        var ordered = sortedExercises
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, exercise) in ordered.enumerated() {
            exercise.orderIndex = index
        }
        try? modelContext.save()
    }

    private func deleteExercises(at offsets: IndexSet) {
        let ordered = sortedExercises
        for index in offsets {
            modelContext.delete(ordered[index])
        }
        reindexExercises()
        try? modelContext.save()
    }

    private func delete(_ exercise: PrescribedExercise) {
        modelContext.delete(exercise)
        reindexExercises()
        try? modelContext.save()
    }

    private func reindexExercises() {
        for (index, exercise) in sortedExercises.enumerated() {
            exercise.orderIndex = index
        }
    }

    private func toggleEditing() {
        editMode = editMode.isEditing ? .inactive : .active
    }
}

private struct ExercisePrescriptionRow: View {
    let exercise: PrescribedExercise

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(exercise.displayName)
                .foregroundStyle(.primary)
            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var summary: String {
        switch exercise.format {
        case .classic:
            let reps = exercise.repsLower == exercise.repsUpper
                ? "\(exercise.repsLower)"
                : "\(exercise.repsLower)-\(exercise.repsUpper)"
            return "\(exercise.sets) x \(reps) - repos \(exercise.restSeconds) s"
        case .pyramid:
            return "Pyramide " + exercise.pyramidReps.map(String.init).joined(separator: "-")
        case .intervals:
            return "\(exercise.intervalWork)-\(exercise.intervalRest) x \(exercise.intervalRounds)"
        case .amrap:
            return "AMRAP \(exercise.amrapSeconds) s"
        }
    }
}

#Preview {
    let session = ProgramSession(name: "Push", orderIndex: 0, warmupEnabled: true)
    return NavigationStack {
        SessionEditorView(session: session)
    }
    .environment(CatalogStore())
    .modelContainer(for: ExerciseRecord.self, inMemory: true)
    .preferredColorScheme(.dark)
}
