import SwiftUI
import MuscuEngine

// Ecran principal du deroule de seance. Ce que l'on affiche n'est jamais
// decide ici : c'est la machine a etats du moteur qui produit l'etape
// courante (`WorkoutStep`), la vue se contente de la presenter.
struct WorkoutRunnerView: View {
    let state: WorkoutState

    @Environment(\.dismiss) private var dismiss
    @Environment(CatalogStore.self) private var catalogStore
    @Environment(\.scenePhase) private var scenePhase

    @State private var showingExitConfirm = false
    @State private var showingPicker = false
    @State private var showingOverview = false
    @State private var showingOneRepMaxPrompt = false
    @State private var showingMaxRepsPrompt = false
    @State private var showingAddExercise = false
    @State private var showingReorder = false

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
                    // Une fermeture due a la fin du repos ne doit PAS
                    // effacer le depassement qui commence.
                    if !isPresented, state.restTimer.isRunning { state.restTimer.skip() }
                }
            )
        ) {
            RestTimerView(timer: state.restTimer, upNext: restUpNext)
                .overlay(alignment: .top) { LiveRecordBannerHost(state: state) }
        }
        // La Live Activity suit la seance : elle demarre avec le runner et
        // se met a jour a chaque changement d'etape ou de repos.
        .onAppear {
            updateScreenAwake()
            guard !state.isSessionComplete else { return }
            state.startLiveActivity()
            state.startHealthWorkout()
        }
        .onChange(of: state.restTimer.isRunning) { _, _ in state.refreshLiveActivity() }
        // +30 s et nouveau repos changent la fin sans changer `isRunning`.
        .onChange(of: state.restTimer.endDate) { _, _ in state.refreshLiveActivity() }
        // Seance terminee ou abandonnee depuis Siri / Raccourcis : le
        // deroule n'a plus rien a montrer.
        .onChange(of: state.endedOutsideRunner) { _, ended in
            if ended { dismiss() }
        }
        .onAppear { LiveWorkoutRegistry.shared.runnerDidAppear(state) }
        .onDisappear { LiveWorkoutRegistry.shared.runnerDidDisappear(state) }
        // Ecran allume tant qu'une seance est en cours ET visible ; retabli
        // a la fin, a la sortie du deroule et en arriere-plan.
        .onChange(of: state.isSessionComplete) { _, _ in updateScreenAwake() }
        .onChange(of: scenePhase) { _, _ in updateScreenAwake() }
        .onDisappear { ScreenAwake.update(workoutIsOnScreen: false) }
    }

    private var restUpNext: Text? {
        guard let next = state.pyramidUpNext else { return nil }
        return Text("Ensuite : palier \(next.step) sur \(next.total) · \(next.reps) reps")
    }

    private func updateScreenAwake() {
        ScreenAwake.update(workoutIsOnScreen: scenePhase == .active && !state.isSessionComplete)
    }

    private var runningBody: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Une seance allegee doit le DIRE. Reduire les series sans le
                // signaler serait une modification silencieuse du programme,
                // exactement ce que la roadmap interdit.
                if !state.weekScaling.isNeutral {
                    WeekScalingBanner(scaling: state.weekScaling)
                }
                LiveHealthCard(controller: LiveHealthWorkoutController.shared, startedAt: state.startedAt)
                if state.restTimer.isOvertime {
                    RestOvertimeBanner(timer: state.restTimer)
                }
                if let node = state.currentNode, node.isGroup, let target = state.currentTarget {
                    GroupOverviewBar(node: node, target: target)
                }
                stepBody
                Spacer(minLength: 0)
            }
            .background(Theme.background)
            .overlay(alignment: .top) { LiveRecordBannerHost(state: state) }
            .navigationTitle(state.sessionTitle)
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
                            // La seance Sante en direct se met en pause
                            // avec elle, et reprend a la reprise.
                            LiveHealthWorkoutController.shared.pause()
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
                if let exercise = state.currentExercise {
                    SubstitutionPickerView(
                        currentExerciseId: exercise.exerciseId,
                        prescriptionId: exercise.id
                    ) { id, displayName in
                        state.replaceExercise(exerciseId: id, displayName: displayName)
                    }
                } else {
                    ExercisePickerView(initialMuscleFilter: currentPrimaryMuscle) { id, displayName in
                        state.replaceExercise(exerciseId: id, displayName: displayName)
                    }
                }
            }
            .sheet(isPresented: $showingOverview) {
                SessionOverviewView(state: state) { position in
                    state.moveTo(position: position)
                }
            }
            // Ajout pour cette seance uniquement : le programme ne change pas.
            .sheet(isPresented: $showingAddExercise) {
                ExercisePickerView(initialMuscleFilter: nil) { id, displayName in
                    state.addExercise(exerciseId: id, displayName: displayName)
                }
            }
            .sheet(isPresented: $showingReorder) {
                ReorderExercisesView(state: state)
            }
        }
    }

    @ViewBuilder
    private var stepBody: some View {
        switch state.currentStep {
        case .finished:
            // Seance libre : un deroule epuise attend l'exercice suivant.
            if state.isFreeSession {
                FreeSessionIdleView(state: state) { showingAddExercise = true }
            } else {
                EmptyView()
            }
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
            if state.currentExercise != nil {
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
            }
            Button {
                showingAddExercise = true
            } label: {
                Label("Ajouter un exercice", systemImage: "plus.rectangle.on.rectangle")
            }
            .accessibilityIdentifier("workout.addExercise")
            if state.reorderableNodes.count > 1 {
                Button {
                    showingReorder = true
                } label: {
                    Label("Réordonner les exercices restants", systemImage: "arrow.up.arrow.down")
                }
                .accessibilityIdentifier("workout.reorderExercises")
            }
            // Ce que mesure l'exercice courant : poids x repetitions, temps
            // (gainage), distance (portage, course). Format classique seul.
            if let exercise = state.currentExercise, exercise.format == .classic {
                Picker(
                    selection: Binding(
                        get: { exercise.effectiveMeasure },
                        set: { state.setMeasure($0) }
                    )
                ) {
                    ForEach(SetMeasure.allCases, id: \.self) { measure in
                        Text(measure.displayName).tag(measure)
                    }
                } label: {
                    Label("Mesure de l'exercice", systemImage: "ruler")
                }
                .pickerStyle(.menu)
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
            if state.isFreeSession, !state.loggedSets.isEmpty {
                Button {
                    state.requestEnd()
                } label: {
                    Label("Terminer la séance", systemImage: "flag.checkered")
                }
                .accessibilityIdentifier("workout.finishFreeSession")
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
        return String(localized: "Série \(min(progress.completed + 1, progress.total))/\(progress.total)")
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
/// Bandeau d'une semaine allegee : il dit ce qui a change et pourquoi.
/// Repos depasse : le temps ecoule depuis la fin prevue, en couleur
/// d'alerte, jusqu'a la serie suivante. Dire combien de temps le repos a
/// vraiment dure vaut mieux qu'un chrono qui disparait a zero.
private struct RestOvertimeBanner: View {
    let timer: RestTimer

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let label = timer.countdown(at: context.date)?.label ?? ""
            HStack(spacing: 8) {
                Image(systemName: "timer")
                Text("Repos dépassé")
                Spacer()
                Text(verbatim: label)
                    .monospacedDigit()
                    .fontWeight(.semibold)
                Button("Masquer") { timer.skip() }
                    .font(.caption)
                    .buttonStyle(.bordered)
            }
            .font(.subheadline)
            .foregroundStyle(.orange)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.12))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("Repos dépassé de \(label)"))
            .accessibilityIdentifier("workout.restOvertime")
        }
    }
}

