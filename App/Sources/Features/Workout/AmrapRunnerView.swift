import SwiftUI
import MuscuEngine

// Deroule d'un bloc AMRAP : decompte de la duree prescrite (chrono absolu,
// comme RestTimer), gros compteur de repetitions incremente par tap
// (haptique a chaque tap), correction possible ; a l'echeance, validation
// loggant le total.
struct AmrapRunnerView: View {
    let state: WorkoutState
    let exercise: RunExercise

    @State private var endDate: Date?
    @State private var isFinished = false
    @State private var counter = 0
    @State private var expiryTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                VStack(spacing: 32) {
                    VStack(spacing: 4) {
                        Text(exercise.displayName)
                            .font(.title3.weight(.semibold))
                        Text(WorkoutState.objectiveLabel(for: exercise))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Text(formattedTime(remaining))
                        .font(Theme.timerFont)
                        .monospacedDigit()
                        .foregroundStyle(isFinished ? .secondary : Theme.accent)

                    counterCard

                    if isFinished {
                        Button {
                            state.logAmrapBlock(reps: counter)
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
        guard endDate == nil else { return }
        endDate = Date.now.addingTimeInterval(Double(exercise.amrapSeconds))
        expiryTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(Double(exercise.amrapSeconds) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            finish()
        }
    }

    private func finish() {
        guard !isFinished else { return }
        isFinished = true
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
                .font(.system(size: 96, weight: .black))
                .monospacedDigit()
                .foregroundStyle(.white)
            Text("répétitions")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if !isFinished {
                Button {
                    counter = max(0, counter - 1)
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
            FeedbackSettings.impact(.light)
        }
    }

    private func formattedTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}
