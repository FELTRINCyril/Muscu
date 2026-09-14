import SwiftUI
import MuscuEngine

// Deroule automatique d'un bloc d'intervalles : alterne EFFORT/REPOS plein
// ecran, sons et haptique distincts a chaque changement de phase, pause
// possible, saisie optionnelle des reps totales a la fin du bloc.
struct IntervalRunnerView: View {
    let state: WorkoutState
    let exercise: WorkoutExercisePlan

    @State private var controller: IntervalController
    @State private var showingRepsEntry = false
    @State private var totalReps = 0

    init(state: WorkoutState, exercise: WorkoutExercisePlan) {
        self.state = state
        self.exercise = exercise
        let plan = Self.intervalPlan(for: exercise)
        let restored = state.runtimeState.interval.flatMap { $0.exerciseId == exercise.exerciseId ? $0 : nil }
        _controller = State(initialValue: IntervalController(segments: plan.segments(), restoring: restored))
        _showingRepsEntry = State(initialValue: restored?.showingRepsEntry ?? false)
        _totalReps = State(initialValue: restored?.totalReps ?? 0)
    }

    // Le plan d'intervalles derive du format : un EMOM est une suite de
    // minutes sans repos, un bloc d'intervalles alterne travail et repos.
    static func intervalPlan(for exercise: WorkoutExercisePlan) -> IntervalPlan {
        switch exercise.format {
        case .emom:
            return IntervalPlan(
                workSeconds: exercise.intervalWorkSeconds > 0 ? exercise.intervalWorkSeconds : 60,
                restSeconds: 0,
                rounds: exercise.intervalRounds
            )
        default:
            return IntervalPlan(
                workSeconds: exercise.intervalWorkSeconds,
                restSeconds: exercise.intervalRestSeconds,
                rounds: exercise.intervalRounds
            )
        }
    }

    private var intervalPlan: IntervalPlan { Self.intervalPlan(for: exercise) }

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
            FeedbackSettings.playSound(segment.kind == .work ? 1013 : 1016)
            FeedbackSettings.impact(.heavy)
        }
        controller.onFinished = {
            showingRepsEntry = true
            persistRuntime()
        }
        controller.onStateChange = { _ in persistRuntime() }
        controller.start()
        persistRuntime()
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
                VStack(spacing: 4) {
                    Text(exercise.displayName)
                        .font(.title3.weight(.semibold))
                    Text(exercise.objectiveLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)

                Spacer()

                if let segment = controller.currentSegment {
                    Text(segment.kind == .work ? "EFFORT" : "REPOS")
                        .scaledSystemFont(size: 44, weight: .black)
                        .minimumScaleFactor(0.5)
                        .foregroundStyle(segment.kind == .work ? Theme.accent : .blue)

                    Text(formattedTime(controller.isPaused ? Int(controller.pausedRemaining.rounded(.up)) : controller.remaining))
                        .timerFont()
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
            VStack(spacing: 4) {
                Text(exercise.displayName)
                    .font(.title3.weight(.semibold))
                Text(exercise.objectiveLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
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
                        persistRuntime()
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .scaledSystemFont(size: 36, relativeTo: .title)
                    }
                    Text("\(totalReps)")
                        .scaledSystemFont(size: 44, weight: .bold)
                        .minimumScaleFactor(0.5)
                        .monospacedDigit()
                        .frame(minWidth: 100)
                    Button {
                        totalReps += 1
                        persistRuntime()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .scaledSystemFont(size: 36, relativeTo: .title)
                    }
                }
                .foregroundStyle(Theme.accent)
            }

            Button {
                state.logTimedBlock(totalReps: totalReps, durationSeconds: intervalPlan.totalDuration)
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

    private func persistRuntime() {
        state.updateIntervalRuntime(IntervalRuntimeState(
            exerciseId: exercise.exerciseId,
            index: controller.index,
            segmentEndDate: controller.segmentEndDate,
            isPaused: controller.isPaused,
            pausedRemaining: controller.pausedRemaining,
            showingRepsEntry: showingRepsEntry,
            totalReps: totalReps
        ))
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
    private(set) var pausedRemaining: TimeInterval = 0
    private var expiryTask: Task<Void, Never>?

    var onSegmentStart: ((IntervalSegment) -> Void)?
    var onFinished: (() -> Void)?
    var onStateChange: ((IntervalController) -> Void)?

    init(segments: [IntervalSegment], restoring state: IntervalRuntimeState? = nil) {
        self.segments = segments
        if let state {
            index = min(max(0, state.index), segments.count)
            segmentEndDate = state.segmentEndDate
            isPaused = state.isPaused
            pausedRemaining = max(0, state.pausedRemaining)
        }
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
        if isPaused {
            onStateChange?(self)
            return
        }
        if let segmentEndDate {
            if segmentEndDate <= .now {
                advance()
            } else {
                scheduleExpiry()
            }
            onStateChange?(self)
            return
        }
        segmentEndDate = Date.now.addingTimeInterval(Double(segment.seconds))
        isPaused = false
        onSegmentStart?(segment)
        scheduleExpiry()
        onStateChange?(self)
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
        onStateChange?(self)
    }

    func skipToEnd() {
        expiryTask?.cancel()
        index = segments.count
        segmentEndDate = nil
        onStateChange?(self)
        onFinished?()
    }

    private func scheduleExpiry() {
        expiryTask?.cancel()
        guard let segmentEndDate else { return }
        let delay = max(0, segmentEndDate.timeIntervalSinceNow)
        expiryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.advance()
        }
    }

    private func advance() {
        // En cas de suspension, plusieurs segments peuvent avoir expire.
        // On repart de l'ancienne echeance absolue (pas de Date.now), puis
        // on saute tous les segments deja ecoules afin de ne pas rallonger
        // artificiellement le bloc au retour dans l'app.
        var nextEndDate = segmentEndDate ?? .now
        index += 1
        while index < segments.count {
            nextEndDate = nextEndDate.addingTimeInterval(Double(segments[index].seconds))
            if nextEndDate > .now {
                segmentEndDate = nextEndDate
                isPaused = false
                onSegmentStart?(segments[index])
                scheduleExpiry()
                onStateChange?(self)
                return
            }
            index += 1
        }
        segmentEndDate = nil
        onStateChange?(self)
        onFinished?()
    }
}