private struct WeekScalingBanner: View {
    let scaling: WeekScaling

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.right.circle")
            Text(text)
                .font(.footnote)
            Spacer(minLength: 0)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Theme.accent.opacity(0.15))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("workout.weekScaling")
    }

    private var text: String {
        let volume = Int((scaling.volumeMultiplier * 100).rounded())
        let intensity = Int((scaling.intensityMultiplier * 100).rounded())
        // « Séance » et non « Semaine » : l'allègement vient d'une semaine de
        // décharge OU d'un check-in de forme accepté. Nommer la semaine
        // serait faux dans le second cas.
        return String(
            localized: "Séance allégée : volume \(volume) %, intensité \(intensity) %. Les séries et charges ont été réduites."
        )
    }
}

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
    @Environment(\.massUnit) private var massUnit

    private var exercise: WorkoutExercisePlan { target.exercise }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ExerciseImageView(imagePath: catalogStore.exercise(id: exercise.exerciseId)?.images.first)
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(spacing: 4) {
                    // Identifiant stable : les tests d'exécution vérifient sur
                    // QUEL exercice on se trouve sans avoir à parcourir tout
                    // l'arbre d'accessibilité, ce qui est lent et fragile.
                    Text(exercise.displayName)
                        .font(.title3.weight(.semibold))
                        .accessibilityIdentifier("workout.exerciseName")
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
                }

                // Remplace l'ancienne ligne « La dernière fois » : la séance
                // la plus récente y figure, avec les précédentes.
                PreviousSessionsStripView(entries: state.previousSessionsStrip(for: exercise))

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

                if exercise.effectiveMeasure == .weightReps {
                    SetLoggerView(
                        initialWeight: state.prefillWeight(for: target),
                        initialReps: prefillReps,
                        weightStepKilograms: state.loadStepKilograms(for: exercise),
                        previous: state.previousSet(for: target),
                        showsPlateCalculator: state.usesBarbell(exercise),
                        onValidate: { (result: SetLoggerView.Result) in
                            state.logSet(
                                weight: result.weight,
                                reps: result.reps,
                                effort: result.effort,
                                reachedFailure: result.reachedFailure,
                                notes: result.notes,
                                role: result.role
                            )
                        }
                    )
                    .id(setIdentity)
                } else {
                    MeasuredSetLoggerView(
                        measure: exercise.effectiveMeasure,
                        targetDurationSeconds: exercise.targetDurationSeconds,
                        targetDistanceMeters: exercise.targetDistanceMeters,
                        initialWeight: exercise.targetWeight ?? 0,
                        weightStepKilograms: state.loadStepKilograms(for: exercise),
                        onValidate: { result in
                            state.logMeasuredSet(
                                result.measured,
                                weight: result.weight,
                                notes: result.notes,
                                role: result.role
                            )
                        }
                    )
                    .id("\(setIdentity)-\(exercise.effectiveMeasure.rawValue)")
                }

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
        if let measured = measuredObjective {
            return measured
        }
        if let percent = exercise.percentMaxReps, let targetReps = state.suggestedReps(for: exercise) {
            return "\(exercise.setCount) x \(targetReps) reps (\(Int(percent)) % du max)"
        }
        let reps = target.targetRepsLower == target.targetRepsUpper
            ? "\(target.targetRepsLower)"
            : "\(target.targetRepsLower)-\(target.targetRepsUpper)"
        let weight = state.prefillWeight(for: target)
        if weight > 0 {
            return "\(reps) reps @ \(WeightFormatter.string(kilograms: weight, unit: massUnit))"
        }
        return "\(reps) reps"
    }

    /// Objectif d'une serie au temps ou a la distance : la cible quand
    /// elle existe, sinon la nature de la mesure.
    private var measuredObjective: String? {
        let measure = exercise.effectiveMeasure
        guard measure != .weightReps else { return nil }
        var parts: [String] = []
        if measure.measuresDuration {
            if let target = exercise.targetDurationSeconds, target > 0 {
                parts.append(CompletedSetPresentation.formattedDuration(target))
            } else {
                parts.append(String(localized: "Temps"))
            }
        }
        if measure.measuresDistance {
            if let target = exercise.targetDistanceMeters, target > 0 {
                parts.append(MeasureFormatter.distance(meters: target))
            } else {
                parts.append(String(localized: "Distance"))
            }
        }
        return parts.joined(separator: " · ")
    }

    /// Meme regle que la Live Activity : elle vit dans `WorkoutState`.
    private var prefillReps: Int {
        state.prefillReps(for: target)
    }
}

