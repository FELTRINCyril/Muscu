import SwiftUI
import SwiftData
import MuscuEngine

// Apercu d'un DraftProgram genere (modele ou generateur) avant enregistrement :
// seances depliables, exercices avec prescription resumee.
// "Enregistrer" convertit en Program (SwiftData) et ferme tout le flux d'origine.
// "Regenerer" relance le generateur avec le meme input (deterministe pour le moment).
struct DraftPreviewView: View {
    let draft: DraftProgram
    let regenerate: (() -> DraftProgram?)?

    // Ouvre directement l'editeur complet du programme (via ProgramsView) apres
    // enregistrement, si fourni. nil par defaut : bouton "Modifier" absent.
    let onEdit: ((Program) -> Void)?

    // Ferme la sheet racine du flux (TemplatePickerView ou GeneratorWizardView),
    // passee explicitement plutot que d'utiliser @Environment(\.dismiss) qui ne
    // fermerait que cet ecran pousse dans la pile de navigation interne.
    let onSaved: () -> Void

    @Environment(\.modelContext) private var modelContext

    @State private var currentDraft: DraftProgram
    @State private var expandedSessions: Set<Int>
    @State private var swapTarget: SwapTarget?

    init(
        draft: DraftProgram,
        regenerate: (() -> DraftProgram?)? = nil,
        onEdit: ((Program) -> Void)? = nil,
        onSaved: @escaping () -> Void
    ) {
        self.draft = draft
        self.regenerate = regenerate
        self.onEdit = onEdit
        self.onSaved = onSaved
        self._currentDraft = State(initialValue: draft)
        self._expandedSessions = State(initialValue: Set(draft.sessions.indices))
    }

    var body: some View {
        List {
            Section {
                Text(currentDraft.name)
                    .font(.title3.weight(.semibold))
                if !currentDraft.notes.isEmpty {
                    Text(currentDraft.notes)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(Array(currentDraft.sessions.enumerated()), id: \.offset) { index, session in
                Section {
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { expandedSessions.contains(index) },
                            set: { isExpanded in
                                if isExpanded {
                                    expandedSessions.insert(index)
                                } else {
                                    expandedSessions.remove(index)
                                }
                            }
                        )
                    ) {
                        if session.exercises.isEmpty {
                            Text("Aucun exercice compatible trouvé pour cette séance.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(session.exercises.enumerated()), id: \.offset) { exerciseIndex, exercise in
                                HStack {
                                    DraftExerciseRow(exercise: exercise)
                                    Spacer()
                                    Button {
                                        swapTarget = SwapTarget(
                                            sessionIndex: index,
                                            exerciseIndex: exerciseIndex,
                                            exerciseId: exercise.exerciseId
                                        )
                                    } label: {
                                        Image(systemName: "arrow.triangle.2.circlepath")
                                            .foregroundStyle(Theme.accent)
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("Remplacer \(exercise.displayName)")
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Text(session.name)
                                .font(.headline)
                            Spacer()
                            Text(exerciseCountLabel(session.exercises.count))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Aperçu")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if onEdit != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button("Modifier") { saveAndEdit() }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                Button {
                    save()
                } label: {
                    Text("Enregistrer")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)

                if let regenerate {
                    Button {
                        if let newDraft = regenerate() {
                            currentDraft = newDraft
                            expandedSessions = Set(newDraft.sessions.indices)
                        }
                    } label: {
                        Text("Régénérer")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
            .background(.ultraThinMaterial)
        }
        .sheet(item: $swapTarget) { target in
            ExerciseSwapSheet(currentExerciseId: target.exerciseId) { newId, newName in
                currentDraft.sessions[target.sessionIndex].exercises[target.exerciseIndex].exerciseId = newId
                currentDraft.sessions[target.sessionIndex].exercises[target.exerciseIndex].displayName = newName
            }
        }
    }

    private func save() {
        let program = currentDraft.toModel()
        modelContext.insert(program)
        try? modelContext.save()
        onSaved()
    }

    // Enregistre le brouillon puis ouvre directement l'editeur complet du
    // programme (via ProgramsView), au lieu d'obliger a enregistrer -> retrouver
    // le programme dans la liste -> l'ouvrir.
    private func saveAndEdit() {
        let program = currentDraft.toModel()
        modelContext.insert(program)
        try? modelContext.save()
        onSaved()
        onEdit?(program)
    }

    private func exerciseCountLabel(_ count: Int) -> String {
        count > 1 ? "\(count) exercices" : "\(count) exercice"
    }
}

// Hashable requis par navigationDestination(item:) ; DraftProgram est deja Equatable
// (synthetise dans MuscuEngine), on derive un hash coherent (mais partiel) a partir
// du nom et du nombre de seances - suffisant pour l'identite de navigation.
extension DraftProgram: @retroactive Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(notes)
        hasher.combine(sessions.count)
    }
}

private struct SwapTarget: Identifiable {
    let sessionIndex: Int
    let exerciseIndex: Int
    let exerciseId: String
    var id: String { "\(sessionIndex)-\(exerciseIndex)" }
}

private struct DraftExerciseRow: View {
    let exercise: DraftExercise

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
        let reps = exercise.repsLower == exercise.repsUpper
            ? "\(exercise.repsLower)"
            : "\(exercise.repsLower)-\(exercise.repsUpper)"
        var text = "\(exercise.sets) x \(reps) - repos \(exercise.restSeconds) s"
        if let percent = exercise.percentOneRepMax {
            text += " - \(Int(percent))% 1RM"
        }
        return text
    }
}

#Preview {
    let draft = DraftProgram(
        name: "Programme Prise de masse 3j/semaine",
        notes: "",
        sessions: [
            DraftSession(name: "Push", warmupEnabled: true, exercises: [
                DraftExercise(exerciseId: "1", displayName: "Développé couché", sets: 4, repsLower: 6, repsUpper: 12, restSeconds: 90, percentOneRepMax: nil),
            ]),
        ]
    )
    return NavigationStack {
        DraftPreviewView(draft: draft, regenerate: nil, onSaved: {})
    }
    .modelContainer(for: Program.self, inMemory: true)
    .preferredColorScheme(.dark)
}
