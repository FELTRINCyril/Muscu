import SwiftUI
import SwiftData

// Editeur d'un programme : nom, notes, liste des seances reordonnable.
struct ProgramEditorView: View {
    @Bindable var program: Program

    @Environment(\.modelContext) private var modelContext

    @State private var editMode: EditMode = .inactive

    private var sortedSessions: [ProgramSession] {
        program.sessions.sorted { $0.orderIndex < $1.orderIndex }
    }

    var body: some View {
        List {
            Section("Nom") {
                TextField("Nom du programme", text: $program.name)
            }

            Section("Notes") {
                TextField("Notes (optionnel)", text: $program.notes, axis: .vertical)
                    .lineLimit(3...6)
            }

            Section("Séances") {
                ForEach(sortedSessions) { session in
                    NavigationLink {
                        SessionEditorView(session: session)
                    } label: {
                        SessionRow(session: session)
                    }
                    .contextMenu {
                        Button {
                            duplicate(session)
                        } label: {
                            Label("Dupliquer", systemImage: "plus.square.on.square")
                        }
                        Button(role: .destructive) {
                            delete(session)
                        } label: {
                            Label("Supprimer", systemImage: "trash")
                        }
                    }
                }
                .onMove(perform: moveSessions)
                .onDelete(perform: deleteSessions)

                Button {
                    addSession()
                } label: {
                    Label("Ajouter une séance", systemImage: "plus")
                }
            }
        }
        .environment(\.editMode, $editMode)
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(program.name.isEmpty ? "Nouveau programme" : program.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(editMode.isEditing ? "Terminé" : "Modifier") {
                    withAnimation { toggleEditing() }
                }
            }
        }
        .onDisappear {
            try? modelContext.save()
        }
    }

    private func addSession() {
        let session = ProgramSession(name: "Séance \(program.sessions.count + 1)", orderIndex: program.sessions.count)
        session.program = program
        program.sessions.append(session)
        modelContext.insert(session)
        try? modelContext.save()
    }

    private func duplicate(_ session: ProgramSession) {
        let copy = ProgramSession(
            name: session.name + " (copie)",
            orderIndex: program.sessions.count,
            warmupEnabled: session.warmupEnabled
        )
        copy.program = program
        modelContext.insert(copy)
        program.sessions.append(copy)

        for exercise in session.exercises.sorted(by: { $0.orderIndex < $1.orderIndex }) {
            let exerciseCopy = exercise.duplicated()
            exerciseCopy.session = copy
            modelContext.insert(exerciseCopy)
            copy.exercises.append(exerciseCopy)
        }

        try? modelContext.save()
    }

    private func moveSessions(from source: IndexSet, to destination: Int) {
        var ordered = sortedSessions
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, session) in ordered.enumerated() {
            session.orderIndex = index
        }
        try? modelContext.save()
    }

    private func deleteSessions(at offsets: IndexSet) {
        let ordered = sortedSessions
        for index in offsets {
            modelContext.delete(ordered[index])
        }
        reindexSessions()
        try? modelContext.save()
    }

    private func delete(_ session: ProgramSession) {
        modelContext.delete(session)
        reindexSessions()
        try? modelContext.save()
    }

    private func reindexSessions() {
        for (index, session) in sortedSessions.enumerated() {
            session.orderIndex = index
        }
    }

    private func toggleEditing() {
        editMode = editMode.isEditing ? .inactive : .active
    }
}

private struct SessionRow: View {
    let session: ProgramSession

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(session.name.isEmpty ? "Séance" : session.name)
                if session.warmupEnabled {
                    Image(systemName: "flame.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Text(exerciseCountLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var exerciseCountLabel: String {
        let count = session.exercises.count
        return count > 1 ? "\(count) exercices" : "\(count) exercice"
    }
}

// Duplication profonde d'une prescription (utilisee pour dupliquer une seance
// ou un programme entier).
extension PrescribedExercise {
    func duplicated() -> PrescribedExercise {
        PrescribedExercise(
            exerciseId: exerciseId,
            displayName: displayName,
            orderIndex: orderIndex,
            formatRaw: formatRaw,
            sets: sets,
            repsLower: repsLower,
            repsUpper: repsUpper,
            restSeconds: restSeconds,
            percentOneRepMax: percentOneRepMax,
            pyramidReps: pyramidReps,
            pyramidMinRest: pyramidMinRest,
            pyramidMaxRest: pyramidMaxRest,
            intervalWork: intervalWork,
            intervalRest: intervalRest,
            intervalRounds: intervalRounds,
            amrapSeconds: amrapSeconds,
            notes: notes
        )
    }
}

#Preview {
    let program = Program(name: "Prise de masse")
    return NavigationStack {
        ProgramEditorView(program: program)
    }
    .modelContainer(for: Program.self, inMemory: true)
    .preferredColorScheme(.dark)
}
