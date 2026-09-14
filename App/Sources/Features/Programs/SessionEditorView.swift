import SwiftUI
import SwiftData
import MuscuEngine

// Editeur d'une seance : nom, liste d'exercices reordonnable, et groupes
// (superset, triset, giant set, circuit) construits a partir d'exercices
// selectionnes.
struct SessionEditorView: View {
    @Bindable var session: ProgramSession

    @Environment(\.modelContext) private var modelContext

    @State private var editMode: EditMode = .inactive
    @State private var showingPicker = false
    @State private var editingExercise: PrescribedExercise?
    @State private var editingGroup: ExerciseGroup?
    @State private var selection: Set<UUID> = []
    @State private var groupError: String?

    private var sortedExercises: [PrescribedExercise] { session.orderedExercises }

    /// Exercices hors groupe, dans l'ordre de la seance.
    private var ungroupedExercises: [PrescribedExercise] {
        sortedExercises.filter { $0.group == nil }
    }

    var body: some View {
        List {
            Section("Nom") {
                TextField("Nom de la séance", text: $session.name)
            }

            ForEach(session.orderedGroups) { group in
                groupSection(group)
            }

            Section {
                ForEach(ungroupedExercises) { exercise in
                    exerciseRow(exercise)
                }
                .onMove(perform: moveExercises)
                .onDelete(perform: deleteUngrouped)

                Button {
                    showingPicker = true
                } label: {
                    Label("Ajouter un exercice", systemImage: "plus")
                }
            } header: {
                Text("Exercices")
            } footer: {
                if selection.count == 1 {
                    Text("1 exercice sélectionné · sélectionnez-en un second pour créer un groupe")
                        .font(.caption)
                        .accessibilityIdentifier("session.selectionCount")
                } else if selection.count >= 2 {
                    Text("\(selection.count) exercices sélectionnés")
                        .font(.caption)
                        .accessibilityIdentifier("session.selectionCount")
                } else if !ungroupedExercises.isEmpty {
                    Text("Appuyez longuement sur un exercice pour le sélectionner et créer un superset ou un circuit.")
                        .font(.caption)
                }
            }

            if selection.count >= 2 {
                Section("Créer un groupe") {
                    ForEach(creatableKinds, id: \.self) { kind in
                        Button {
                            createGroup(kind: kind)
                        } label: {
                            Label(kind.displayName, systemImage: "rectangle.3.group")
                        }
                        .accessibilityIdentifier("session.createGroup.\(kind.rawValue)")
                    }
                    Button("Annuler la sélection", role: .cancel) {
                        selection.removeAll()
                    }
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
        .sheet(item: $editingGroup) { group in
            ExerciseGroupEditorView(group: group)
        }
        .alert("Groupe impossible", isPresented: Binding(
            get: { groupError != nil },
            set: { if !$0 { groupError = nil } }
        )) {
            Button("OK", role: .cancel) { groupError = nil }
        } message: {
            Text(groupError ?? "")
        }
        .onDisappear {
            _ = PersistenceSupport.save(modelContext, action: "Modification de la séance")
        }
    }

    // MARK: - Sections

    private func groupSection(_ group: ExerciseGroup) -> some View {
        Section {
            ForEach(group.orderedExercises) { exercise in
                exerciseRow(exercise, prefix: groupLabel(for: exercise, in: group))
            }
            Button {
                editingGroup = group
            } label: {
                Label("Réglages du groupe", systemImage: "slider.horizontal.3")
            }
            .accessibilityIdentifier("session.editGroup")
            Button(role: .destructive) {
                ungroup(group)
            } label: {
                Label("Dissocier le groupe", systemImage: "rectangle.split.3x1")
            }
        } header: {
            Text(group.kind.displayName)
        } footer: {
            Text(groupFooter(group))
                .font(.caption)
        }
    }

    private func exerciseRow(_ exercise: PrescribedExercise, prefix: String? = nil) -> some View {
        Button {
            editingExercise = exercise
        } label: {
            HStack(spacing: 10) {
                if let prefix {
                    Text(prefix)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.accent)
                        .frame(minWidth: 24, alignment: .leading)
                }
                ExercisePrescriptionRow(exercise: exercise)
                Spacer(minLength: 0)
                if selection.contains(exercise.id) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.accent)
                        .accessibilityLabel("Sélectionné")
                }
            }
        }
        .contextMenu {
            if exercise.group == nil {
                Button {
                    toggleSelection(exercise)
                } label: {
                    Label(
                        selection.contains(exercise.id) ? "Désélectionner" : "Sélectionner",
                        systemImage: "checkmark.circle"
                    )
                }
                .accessibilityIdentifier("session.selectionToggle")
            } else {
                Button {
                    removeFromGroup(exercise)
                } label: {
                    Label("Sortir du groupe", systemImage: "arrow.up.forward.square")
                }
            }
            Button {
                duplicate(exercise)
            } label: {
                Label("Dupliquer", systemImage: "plus.square.on.square")
            }
            Button(role: .destructive) {
                delete(exercise)
            } label: {
                Label("Supprimer", systemImage: "trash")
            }
        }
    }

