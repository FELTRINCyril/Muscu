import SwiftUI
import MuscuEngine

// Deroule d'un bloc AMRAP : decompte de la duree prescrite (chrono absolu,
// comme RestTimer), gros compteur de repetitions incremente par tap
// (haptique a chaque tap), correction possible ; a l'echeance, validation
// loggant le total.
struct AmrapRunnerView: View {
    let state: WorkoutState
    let exercise: WorkoutExercisePlan

    @State private var endDate: Date?
    @State private var isFinished = false
    @State private var counter = 0
    @State private var expiryTask: Task<Void, Never>?

    init(state: WorkoutState, exercise: WorkoutExercisePlan) {
        self.state = state
        self.exercise = exercise
        let restored = state.runtimeState.amrap.flatMap { $0.exerciseId == exercise.exerciseId ? $0 : nil }
        _endDate = State(initialValue: restored?.endDate)
        _isFinished = State(initialValue: restored?.isFinished ?? false)
        _counter = State(initialValue: restored?.counter ?? 0)
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                VStack(spacing: 32) {
                    VStack(spacing: 4) {
                        Text(exercise.displayName)
                            .font(.title3.weight(.semibold))
                        Text(exercise.objectiveLabel)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Text(formattedTime(remaining))
                        .timerFont()
                        .monospacedDigit()
                        .foregroundStyle(isFinished ? .secondary : Theme.accent)

                    counterCard

                    if isFinished {
                        Button {
                            state.logTimedBlock(totalReps: counter, durationSeconds: exercise.amrapSeconds)
                        } label: {
                            Text("Valider")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                        .controlSize(.large)
                        .padding(.horizontal)
                    }
                }
                .padding()
            }
        }
        .onAppear(perform: start)
    }

    private func start() {
        guard !isFinished else { return }
        if endDate == nil {
            endDate = Date.now.addingTimeInterval(Double(max(1, exercise.amrapSeconds)))
            persistRuntime()
        }
        guard let endDate else { return }
        let delay = max(0, endDate.timeIntervalSinceNow)
        if delay == 0 {
            finish()
            return
        }
        expiryTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            finish()
        }
    }

    private func finish() {
        guard !isFinished else { return }
        isFinished = true
        persistRuntime()
        FeedbackSettings.playSound(1005)
        FeedbackSettings.notification(.success)
    }

    private var remaining: Int {
        guard let endDate else { return exercise.amrapSeconds }
        return max(0, Int(endDate.timeIntervalSinceNow.rounded(.up)))
    }

    private var counterCard: some View {
        VStack(spacing: 12) {
            Text("\(counter)")
                .scaledSystemFont(size: 96, weight: .black)
                .minimumScaleFactor(0.4)
                .monospacedDigit()
                .foregroundStyle(.white)
            Text("répétitions")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if !isFinished {
                Button {
                    counter = max(0, counter - 1)
                    persistRuntime()
                } label: {
                    Label("Corriger (-1)", systemImage: "minus.circle")
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isFinished else { return }
            counter += 1
            persistRuntime()
            FeedbackSettings.impact(.light)
        }
        .accessibilityIdentifier("amrap.counterTapArea")
    }

    private func formattedTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    private func persistRuntime() {
        state.updateAmrapRuntime(AmrapRuntimeState(
            exerciseId: exercise.exerciseId,
            endDate: endDate,
            isFinished: isFinished,
            counter: counter
        ))
    }
}
