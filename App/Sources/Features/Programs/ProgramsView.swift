import SwiftUI
import SwiftData

// Onglet Programmes : liste des programmes + creation (de zero / modele / generateur).
struct ProgramsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Program.name) private var programs: [Program]

    @State private var path = NavigationPath()
    @State private var showingAddChoice = false
    @State private var showingTemplatePicker = false
    @State private var showingGeneratorWizard = false
    @State private var programPendingDelete: Program?

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(programs) { program in
                    NavigationLink(value: program) {
                        ProgramRow(program: program)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            programPendingDelete = program
                        } label: {
                            Label("Supprimer", systemImage: "trash")
                        }
                        Button {
                            duplicate(program)
                        } label: {
                            Label("Dupliquer", systemImage: "plus.square.on.square")
                        }
                        .tint(.blue)
                        if !program.isActive {
                            Button {
                                activate(program)
                            } label: {
                                Label("Activer", systemImage: "checkmark.circle")
                            }
                            .tint(Theme.accent)
                        }
                    }
                    .contextMenu {
                        if !program.isActive {
                            Button {
                                activate(program)
                            } label: {
                                Label("Activer", systemImage: "checkmark.circle")
                            }
                        }
                        Button {
                            duplicate(program)
                        } label: {
                            Label("Dupliquer", systemImage: "plus.square.on.square")
                        }
                        Button(role: .destructive) {
                            programPendingDelete = program
                        } label: {
                            Label("Supprimer", systemImage: "trash")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Programmes")
            .navigationDestination(for: Program.self) { program in
                ProgramEditorView(program: program)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    // Dialog attache au bouton + lui-meme (pas a la vue
                    // englobante) pour que l'OS l'ancre sur ce bouton au
                    // lieu d'un popover centre avec une fleche errante.
                    Button {
                        showingAddChoice = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("programs.addButton")
                    .confirmationDialog("Nouveau programme", isPresented: $showingAddChoice, titleVisibility: .visible) {
                        Button("De zéro") { createFromScratch() }
                        Button("Depuis un modèle") { showingTemplatePicker = true }
                        Button("Générateur") { showingGeneratorWizard = true }
                        Button("Annuler", role: .cancel) {}
                    }
                }
            }
            .overlay {
                if programs.isEmpty {
                    ContentUnavailableView(
                        "Aucun programme",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Créez votre premier programme avec le bouton +.")
                    )
                }
            }
            .confirmationDialog(
                "Supprimer ce programme ?",
                isPresented: Binding(
                    get: { programPendingDelete != nil },
                    set: { if !$0 { programPendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Supprimer", role: .destructive) {
                    if let program = programPendingDelete {
                        delete(program)
                    }
                    programPendingDelete = nil
                }
                Button("Annuler", role: .cancel) {
                    programPendingDelete = nil
                }
            }
            .sheet(isPresented: $showingTemplatePicker) {
                TemplatePickerView(
                    onEdit: { program in path.append(program) },
                    onSaved: { showingTemplatePicker = false }
                )
            }
            .sheet(isPresented: $showingGeneratorWizard) {
                GeneratorWizardView(
                    onEdit: { program in path.append(program) },
                    onSaved: { showingGeneratorWizard = false }
                )
            }
        }
    }

    private func createFromScratch() {
        let program = Program(name: "Nouveau programme")
        modelContext.insert(program)
        try? modelContext.save()
        path.append(program)
    }

    private func activate(_ program: Program) {
        for existing in programs {
            existing.isActive = existing.id == program.id
        }
        try? modelContext.save()
    }

    private func duplicate(_ program: Program) {
        let copy = Program(name: program.name + " (copie)", notes: program.notes, isActive: false)
        modelContext.insert(copy)

        for session in program.sessions.sorted(by: { $0.orderIndex < $1.orderIndex }) {
            let sessionCopy = ProgramSession(name: session.name, orderIndex: session.orderIndex, warmupEnabled: session.warmupEnabled)
            sessionCopy.program = copy
            modelContext.insert(sessionCopy)
            copy.sessions.append(sessionCopy)

            for exercise in session.exercises.sorted(by: { $0.orderIndex < $1.orderIndex }) {
                let exerciseCopy = exercise.duplicated()
                exerciseCopy.session = sessionCopy
                modelContext.insert(exerciseCopy)
                sessionCopy.exercises.append(exerciseCopy)
            }
        }

        try? modelContext.save()
    }

    private func delete(_ program: Program) {
        modelContext.delete(program)
        try? modelContext.save()
    }
}

private struct ProgramRow: View {
    let program: Program

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(program.name.isEmpty ? "Programme" : program.name)
                    if program.isActive {
                        ActiveBadge()
                    }
                }
                Text(sessionCountLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var sessionCountLabel: String {
        let count = program.sessions.count
        return count > 1 ? "\(count) séances" : "\(count) séance"
    }
}

private struct ActiveBadge: View {
    var body: some View {
        Text("Actif")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Theme.accent.opacity(0.2))
            .foregroundStyle(Theme.accent)
            .clipShape(Capsule())
    }
}

#Preview {
    ProgramsView()
        .environment(CatalogStore())
        .modelContainer(for: Program.self, inMemory: true)
        .preferredColorScheme(.dark)
}
