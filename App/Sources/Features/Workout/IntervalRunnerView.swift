import SwiftUI
import AudioToolbox
import UIKit
import MuscuEngine

// Deroule automatique d'un bloc d'intervalles : alterne EFFORT/REPOS plein
// ecran, sons et haptique distincts a chaque changement de phase, pause
// possible, saisie optionnelle des reps totales a la fin du bloc.
struct IntervalRunnerView: View {
    let state: WorkoutState
    let exercise: RunExercise

    @State private var controller: IntervalController
    @State private var showingRepsEntry = false
    @State private var totalReps = 0

    init(state: WorkoutState, exercise: RunExercise) {
        self.state = state
        self.exercise = exercise
        let plan = IntervalPlan(
            workSeconds: exercise.intervalWork,
            restSeconds: exercise.intervalRest,
            rounds: exercise.intervalRounds
        )
        _controller = State(initialValue: IntervalController(segments: plan.segments()))
    }

    var body: some View {
        ZStack {
            phaseColor.ignoresSafeArea()

            if showingRepsEntry {
                repsEntryBody
            } else {
                runningBody
            }
        }
        .animation(.easeInOut(duration: 0.3), value: controller.index)
        .onAppear(perform: start)
    }

    private func start() {
        guard controller.onFinished == nil else { return }
        controller.onSegmentStart = { segment in
            AudioServicesPlaySystemSound(segment.kind == .work ? 1013 : 1016)
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        }
        controller.onFinished = { showingRepsEntry = true }
        controller.start()
    }

    private var phaseColor: Color {
        switch controller.currentSegment?.kind {
        case .work: return Theme.accent.opacity(0.25)
        case .rest: return Color.blue.opacity(0.25)
        case nil: return Theme.background
        }
    }

    private var runningBody: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { _ in
            VStack(spacing: 32) {
                Spacer()

                if let segment = controller.currentSegment {
                    Text(segment.kind == .work ? "EFFORT" : "REPOS")
                        .font(.system(size: 44, weight: .black))
                        .foregroundStyle(segment.kind == .work ? Theme.accent : .blue)

                    Text(formattedTime(controller.remaining))
                        .font(Theme.timerFont)
                        .monospacedDigit()
                        .foregroundStyle(.white)

                    Text("Round \(segment.round)/\(exercise.intervalRounds)")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 16) {
                    Button(controller.isPaused ? "Reprendre" : "Pause") {
                        controller.pauseToggle()
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.accent)

                    Button("Passer le bloc") {
                        controller.skipToEnd()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                }
                .controlSize(.large)
                .padding(.bottom, 40)
            }
            .padding()
        }
    }

    private var repsEntryBody: some View {
        VStack(spacing: 24) {
            Spacer()
            Text(exercise.displayName)
                .font(.title3.weight(.semibold))
            Text("Bloc terminé")
                .font(.headline)
                .foregroundStyle(Theme.accent)

            VStack(spacing: 8) {
                Text("Reps totales (optionnel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 24) {
                    Button {
                        totalReps = max(0, totalReps - 1)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 36))
                    }
                    Text("\(totalReps)")
                        .font(.system(size: 44, weight: .bold))
                        .monospacedDigit()
                        .frame(minWidth: 100)
                    Button {
                        totalReps += 1
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 36))
                    }
                }
                .foregroundStyle(Theme.accent)
            }

            Button {
                state.logIntervalBlock(totalReps: totalReps)
            } label: {
                Text("Valider")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .controlSize(.large)

            Spacer()
        }
        .padding()
    }

    private func formattedTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

// Machine a etats locale au deroule d'intervalles : segment par segment,
// chrono absolu (survit a une suspension breve), pause en conservant le
// temps restant. Distincte du RestTimer partage (qui gere le repos entre
// series classiques), car ici le decompte alterne effort/repos et compte
// des rounds.
@Observable
@MainActor
final class IntervalController {
    let segments: [IntervalSegment]

    private(set) var index = 0
    private(set) var segmentEndDate: Date?
    private(set) var isPaused = false
    private var pausedRemaining: TimeInterval = 0
    private var expiryTask: Task<Void, Never>?

    var onSegmentStart: ((IntervalSegment) -> Void)?
    var onFinished: (() -> Void)?

    init(segments: [IntervalSegment]) {
        self.segments = segments
    }

    var currentSegment: IntervalSegment? {
        index < segments.count ? segments[index] : nil
    }

    var remaining: Int {
        guard let segmentEndDate else { return 0 }
        return max(0, Int(segmentEndDate.timeIntervalSinceNow.rounded(.up)))
    }

    func start() {
        guard let segment = currentSegment else { return }
        segmentEndDate = Date.now.addingTimeInterval(Double(segment.seconds))
        isPaused = false
        onSegmentStart?(segment)
        scheduleExpiry()
    }

    func pauseToggle() {
        guard let segmentEndDate else { return }
        if isPaused {
            self.segmentEndDate = Date.now.addingTimeInterval(pausedRemaining)
            isPaused = false
            scheduleExpiry()
        } else {
            pausedRemaining = max(0, segmentEndDate.timeIntervalSinceNow)
            expiryTask?.cancel()
            isPaused = true
        }
    }

    func skipToEnd() {
        expiryTask?.cancel()
        index = segments.count
        segmentEndDate = nil
        onFinished?()
    }

    private func scheduleExpiry() {
        expiryTask?.cancel()
        guard let segmentEndDate else { return }
        let delay = max(0, segmentEndDate.timeIntervalSinceNow)
        expiryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.advance()
        }
    }

    private func advance() {
        index += 1
        if index >= segments.count {
            segmentEndDate = nil
            onFinished?()
        } else {
            start()
        }
    }
}
