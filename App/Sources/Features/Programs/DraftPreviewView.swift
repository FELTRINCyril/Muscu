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
    /// Plan pluri-semaines associe, quand le generateur en a produit un.
    /// Sans plan, l'enregistrement cree simplement le programme.
    var plan: DraftPlan?
    /// Reglages de periodisation ayant produit ce plan. Conserves sur le
    /// plan enregistre pour pouvoir recalculer ses semaines a venir.
    var periodizationStyle: PeriodizationStyle?
    var deloadEveryWeeks: Int?

    // Ferme la sheet racine du flux (TemplatePickerView ou GeneratorWizardView),
    // passee explicitement plutot que d'utiliser @Environment(\.dismiss) qui ne
    // fermerait que cet ecran pousse dans la pile de navigation interne.
    let onSaved: () -> Void

    @Environment(\.modelContext) private var modelContext

    @State private var currentDraft: DraftProgram
    @State private var expandedSessions: Set<Int>

    init(
        draft: DraftProgram,
        regenerate: (() -> DraftProgram?)? = nil,
        plan: DraftPlan? = nil,
        periodizationStyle: PeriodizationStyle? = nil,
        deloadEveryWeeks: Int? = nil,
        onSaved: @escaping () -> Void
    ) {
        self.draft = draft
        self.regenerate = regenerate
        self.plan = plan
        self.periodizationStyle = periodizationStyle
        self.deloadEveryWeeks = deloadEveryWeeks
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

            if let plan {
                planSection(plan)
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
                            ForEach(Array(session.exercises.enumerated()), id: \.offset) { _, exercise in
                                DraftExerciseRow(exercise: exercise)
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
    }

    /// Resume du plan : ce que l'utilisateur doit pouvoir lire AVANT
    /// d'enregistrer, y compris les raisons des choix du moteur.
    @ViewBuilder
    private func planSection(_ plan: DraftPlan) -> some View {
        Section("Plan sur \(plan.weeks.count) semaines") {
            ForEach(plan.rationale, id: \.self) { line in
                Label(line, systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }

        Section("Semaines") {
            ForEach(plan.weeks, id: \.number) { week in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Semaine \(week.number)")
                            .font(.subheadline.weight(.medium))
                        if week.isDeload {
                            Text("Décharge")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.accent.opacity(0.2))
                                .foregroundStyle(Theme.accent)
                                .clipShape(Capsule())
                        }
                        Spacer()
                        Text("\(week.workouts.count) séances")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(week.rationale)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func save() {
        if let plan {
            // Le plan porte deja son programme : on ne cree pas deux fois les
            // memes seances.
            PlanImporter.insert(
                draft: plan,
                into: modelContext,
                activateProgram: true,
                periodizationStyle: periodizationStyle,
                deloadEveryWeeks: deloadEveryWeeks
            )
            _ = PersistenceSupport.save(modelContext, action: "Enregistrement du plan")
        } else {
            let program = currentDraft.toModel()
            modelContext.insert(program)
            _ = PersistenceSupport.save(modelContext, action: "Enregistrement du programme")
        }
        onSaved()
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
            ? String(localized: "\(exercise.repsLower)")
            : String(localized: "\(exercise.repsLower)-\(exercise.repsUpper)")
        var text = String(localized: "\(exercise.sets) x \(reps) - repos \(exercise.restSeconds) s")
        if let percent = exercise.percentOneRepMax {
            text += String(localized: " - \(Int(percent))% 1RM")
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
