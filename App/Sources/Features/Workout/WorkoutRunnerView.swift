import SwiftUI
import MuscuEngine

// Ecran principal du deroule de seance : un exercice a la fois. Ne gere
// completement dans cette tache que le format classique ; les autres formats
// affichent un ecran relais que la Task 19 remplacera (dispatch par format
// isole dans `formatBody`, pas de branchement eparpille dans le reste de la vue).
struct WorkoutRunnerView: View {
    let state: WorkoutState

    @Environment(\.dismiss) private var dismiss
    @Environment(CatalogStore.self) private var catalogStore

    @State private var showingExitConfirm = false
    @State private var showingPicker = false
    @State private var showingOneRepMaxPrompt = false
    @State private var showingMaxRepsPrompt = false

    var body: some View {
        Group {
            if state.phase == .warmup {
                WarmupView(state: state)
            } else if state.isSessionComplete {
                WorkoutSummaryView(state: state, onFinish: { dismiss() })
            } else {
                runningBody
            }
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { state.restTimer.isRunning },
                set: { isPresented in
                    if !isPresented { state.restTimer.skip() }
                }
            )
        ) {
            RestTimerView(timer: state.restTimer)
        }
    }

    private var runningBody: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let exercise = state.currentExercise {
                    formatBody(for: exercise)
                }
                Spacer(minLength: 0)
            }
            .background(Theme.background)
            .navigationTitle(state.programSession.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // Le confirmationDialog est attache directement a ce
                    // bouton (pas a la vue englobante) pour que l'OS
                    // l'ancre visuellement sur le X, au lieu d'un popover
                    // centre avec une fleche errante (style iOS 26 quand
                    // aucune source precise n'est identifiable).
                    Button {
                        showingExitConfirm = true
                    } label: {
                        Image(systemName: "xmark")
                    }
                    // dismiss() direct : la fermeture d'un confirmationDialog
                    // n'ouvre PAS de nouvelle presentation UIKit (contrairement
                    // au chemin alerte -> runner de HomeView.resumeWorkout, qui
                    // a besoin de PresentationSync) - ici on ferme seulement le
                    // fullScreenCover qui est deja l'unique presentation active,
                    // aucune course possible.
                    .confirmationDialog("Quitter la séance ?", isPresented: $showingExitConfirm, titleVisibility: .visible) {
                        Button("Reprendre plus tard") {
                            dismiss()
                        }
                        Button("Abandonner", role: .destructive) {
                            state.discard()
                            dismiss()
                        }
                        Button("Annuler", role: .cancel) {}
                    }
                }
                ToolbarItem(placement: .principal) {
                    if state.currentExercise != nil {
                        Text(progressLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    actionsMenu
                }
            }
            .sheet(isPresented: $showingPicker) {
                ExercisePickerView(initialMuscleFilter: currentPrimaryMuscle) { id, displayName in
                    state.replaceExercise(exerciseId: id, displayName: displayName)
                }
            }
        }
    }

    @ViewBuilder
    private func formatBody(for exercise: RunExercise) -> some View {
        switch exercise.format {
        case .classic:
            ClassicExerciseCard(state: state, exercise: exercise, showingOneRepMaxPrompt: $showingOneRepMaxPrompt, showingMaxRepsPrompt: $showingMaxRepsPrompt)
        case .pyramid:
            PyramidRunnerView(state: state, exercise: exercise)
                .id(exercise.id)
        case .intervals:
            IntervalRunnerView(state: state, exercise: exercise)
                .id(exercise.id)
        case .amrap:
            AmrapRunnerView(state: state, exercise: exercise)
                .id(exercise.id)
        }
    }

    private var actionsMenu: some View {
        Menu {
            Button {
                state.skipExercise()
            } label: {
                Label("Passer l'exercice", systemImage: "forward.fill")
            }
            Button {
                showingPicker = true
            } label: {
                Label("Remplacer l'exercice", systemImage: "arrow.triangle.2.circlepath")
            }
            Button {
                state.addSet()
            } label: {
                Label("Ajouter une série", systemImage: "plus")
            }
            Button {
                state.removeSet()
            } label: {
                Label("Retirer une série", systemImage: "minus")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    private var currentPrimaryMuscle: String? {
        guard let exercise = state.currentExercise else { return nil }
        return catalogStore.exercise(id: exercise.exerciseId)?.primaryMuscles.first
    }

    private var progressLabel: String {
        "Exercice \(state.currentExerciseIndex + 1)/\(state.exercises.count)"
    }
}

// MARK: - Carte exercice classique

private struct ClassicExerciseCard: View {
    let state: WorkoutState
    let exercise: RunExercise
    @Binding var showingOneRepMaxPrompt: Bool
    @Binding var showingMaxRepsPrompt: Bool

    @Environment(CatalogStore.self) private var catalogStore

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ExerciseImageView(imagePath: catalogStore.exercise(id: exercise.exerciseId)?.images.first)
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(spacing: 4) {
                    Text(exercise.displayName)
                        .font(.title3.weight(.semibold))
                    Text("Série \(state.currentSetIndex + 1)/\(exercise.sets)")
                        .font(.subheadline)
                        .foregroundStyle(Theme.accent)
                    Text(objectiveText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let lastPerformance = state.lastPerformance(for: exercise) {
                        Text(lastPerformance)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if state.needsOneRepMax(for: exercise) {
                    Button {
                        showingOneRepMaxPrompt = true
                    } label: {
                        Label("Renseigner le 1RM pour calculer la charge", systemImage: "exclamationmark.circle")
                            .font(.footnote)
                    }
                    .buttonStyle(.bordered)
                }

                if state.needsMaxReps(for: exercise) {
                    Button {
                        showingMaxRepsPrompt = true
                    } label: {
                        Label("Renseigner le max de reps pour calculer l'objectif", systemImage: "exclamationmark.circle")
                            .font(.footnote)
                    }
                    .buttonStyle(.bordered)
                }

                SetLoggerView(
                    initialWeight: prefillWeight,
                    initialReps: prefillReps,
                    onValidate: { weight, reps in
                        state.logSet(weight: weight, reps: reps)
                    }
                )
                .id("\(exercise.id)-\(exercise.exerciseId)-\(state.currentSetIndex)")
            }
            .padding()
        }
        .sheet(isPresented: $showingOneRepMaxPrompt) {
            OneRepMaxPromptView(exercise: exercise) { value in
                state.saveOneRepMax(value, for: exercise)
            }
        }
        .sheet(isPresented: $showingMaxRepsPrompt) {
            MaxRepsPromptView(exercise: exercise) { value in
                state.saveMaxReps(value, for: exercise)
            }
        }
    }

    private var objectiveText: String {
        if let percent = exercise.percentMaxReps, let targetReps = state.suggestedReps(for: exercise) {
            return "\(exercise.sets) x \(targetReps) reps (\(Int(percent)) % du max)"
        }
        let reps = exercise.repsLower == exercise.repsUpper
            ? "\(exercise.repsLower)"
            : "\(exercise.repsLower)-\(exercise.repsUpper)"
        if let weight = state.suggestedWeight(for: exercise) {
            return "\(reps) reps @ \(WorkoutState.formatWeight(weight)) kg"
        }
        return "\(reps) reps"
    }

    private var prefillWeight: Double {
        state.suggestedWeight(for: exercise) ?? 0
    }

    private var prefillReps: Int {
        if let targetReps = state.suggestedReps(for: exercise) {
            return targetReps
        }
        return exercise.repsUpper > 0 ? exercise.repsUpper : exercise.repsLower
    }
}

// MARK: - Saisie du 1RM

private struct OneRepMaxPromptView: View {
    let exercise: RunExercise
    let onSave: (Double) -> Void

    @Environment(\.dismiss) private var dismiss

    private enum Mode: String { case direct, estimate }

    @State private var mode: Mode = .direct
    @State private var directWeight: Double = 0
    @State private var perfWeight: Double = 0
    @State private var perfReps: Int = 5

    var body: some View {
        NavigationStack {
            Form {
                Picker("Méthode", selection: $mode) {
                    Text("1RM connu").tag(Mode.direct)
                    Text("Estimer depuis une perf").tag(Mode.estimate)
                }
                .pickerStyle(.segmented)

                switch mode {
                case .direct:
                    Section("1RM (kg)") {
                        Stepper("\(WorkoutState.formatWeight(directWeight)) kg", value: $directWeight, in: 0...500, step: 2.5)
                    }
                case .estimate:
                    Section("Performance récente") {
                        Stepper("Poids : \(WorkoutState.formatWeight(perfWeight)) kg", value: $perfWeight, in: 0...500, step: 2.5)
                        Stepper("Répétitions : \(perfReps)", value: $perfReps, in: 1...30)
                        LabeledContent("1RM estimé", value: "\(WorkoutState.formatWeight(estimatedOneRepMax)) kg")
                    }
                }
            }
            .navigationTitle(exercise.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        onSave(mode == .direct ? directWeight : estimatedOneRepMax)
                        dismiss()
                    }
                }
            }
        }
    }

    private var estimatedOneRepMax: Double {
        OneRepMax.epley(weight: perfWeight, reps: perfReps)
    }
}

// MARK: - Saisie du max de reps

private struct MaxRepsPromptView: View {
    let exercise: RunExercise
    let onSave: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var maxReps: Int = 10

    var body: some View {
        NavigationStack {
            Form {
                Section("Ton max de reps ?") {
                    Stepper("\(maxReps) reps", value: $maxReps, in: 1...100)
                }
            }
            .navigationTitle(exercise.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        onSave(maxReps)
                        dismiss()
                    }
                }
            }
        }
    }
}
