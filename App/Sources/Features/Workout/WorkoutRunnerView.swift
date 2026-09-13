import SwiftUI
import MuscuEngine

// Ecran principal du deroule de seance. Ce que l'on affiche n'est jamais
// decide ici : c'est la machine a etats du moteur qui produit l'etape
// courante (`WorkoutStep`), la vue se contente de la presenter.
struct WorkoutRunnerView: View {
    let state: WorkoutState

    @Environment(\.dismiss) private var dismiss
    @Environment(CatalogStore.self) private var catalogStore

    @State private var showingExitConfirm = false
    @State private var showingPicker = false
    @State private var showingOverview = false
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
                if let node = state.currentNode, node.isGroup, let target = state.currentTarget {
                    GroupOverviewBar(node: node, target: target)
                }
                stepBody
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
                    .accessibilityIdentifier("workout.exitButton")
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
                    SessionChronoLabel(
                        startedAt: state.startedAt,
                        subtitle: state.currentExercise != nil ? progressLabel : nil
                    )
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
            .sheet(isPresented: $showingOverview) {
                SessionOverviewView(state: state) { position in
                    state.moveTo(position: position)
                }
            }
        }
    }

    @ViewBuilder
    private var stepBody: some View {
        switch state.currentStep {
        case .finished:
            EmptyView()
        case .timedBlock(let exercise):
            timedBody(for: exercise)
        case .logSet(let target):
            switch target.exercise.format {
            case .pyramid:
                PyramidRunnerView(state: state, exercise: target.exercise)
                    .id("\(target.exercise.id)-pyramid")
            case .classic, .dropset, .restPause, .myoReps:
                SetEntryCard(
                    state: state,
                    target: target,
                    showingOneRepMaxPrompt: $showingOneRepMaxPrompt,
                    showingMaxRepsPrompt: $showingMaxRepsPrompt
                )
            case .intervals, .emom, .amrap, .forTime:
                // Un format chronometre ne produit jamais d'etape de saisie :
                // la machine a etats renvoie `timedBlock`. Ce cas ne peut donc
                // pas se produire, mais on ne bloque jamais la seance.
                timedBody(for: target.exercise)
            }
        }
    }

    @ViewBuilder
    private func timedBody(for exercise: WorkoutExercisePlan) -> some View {
        switch exercise.format {
        case .amrap:
            AmrapRunnerView(state: state, exercise: exercise)
                .id(exercise.id)
        case .forTime:
            ForTimeRunnerView(state: state, exercise: exercise)
                .id(exercise.id)
        default:
            IntervalRunnerView(state: state, exercise: exercise)
                .id(exercise.id)
        }
    }

    private var actionsMenu: some View {
        Menu {
            Button {
                showingOverview = true
            } label: {
                Label("Aperçu de la séance", systemImage: "list.bullet.rectangle")
            }
            if state.canStepBack {
                Button {
                    state.stepBack()
                } label: {
                    Label("Corriger la série précédente", systemImage: "arrow.uturn.backward")
                }
            }
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
            if let node = state.currentNode, node.isGroup {
                Button {
                    state.addSet()
                } label: {
                    Label("Ajouter un tour", systemImage: "plus")
                }
                Button {
                    state.removeSet()
                } label: {
                    Label("Retirer un tour", systemImage: "minus")
                }
            } else if state.currentExercise?.format == .classic {
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
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityIdentifier("workout.actionsMenu")
    }

    private var currentPrimaryMuscle: String? {
        guard let exercise = state.currentExercise else { return nil }
        return catalogStore.exercise(id: exercise.exerciseId)?.primaryMuscles.first
    }

    private var progressLabel: String {
        let progress = state.progress
        return "Série \(min(progress.completed + 1, progress.total))/\(progress.total)"
    }
}

// MARK: - Chrono de duree de seance

// Chrono absolu (base sur state.startedAt, pas un compteur incremente a la
// main) : reste correct meme apres un arriere-plan prolonge ou un
// kill+resume, et reste coherent avec la duree finale affichee par
// WorkoutSummaryView (meme reference de depart). Affiche dans le toolbar
// principal du runner ET de l'echauffement (cf. WarmupView), puisque
// startedAt est fixe a la creation de la seance, avant l'echauffement.
struct SessionChronoLabel: View {
    let startedAt: Date
    var subtitle: String?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 0) {
                Text(Self.formatElapsed(context.date.timeIntervalSince(startedAt)))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private static func formatElapsed(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Vue d'ensemble d'un groupe

// Bandeau affiche au-dessus d'un superset, triset, giant set ou circuit :
// tour courant, exercice courant et enchainement du groupe. Sans lui, rien
// a l'ecran ne distingue un superset d'une suite d'exercices independants.
private struct GroupOverviewBar: View {
    let node: WorkoutNode
    let target: WorkoutSetTarget

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(kindLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                Spacer()
                Text("Tour \(target.round)/\(target.totalRounds)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                ForEach(Array(node.exercises.enumerated()), id: \.element.id) { index, exercise in
                    Text(letter(for: index))
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(index + 1 == target.memberPosition ? Theme.accent : Color.white.opacity(0.12))
                        .foregroundStyle(index + 1 == target.memberPosition ? Color.black : Color.white)
                        .clipShape(Capsule())
                        .accessibilityLabel("\(letter(for: index)) \(exercise.displayName)")
                        .accessibilityAddTraits(index + 1 == target.memberPosition ? [.isSelected] : [])
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(kindLabel), tour \(target.round) sur \(target.totalRounds), exercice \(target.memberPosition) sur \(target.totalMembers) : \(target.exercise.displayName)")
    }

    private var kindLabel: String {
        switch node.kind {
        case .single: return String(localized: "Exercice")
        case .superset: return String(localized: "Superset")
        case .triset: return String(localized: "Triset")
        case .giantSet: return String(localized: "Giant set")
        case .circuit: return String(localized: "Circuit")
        }
    }

    // A1, A2, A3... : la convention usuelle pour noter un groupe.
    private func letter(for index: Int) -> String {
        "A\(index + 1)"
    }
}

// MARK: - Carte de saisie d'une serie

// Utilisee par tous les formats qui se saisissent serie par serie :
// classique, dropset, rest-pause et myo-reps. Les differences tiennent a
// l'objectif affiche et aux actions de fin de bloc, pas a un ecran distinct.
private struct SetEntryCard: View {
    let state: WorkoutState
    let target: WorkoutSetTarget
    @Binding var showingOneRepMaxPrompt: Bool
    @Binding var showingMaxRepsPrompt: Bool

    @Environment(CatalogStore.self) private var catalogStore

    private var exercise: WorkoutExercisePlan { target.exercise }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ExerciseImageView(imagePath: catalogStore.exercise(id: exercise.exerciseId)?.images.first)
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(spacing: 4) {
                    Text(exercise.displayName)
                        .font(.title3.weight(.semibold))
                    Text(setLabel)
                        .font(.subheadline)
                        .foregroundStyle(Theme.accent)
                    Text(objectiveText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let tempo = exercise.tempo, !tempo.isZero {
                        Text("Tempo \(tempo.notation)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Tempo \(tempo.notation), soit \(tempo.secondsPerRep) secondes par répétition")
                    }
                    if let effort = exercise.targetEffort {
                        Text("Effort visé : \(effort.displayText)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
                    initialWeight: state.prefillWeight(for: target),
                    initialReps: prefillReps,
                    onValidate: { (result: SetLoggerView.Result) in
                        state.logSet(
                            weight: result.weight,
                            reps: result.reps,
                            effort: result.effort,
                            reachedFailure: result.reachedFailure,
                            notes: result.notes
                        )
                    }
                )
                .id(setIdentity)

                if canStopSubSets {
                    Button("Terminer le bloc après cette série") {
                        state.logSet(
                            weight: state.prefillWeight(for: target),
                            reps: prefillReps,
                            stopsSubSets: true
                        )
                    }
                    .font(.footnote)
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("workout.stopSubSets")
                }
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

    // Identite de la saisie : change a chaque creneau reel (serie, tour,
    // palier) pour que SetLoggerView reparte de la bonne valeur pre-remplie.
    private var setIdentity: String {
        "\(exercise.id)-\(exercise.exerciseId)-\(target.round)-\(target.setNumber)-\(target.subSetIndex)"
    }

    private var setLabel: String {
        switch exercise.format {
        case .dropset where target.isSubSet:
            return String(localized: "Palier \(target.subSetIndex)")
        case .restPause where target.isSubSet:
            return String(localized: "Mini-série \(target.subSetIndex)")
        case .myoReps where target.isSubSet:
            return String(localized: "Myo-série \(target.subSetIndex)")
        case .myoReps:
            return String(localized: "Série d'activation")
        default:
            return String(localized: "Série \(target.setNumber)/\(target.totalSets)")
        }
    }

    // Rest-pause et myo-reps s'arretent sur decision de l'utilisateur autant
    // que sur un seuil : le bouton n'est propose que dans un bloc en cours.
    private var canStopSubSets: Bool {
        switch exercise.format {
        case .restPause, .myoReps: return target.isSubSet
        case .classic, .pyramid, .dropset, .intervals, .emom, .amrap, .forTime: return false
        }
    }

    private var objectiveText: String {
        if !exercise.objectiveLabel.isEmpty, exercise.format != .classic {
            return exercise.objectiveLabel
        }
        if let percent = exercise.percentMaxReps, let targetReps = state.suggestedReps(for: exercise) {
            return "\(exercise.setCount) x \(targetReps) reps (\(Int(percent)) % du max)"
        }
        let reps = target.targetRepsLower == target.targetRepsUpper
            ? "\(target.targetRepsLower)"
            : "\(target.targetRepsLower)-\(target.targetRepsUpper)"
        let weight = state.prefillWeight(for: target)
        if weight > 0 {
            return "\(reps) reps @ \(WorkoutState.formatWeight(weight)) kg"
        }
        return "\(reps) reps"
    }

    private var prefillReps: Int {
        if let targetReps = state.suggestedReps(for: exercise) {
            return targetReps
        }
        if target.targetRepsUpper > 0 { return target.targetRepsUpper }
        return target.targetRepsLower > 0 ? target.targetRepsLower : 1
    }
}

// MARK: - Saisie du 1RM

private struct OneRepMaxPromptView: View {
    let exercise: WorkoutExercisePlan
    let onSave: (Double) -> Void

    @Environment(\.dismiss) private var dismiss

    private enum Mode: String { case direct, estimate }

    @State private var mode: Mode = .direct
    @State private var directWeight: Double = 2.5
    @State private var perfWeight: Double = 2.5
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
                        Stepper("\(WorkoutState.formatWeight(directWeight)) kg", value: $directWeight, in: 2.5...500, step: 2.5)
                    }
                case .estimate:
                    Section("Performance récente") {
                        Stepper("Poids : \(WorkoutState.formatWeight(perfWeight)) kg", value: $perfWeight, in: 2.5...500, step: 2.5)
                        Stepper("Répétitions : \(perfReps)", value: $perfReps, in: 1...12)
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
                    .disabled((mode == .direct ? directWeight : perfWeight) <= 0)
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
    let exercise: WorkoutExercisePlan
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
