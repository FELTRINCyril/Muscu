import SwiftUI
import MuscuEngine

// Deroule d'un bloc « For Time » : le travail est fixe, c'est le TEMPS qui
// est mesure. Chrono absolu (comme RestTimer et AMRAP) pour rester juste
// apres une mise en arriere-plan prolongee, plafond de temps facultatif,
// comptage des tours complets et des repetitions supplementaires.
struct ForTimeRunnerView: View {
    let state: WorkoutState
    let exercise: WorkoutExercisePlan

    @State private var startedAt: Date?
    @State private var finishedAt: Date?
    @State private var completedRounds = 0
    @State private var extraReps = 0
    @State private var capTask: Task<Void, Never>?

    init(state: WorkoutState, exercise: WorkoutExercisePlan) {
        self.state = state
        self.exercise = exercise
        let restored = state.runtimeState.forTime.flatMap { $0.exerciseId == exercise.exerciseId ? $0 : nil }
        _startedAt = State(initialValue: restored?.startedAt)
        _finishedAt = State(initialValue: restored?.finishedAt)
        _completedRounds = State(initialValue: restored?.completedRounds ?? 0)
        _extraReps = State(initialValue: restored?.extraReps ?? 0)
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                VStack(spacing: 28) {
                    VStack(spacing: 4) {
                        Text(exercise.displayName)
                            .font(.title3.weight(.semibold))
                        Text(exercise.objectiveLabel)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Text(formattedTime(elapsedSeconds))
                        .font(Theme.timerFont)
                        .monospacedDigit()
                        .foregroundStyle(isFinished ? .secondary : Theme.accent)
                        .accessibilityLabel("Temps écoulé : \(elapsedSeconds) secondes")

                    if exercise.capSeconds > 0 {
                        Text(capLabel)
                            .font(.caption)
                            .foregroundStyle(isCapped ? .orange : .secondary)
                    }

                    roundsCard

                    actionButton
                }
                .padding()
            }
        }
        .onAppear(perform: scheduleCapIfNeeded)
        .onDisappear { capTask?.cancel() }
    }

    // MARK: - Sous-vues

    private var roundsCard: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text("\(completedRounds)")
                    .font(.system(size: 72, weight: .black))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text("tours complets")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !isFinished {
                HStack(spacing: 12) {
                    Button {
                        completedRounds = max(0, completedRounds - 1)
                        persistRuntime()
                    } label: {
                        Label("Retirer un tour", systemImage: "minus.circle")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.bordered)
                    .tint(.secondary)
                    .accessibilityLabel("Retirer un tour")

                    Button {
                        completedRounds += 1
                        persistRuntime()
                        FeedbackSettings.impact(.light)
                    } label: {
                        Label("Tour terminé", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .accessibilityIdentifier("forTime.addRound")
                }

                Stepper("Répétitions en plus : \(extraReps)", value: $extraReps, in: 0...500)
                    .onChange(of: extraReps) { _, _ in persistRuntime() }
                    .padding(.horizontal)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    @ViewBuilder
    private var actionButton: some View {
        if startedAt == nil {
            Button {
                startedAt = .now
                persistRuntime()
                scheduleCapIfNeeded()
                FeedbackSettings.impact(.medium)
            } label: {
                Text("Démarrer")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .controlSize(.large)
            .accessibilityIdentifier("forTime.start")
        } else if !isFinished {
            Button {
                finish()
            } label: {
                Text("Terminé")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .controlSize(.large)
            .accessibilityIdentifier("forTime.finish")
        } else {
            Button {
                // Le resultat d'un For Time est son TEMPS : il est enregistre
                // comme duree de la serie, les tours et reps comme volume.
                state.logTimedBlock(
                    totalReps: completedRounds * max(1, exercise.repsLower) + extraReps,
                    durationSeconds: elapsedSeconds
                )
            } label: {
                Text("Valider")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .controlSize(.large)
            .accessibilityIdentifier("forTime.validate")
        }
    }

    // MARK: - Logique

    private var isFinished: Bool { finishedAt != nil }

    private var isCapped: Bool {
        guard exercise.capSeconds > 0 else { return false }
        return elapsedSeconds >= exercise.capSeconds
    }

    private var capLabel: String {
        isCapped
            ? String(localized: "Plafond de temps atteint")
            : String(localized: "Plafond : \(formattedTime(exercise.capSeconds))")
    }

    /// Temps ecoule, fige a la fin du bloc. Calcule depuis des dates
    /// absolues : une suspension longue de l'app ne fausse rien.
    private var elapsedSeconds: Int {
        guard let startedAt else { return 0 }
        let reference = finishedAt ?? .now
        return max(0, Int(reference.timeIntervalSince(startedAt).rounded()))
    }

    /// Au plafond, le bloc se termine tout seul : rien n'est valide a la
    /// place de l'utilisateur, qui confirme ensuite son resultat.
    private func scheduleCapIfNeeded() {
        capTask?.cancel()
        guard let startedAt, !isFinished, exercise.capSeconds > 0 else { return }
        let deadline = startedAt.addingTimeInterval(Double(exercise.capSeconds))
        let delay = deadline.timeIntervalSinceNow
        if delay <= 0 {
            // Le plafond est deja depasse (app suspendue pendant le bloc) :
            // on fige le temps a la valeur du plafond, pas a l'instant present.
            finish(at: deadline)
            return
        }
        capTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            finish(at: deadline)
        }
    }

    private func finish(at date: Date = .now) {
        guard !isFinished, startedAt != nil else { return }
        finishedAt = date
        capTask?.cancel()
        persistRuntime()
        FeedbackSettings.playSound(1005)
        FeedbackSettings.notification(.success)
    }

    private func formattedTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    private func persistRuntime() {
        state.updateForTimeRuntime(ForTimeRuntimeState(
            exerciseId: exercise.exerciseId,
            startedAt: startedAt,
            finishedAt: finishedAt,
            completedRounds: completedRounds,
            extraReps: extraReps
        ))
    }
}