    private func groupLabel(for exercise: PrescribedExercise, in group: ExerciseGroup) -> String {
        let index = group.orderedExercises.firstIndex { $0.id == exercise.id } ?? 0
        return "A\(index + 1)"
    }

    private func groupFooter(_ group: ExerciseGroup) -> String {
        let rest = group.restBetweenExercisesSeconds == 0
            ? String(localized: "enchaîné")
            : String(localized: "\(group.restBetweenExercisesSeconds) s entre exercices")
        return "\(group.rounds) tours · \(rest) · \(group.restBetweenRoundsSeconds) s entre tours"
    }

    private var creatableKinds: [ExerciseGroupKind] {
        ExerciseGroupKind.allCases.filter { $0 != .single && $0.accepts(exerciseCount: selection.count) }
    }

    // MARK: - Actions

    private func toggleSelection(_ exercise: PrescribedExercise) {
        if selection.contains(exercise.id) {
            selection.remove(exercise.id)
        } else {
            selection.insert(exercise.id)
        }
    }

    /// Cree un groupe a partir de la selection. Les exercices gardent leur
    /// place dans la seance : seul leur rattachement change.
    private func createGroup(kind: ExerciseGroupKind) {
        let members = sortedExercises.filter { selection.contains($0.id) && $0.group == nil }
        guard kind.accepts(exerciseCount: members.count) else {
            groupError = String(localized: "Un \(kind.displayName) n’accepte pas \(members.count) exercices.")
            return
        }
        let defaultRest = members.map(\.restSeconds).max() ?? 90
        // Nombre de tours par defaut : le plus petit nombre de series des
        // exercices qui en comptent reellement. Les formats chronometres et
        // la pyramide n'utilisent pas `sets` : les inclure ramenerait le
        // groupe a un seul tour.
        let setCounts = members.map(\.sets).filter { $0 > 0 }
        let group = ExerciseGroup(
            kindRaw: kind.rawValue,
            orderIndex: session.groups.count,
            rounds: setCounts.min() ?? 3,
            restBetweenExercisesSeconds: 0,
            restBetweenRoundsSeconds: defaultRest
        )
        group.session = session
        modelContext.insert(group)
        session.groups.append(group)
        for (index, exercise) in members.enumerated() {
            exercise.group = group
            exercise.groupOrderIndex = index
        }
        selection.removeAll()
        session.touch()
        _ = PersistenceSupport.save(modelContext, action: "Création du groupe")
    }

    /// Dissocie le groupe sans supprimer les exercices : ils redeviennent
    /// des exercices simples, a leur place dans la seance.
    private func ungroup(_ group: ExerciseGroup) {
        for exercise in group.exercises {
            exercise.group = nil
            exercise.groupOrderIndex = 0
        }
        modelContext.delete(group)
        reindexGroups()
        session.touch()
        _ = PersistenceSupport.save(modelContext, action: "Dissociation du groupe")
    }

    private func removeFromGroup(_ exercise: PrescribedExercise) {
        guard let group = exercise.group else { return }
        exercise.group = nil
        exercise.groupOrderIndex = 0
        let remaining = group.orderedExercises
        for (index, member) in remaining.enumerated() { member.groupOrderIndex = index }
        // Un groupe qui n'a plus assez d'exercices n'a plus de sens : on le
        // dissout plutot que de laisser un superset a un seul exercice.
        if !group.kind.accepts(exerciseCount: remaining.count) {
            ungroup(group)
            return
        }
        session.touch()
        _ = PersistenceSupport.save(modelContext, action: "Sortie du groupe")
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
        session.touch()
        _ = PersistenceSupport.save(modelContext, action: "Ajout de l’exercice")
    }

    private func duplicate(_ exercise: PrescribedExercise) {
        let copy = PrescribedExercise(
            exerciseId: exercise.exerciseId,
            displayName: exercise.displayName,
            orderIndex: session.exercises.count,
            formatRaw: exercise.formatRaw,
            sets: exercise.sets,
            repsLower: exercise.repsLower,
            repsUpper: exercise.repsUpper,
            restSeconds: exercise.restSeconds,
            percentOneRepMax: exercise.percentOneRepMax,
            percentMaxReps: exercise.percentMaxReps,
            targetWeight: exercise.targetWeight,
            pyramidReps: exercise.pyramidReps,
            pyramidMinRest: exercise.pyramidMinRest,
            pyramidMaxRest: exercise.pyramidMaxRest,
            intervalWork: exercise.intervalWork,
            intervalRest: exercise.intervalRest,
            intervalRounds: exercise.intervalRounds,
            amrapSeconds: exercise.amrapSeconds,
            notes: exercise.notes,
            tempoNotation: exercise.tempoNotation,
            targetEffortData: exercise.targetEffortData,
            progressionRuleData: exercise.progressionRuleData,
            loadKindRaw: exercise.loadKindRaw,
            sideConventionRaw: exercise.sideConventionRaw,
            dropsetDrops: exercise.dropsetDrops,
            dropsetUsesPercent: exercise.dropsetUsesPercent,
            dropsetRestSeconds: exercise.dropsetRestSeconds,
            restPauseMicroRestSeconds: exercise.restPauseMicroRestSeconds,
            restPauseMaxMiniSets: exercise.restPauseMaxMiniSets,
            restPauseMinimumReps: exercise.restPauseMinimumReps,
            myoRepsActivationLower: exercise.myoRepsActivationLower,
            myoRepsActivationUpper: exercise.myoRepsActivationUpper,
            myoRepsTargetRepsInReserve: exercise.myoRepsTargetRepsInReserve,
            myoRepsMiniSetReps: exercise.myoRepsMiniSetReps,
            myoRepsMaxMiniSets: exercise.myoRepsMaxMiniSets,
            myoRepsRestSeconds: exercise.myoRepsRestSeconds,
            intervalCountdownSeconds: exercise.intervalCountdownSeconds,
            forTimeCapSeconds: exercise.forTimeCapSeconds
        )
        copy.session = session
        session.exercises.append(copy)
        modelContext.insert(copy)
        session.touch()
        _ = PersistenceSupport.save(modelContext, action: "Duplication de l’exercice")
    }