// MARK: - Saisie du 1RM

private struct OneRepMaxPromptView: View {
    let exercise: WorkoutExercisePlan
    let onSave: (Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.massUnit) private var massUnit

    private enum Mode: String { case direct, estimate }

    /// Charges saisies dans l'unite du profil, converties en kg a
    /// l'enregistrement.
    @State private var mode: Mode = .direct
    @State private var directWeight: Double = 2.5
    @State private var perfWeight: Double = 2.5
    @State private var perfReps: Int = 5
    @State private var didSetInitialWeights = false

    /// Pas usuel dans l'unite affichee : 2,5 kg ou 5 lb.
    private var displayStep: Double { (massUnit.fromKilograms(massUnit.defaultIncrementKilograms) * 100).rounded() / 100 }
    private var displayRange: ClosedRange<Double> { displayStep...massUnit.fromKilograms(500).rounded() }
    /// Au-dela du plafond regle, l'estimation n'est plus retenue nulle part
    /// ailleurs : la proposer ici serait incoherent.
    private var maximumReps: Int { WorkoutSettings.maximumRepsForOneRepMax }

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
                    Section("1RM (\(massUnit.symbol))") {
                        Stepper(
                            "\(WeightFormatter.number(directWeight)) \(massUnit.symbol)",
                            value: $directWeight,
                            in: displayRange,
                            step: displayStep
                        )
                    }
                case .estimate:
                    Section("Performance récente") {
                        Stepper(
                            "Poids : \(WeightFormatter.number(perfWeight)) \(massUnit.symbol)",
                            value: $perfWeight,
                            in: displayRange,
                            step: displayStep
                        )
                        Stepper("Répétitions : \(perfReps)", value: $perfReps, in: 1...max(1, maximumReps))
                        LabeledContent("1RM estimé", value: WeightFormatter.string(kilograms: estimatedOneRepMax, unit: massUnit))
                    }
                }
            }
            .navigationTitle(exercise.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                // L'unite n'est connue qu'une fois la vue installee : les
                // valeurs de depart suivent le pas de cette unite.
                guard !didSetInitialWeights else { return }
                didSetInitialWeights = true
                directWeight = displayStep
                perfWeight = displayStep
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        onSave(mode == .direct ? massUnit.toKilograms(directWeight) : estimatedOneRepMax)
                        dismiss()
                    }
                    .disabled((mode == .direct ? directWeight : perfWeight) <= 0)
                }
            }
        }
    }

    /// 1RM estime, en kg canonique.
    private var estimatedOneRepMax: Double {
        OneRepMax.epley(weight: massUnit.toKilograms(perfWeight), reps: min(perfReps, maximumReps))
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
