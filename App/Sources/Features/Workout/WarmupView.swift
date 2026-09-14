import SwiftUI
import MuscuEngine

// Premiere phase de la seance, toujours proposee : ecran de choix
// (cardio chronometre / echauffement libre en chrono compte-up / passage
// direct), puis un ecran "Continuer l'echauffement ?" permettant d'enchainer
// plusieurs blocs avant de demarrer reellement la seance. Toujours sortie
// via `state.finishWarmup()`, quel que soit le chemin pris.
struct WarmupView: View {
    let state: WorkoutState

    private enum Step: Equatable {
        case choice
        case cardioDuration
        case cardioCountdown(endDate: Date, minutes: Int)
        case free(startedAt: Date)
        case continueChoice
    }

    @State private var step: Step = .choice
    @State private var cardioMinutesChoice: Int = Warmup.cardioMinutes
    @State private var checkedRamps: Set<Int> = []

    init(state: WorkoutState) {
        self.state = state
        let runtime = state.runtimeState.warmup
        _step = State(initialValue: Self.step(from: runtime))
        _cardioMinutesChoice = State(initialValue: runtime.cardioMinutes)
    }

    private var rampSets: [WarmupSet] {
        state.warmupRampSets()
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .choice:
                    choiceScreen
                case .cardioDuration:
                    cardioDurationScreen
                case .cardioCountdown(let endDate, let minutes):
                    cardioCountdownScreen(endDate: endDate, minutes: minutes)
                case .free(let startedAt):
                    freeScreen(startedAt: startedAt)
                case .continueChoice:
                    continueScreen
                }
            }
            .background(Theme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    SessionChronoLabel(startedAt: state.startedAt, subtitle: "Échauffement")
                }
            }
        }
        .onAppear {
            restoreCheckedRamps()
            persistStep()
        }
        .onChange(of: cardioMinutesChoice) { _, _ in persistStep() }
    }

    // MARK: - Ecran de choix initial

    private var choiceScreen: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 12)

            VStack(spacing: 16) {
                WarmupOptionCard(title: "Cardio", subtitle: "Chrono minute", systemImage: "figure.run") {
                    transition(to: .cardioDuration)
                }
                WarmupOptionCard(title: "Échauffement libre", subtitle: "Chrono libre + montée en charge", systemImage: "figure.flexibility") {
                    transition(to: .free(startedAt: .now))
                }
            }
            .padding(.horizontal)

            Spacer()

            Button("Commencer directement la séance") {
                state.finishWarmup()
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Cardio : choix de la duree

    private var cardioDurationScreen: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 12)

            Text("Durée du cardio")
                .font(.title3.weight(.semibold))

            HStack(spacing: 12) {
                ForEach([5, 10, 15], id: \.self) { minutes in
                    Button {
                        cardioMinutesChoice = minutes
                    } label: {
                        Text("\(minutes) min")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                    .tint(cardioMinutesChoice == minutes ? Theme.accent : .secondary)
                }
            }
            .padding(.horizontal)

            Stepper("\(cardioMinutesChoice) min", value: $cardioMinutesChoice, in: 1...60)
                .padding(.horizontal, 40)

            Spacer()

            Button {
                transition(to: .cardioCountdown(endDate: Date.now.addingTimeInterval(Double(cardioMinutesChoice * 60)), minutes: cardioMinutesChoice))
            } label: {
                Text("Démarrer le cardio")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .controlSize(.large)
            .padding()
        }
    }

    // MARK: - Cardio : decompte

    private func cardioCountdownScreen(endDate: Date, minutes: Int) -> some View {
        VStack(spacing: 40) {
            Spacer()

            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                let remaining = max(0, Int((endDate.timeIntervalSince(context.date)).rounded(.up)))
                ZStack {
                    Circle()
                        .stroke(Theme.card, lineWidth: 14)
                    Circle()
                        .trim(from: 0, to: cardioProgress(endDate: endDate, minutes: minutes, now: context.date))
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.5), value: remaining)

                    Text(Self.formatSeconds(remaining))
                        .timerFont()
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                        .frame(maxWidth: 260 - 14 * 2 - 24 * 2)
                        .padding(24)
                        .foregroundStyle(.white)
                }
                .frame(width: 260, height: 260)
                .onChange(of: remaining) { _, newValue in
                    if newValue == 0 {
                        transition(to: .continueChoice)
                    }
                }
            }

            Spacer()

            Button("Terminer le cardio") {
                transition(to: .continueChoice)
            }
            .buttonStyle(.bordered)
            .tint(Theme.accent)
            .controlSize(.large)
            .padding(.bottom, 40)
        }
    }

    private func cardioProgress(endDate: Date, minutes: Int, now: Date) -> Double {
        let total = Double(minutes * 60)
        guard total > 0 else { return 1 }
        let remaining = max(0, endDate.timeIntervalSince(now))
        return 1 - min(1, max(0, remaining / total))
    }

    // MARK: - Echauffement libre

    private func freeScreen(startedAt: Date) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(Self.formatSeconds(Int(context.date.timeIntervalSince(startedAt).rounded(.down))))
                        .timerFont()
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                        .foregroundStyle(Theme.accent)
                }
                .padding(.top, 12)

                if !rampSets.isEmpty {
                    rampCard
                }

                Spacer(minLength: 12)

                Button {
                    transition(to: .continueChoice)
                } label: {
                    Text("Terminer")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .controlSize(.large)
            }
            .padding()
        }
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Ecran "Continuer l'echauffement ?"

    private var continueScreen: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 12)

            Text("Continuer l'échauffement ?")
                .font(.title3.weight(.semibold))

            VStack(spacing: 16) {
                WarmupOptionCard(title: "Refaire du cardio", subtitle: nil, systemImage: "figure.run") {
                    transition(to: .cardioDuration)
                }
                WarmupOptionCard(title: "Échauffement libre", subtitle: nil, systemImage: "figure.flexibility") {
                    transition(to: .free(startedAt: .now))
                }
            }
            .padding(.horizontal)

            Spacer()

            Button {
                state.finishWarmup()
            } label: {
                Text("Commencer la séance")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .controlSize(.large)
            .padding()
        }
    }

    // MARK: - Reprise apres kill+resume

    // Reconstruit checkedRamps depuis les series deja persistees : necessaire
    // apres un kill+resume en pleine echauffement, sinon ce @State frais
    // repart a vide (toutes les cases redeviennent decochees) alors que
    // logWarmupSet a deja loggee ces paliers - source de doublons a la
    // reprise si on retapait sur une case deja validee.
    private func restoreCheckedRamps() {
        guard let target = state.warmupTargetExercise(),
              let targetIndex = state.exercises.firstIndex(where: { $0.id == target.id }) else { return }
        let loggedRampIndexes = state.loggedSets
            .filter { $0.isWarmup && $0.orderIndex == targetIndex }
            .map(\.setIndex)
        checkedRamps = Set(loggedRampIndexes)
    }

    private func transition(to newStep: Step) {
        step = newStep
        persistStep()
    }

    private func persistStep() {
        var runtime = WarmupRuntimeState(cardioMinutes: cardioMinutesChoice)
        switch step {
        case .choice:
            runtime.stepRaw = "choice"
        case .cardioDuration:
            runtime.stepRaw = "cardioDuration"
        case .cardioCountdown(let endDate, let minutes):
            runtime.stepRaw = "cardioCountdown"
            runtime.endDate = endDate
            runtime.cardioMinutes = minutes
        case .free(let startedAt):
            runtime.stepRaw = "free"
            runtime.startedAt = startedAt
        case .continueChoice:
            runtime.stepRaw = "continueChoice"
        }
        state.updateWarmupRuntime(runtime)
    }

    private static func step(from runtime: WarmupRuntimeState) -> Step {
        switch runtime.stepRaw {
        case "cardioDuration": return .cardioDuration
        case "cardioCountdown":
            guard let endDate = runtime.endDate else { return .cardioDuration }
            return .cardioCountdown(endDate: endDate, minutes: runtime.cardioMinutes)
        case "free": return .free(startedAt: runtime.startedAt ?? .now)
        case "continueChoice": return .continueChoice
        default: return .choice
        }
    }

    private static func formatSeconds(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - Carte d'option (choix / continuation)

private struct WarmupOptionCard: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        // Sans ce label explicite, l'accessibilite combine titre + sous-titre
        // (ex: "Cardio, Chrono minute"), ce qui rend le bouton introuvable
        // par son seul titre pour les tests UI comme pour VoiceOver.
        .accessibilityLabel(title)
    }
}