    private func moveExercises(from source: IndexSet, to destination: Int) {
        var ordered = ungroupedExercises
        ordered.move(fromOffsets: source, toOffset: destination)
        // Les exercices groupes gardent leur position : on ne reindexe que
        // ceux qui viennent d'etre deplaces.
        var index = 0
        for exercise in sortedExercises where exercise.group != nil {
            exercise.orderIndex = index
            index += 1
        }
        for exercise in ordered {
            exercise.orderIndex = index
            index += 1
        }
        session.touch()
        _ = PersistenceSupport.save(modelContext, action: "Réorganisation des exercices")
    }

    private func deleteUngrouped(at offsets: IndexSet) {
        let ordered = ungroupedExercises
        for index in offsets {
            selection.remove(ordered[index].id)
            modelContext.delete(ordered[index])
        }
        reindexExercises()
        session.touch()
        _ = PersistenceSupport.save(modelContext, action: "Suppression de l’exercice")
    }

    private func delete(_ exercise: PrescribedExercise) {
        let group = exercise.group
        selection.remove(exercise.id)
        modelContext.delete(exercise)
        if let group {
            let remaining = group.orderedExercises.filter { $0.id != exercise.id }
            if !group.kind.accepts(exerciseCount: remaining.count) {
                ungroup(group)
            }
        }
        reindexExercises()
        session.touch()
        _ = PersistenceSupport.save(modelContext, action: "Suppression de l’exercice")
    }

    private func reindexExercises() {
        for (index, exercise) in sortedExercises.enumerated() {
            exercise.orderIndex = index
        }
    }

    private func reindexGroups() {
        for (index, group) in session.orderedGroups.enumerated() {
            group.orderIndex = index
        }
    }

    private func toggleEditing() {
        editMode = editMode.isEditing ? .inactive : .active
    }
}

// MARK: - Ligne de prescription

struct ExercisePrescriptionRow: View {
    let exercise: PrescribedExercise

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(exercise.displayName)
                .foregroundStyle(.primary)
            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(exercise.displayName), \(summary)")
    }

    private var summary: String {
        switch exercise.format {
        case .classic:
            if let percentMaxReps = exercise.percentMaxReps {
                return String(localized: "\(exercise.sets) x \(Int(percentMaxReps)) % max reps - repos \(exercise.restSeconds) s")
            }
            let reps = exercise.repsLower == exercise.repsUpper
                ? String(localized: "\(exercise.repsLower)")
                : String(localized: "\(exercise.repsLower)-\(exercise.repsUpper)")
            return String(localized: "\(exercise.sets) x \(reps) - repos \(exercise.restSeconds) s")
        case .pyramid:
            return "Pyramide " + exercise.pyramidReps.map(String.init).joined(separator: "-")
        case .dropset:
            let unit = exercise.dropsetUsesPercent ? "%" : "kg"
            let drops = exercise.dropsetDrops.map { String(format: "%g", $0) }.joined(separator: "/")
            return String(localized: "Dropset \(exercise.sets) x — paliers -\(drops) \(unit)")
        case .restPause:
            return String(localized: "Rest-pause \(exercise.sets) x — \(exercise.restPauseMaxMiniSets) mini-séries, \(exercise.restPauseMicroRestSeconds) s")
        case .myoReps:
            return String(localized: "Myo-reps \(exercise.myoRepsActivationLower)-\(exercise.myoRepsActivationUpper) puis \(exercise.myoRepsMaxMiniSets) x \(exercise.myoRepsMiniSetReps)")
        case .intervals:
            return String(localized: "\(exercise.intervalWork)-\(exercise.intervalRest) x \(exercise.intervalRounds)")
        case .emom:
            return String(localized: "EMOM \(exercise.intervalRounds) min")
        case .amrap:
            return String(localized: "AMRAP \(exercise.amrapSeconds) s")
        case .forTime:
            return exercise.forTimeCapSeconds > 0
                ? String(localized: "For Time (cap \(exercise.forTimeCapSeconds) s)")
                : String(localized: "For Time")
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
