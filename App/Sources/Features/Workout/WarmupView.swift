import SwiftUI
import MuscuEngine

// Premiere phase de la seance quand `warmupEnabled` : cardio leger (chrono
// simple, passable) puis montee en charge sur le premier exercice lourd de
// la seance (Warmup.rampSets), chaque palier loggeable individuellement.
// Passable a tout moment via "Passer l'échauffement".
struct WarmupView: View {
    let state: WorkoutState

    @State private var cardioEndDate: Date?
    @State private var cardioSkipped = false
    @State private var checkedRamps: Set<Int> = []

    private var rampSets: [WarmupSet] {
        state.warmupRampSets()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    cardioCard

                    if !rampSets.isEmpty {
                        rampCard
                    }
                }
                .padding()
            }
            .background(Theme.background)
            .navigationTitle("Échauffement")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button {
                    state.finishWarmup()
                } label: {
                    Text(allRampsChecked ? "Commencer la séance" : "Passer l'échauffement")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .controlSize(.large)
                .padding()
                .background(.ultraThinMaterial)
            }
        }
        .onAppear {
            guard cardioEndDate == nil else { return }
            cardioEndDate = Date.now.addingTimeInterval(Double(Warmup.cardioMinutes * 60))
        }
    }

    private var allRampsChecked: Bool {
        !rampSets.isEmpty && checkedRamps.count == rampSets.count
    }

    private var cardioCard: some View {
        VStack(spacing: 16) {
            Text("\(Warmup.cardioMinutes) min de cardio léger")
                .font(.title3.weight(.semibold))

            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(formattedRemaining)
                    .font(Theme.timerFont)
                    .monospacedDigit()
                    .foregroundStyle(cardioSkipped || cardioRemaining == 0 ? .secondary : Theme.accent)
            }

            Button("Passer le cardio") {
                cardioSkipped = true
                cardioEndDate = Date.now
            }
            .buttonStyle(.bordered)
            .tint(Theme.accent)
            .disabled(cardioSkipped || cardioRemaining == 0)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var cardioRemaining: Int {
        guard let cardioEndDate else { return Warmup.cardioMinutes * 60 }
        return max(0, Int(cardioEndDate.timeIntervalSinceNow.rounded(.up)))
    }

    private var formattedRemaining: String {
        let seconds = cardioRemaining
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private var rampCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let target = state.warmupTargetExercise() {
                Text("Montée en charge - \(target.displayName)")
                    .font(.headline)
            }

            ForEach(Array(rampSets.enumerated()), id: \.offset) { index, ramp in
                HStack {
                    Text("\(WorkoutState.formatWeight(ramp.weight)) kg x \(ramp.reps)")
                        .font(.body.monospacedDigit())
                    Spacer()
                    Button {
                        state.logWarmupSet(ramp, rampIndex: index)
                        checkedRamps.insert(index)
                    } label: {
                        Image(systemName: checkedRamps.contains(index) ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                    }
                    .disabled(checkedRamps.contains(index))
                }
                .foregroundStyle(checkedRamps.contains(index) ? Theme.accent : .primary)
                .padding()
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}
