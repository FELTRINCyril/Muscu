import SwiftUI
import MuscuEngine

// Deroule d'un exercice au format pyramide : sequence complete affichee en
// pastilles defilantes (paliers passes/en cours/a venir), palier courant en
// gros avec un nombre de reps ajustable, et le repos EXACT qui suivra la
// validation (meme calcul que la machine a etats : Pyramid.restAfterStep).
//
// Une pyramide peut compter jusqu'a 30 paliers : la sequence defile
// horizontalement et se recentre sur le palier courant, au lieu d'imposer
// sa largeur a tout l'ecran.
struct PyramidRunnerView: View {
    let state: WorkoutState
    let exercise: WorkoutExercisePlan

    var body: some View {
        Group {
            if exercise.pyramidReps.isEmpty {
                emptySequence
            } else {
                sequenceBody
            }
        }
    }

    // Defensif : une pyramide sans paliers ne devrait jamais arriver (la
    // saisie force au moins une proposition), mais on ne bloque jamais la
    // seance si c'est le cas.
    private var emptySequence: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("Aucun palier configuré pour cette pyramide")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Button("Passer cet exercice") {
                state.skipExercise()
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity)
    }

    private var sequenceBody: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 4) {
                    Text(exercise.displayName)
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                    Text("Palier \(currentStepIndex + 1) sur \(exercise.pyramidReps.count)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .accessibilityIdentifier("pyramid.stepCounter")
                }
                .padding(.horizontal)

                PyramidSequenceStrip(reps: exercise.pyramidReps, currentIndex: currentStepIndex)

                PyramidStepControl(
                    targetReps: exercise.pyramidReps[currentStepIndex],
                    isLastStep: currentStepIndex + 1 >= exercise.pyramidReps.count,
                    restAfter: { reps in
                        exercise.pyramidRest(afterStep: currentStepIndex, repsDone: reps)
                    },
                    onValidate: { reps in
                        state.logPyramidStep(reps: reps)
                    }
                )
                .id("\(exercise.id)-\(currentStepIndex)")
                .padding(.horizontal)
            }
            .padding(.vertical)
            // Jamais plus large qu'une colonne lisible, meme sur iPad.
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
    }

    // Palier courant, borne aux paliers reellement configures : la machine
    // a etats reste la seule source de la position.
    private var currentStepIndex: Int {
        guard let target = state.currentTarget, target.exercise.id == exercise.id else { return 0 }
        return min(max(0, target.setNumber - 1), max(0, exercise.pyramidReps.count - 1))
    }
}

// MARK: - Sequence

/// Pastilles des paliers dans un defilement horizontal, recentre sur le
/// palier courant. Les pastilles suivent Dynamic Type.
private struct PyramidSequenceStrip: View {
    let reps: [Int]
    let currentIndex: Int

    @ScaledMetric(relativeTo: .subheadline) private var chipSize: CGFloat = 34

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(reps.enumerated()), id: \.offset) { index, value in
                        ChipView(reps: value, index: index, total: reps.count,
                                 status: status(for: index), size: chipSize)
                            .id(index)
                    }
                }
                .padding(.horizontal)
                // Place pour l'anneau de la pastille courante.
                .padding(.vertical, 4)
            }
            .onAppear { proxy.scrollTo(currentIndex, anchor: .center) }
            .onChange(of: currentIndex) { _, newValue in
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    private func status(for index: Int) -> ChipStatus {
        if index < currentIndex { return .done }
        if index == currentIndex { return .current }
        return .upcoming
    }

    enum ChipStatus { case done, current, upcoming }

    private struct ChipView: View {
        let reps: Int
        let index: Int
        let total: Int
        let status: ChipStatus
        let size: CGFloat

        var body: some View {
            let diameter = status == .current ? size * 1.3 : size
            Text(verbatim: "\(reps)")
                .font(status == .current ? .headline : .subheadline)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(4)
                .foregroundStyle(foreground)
                .frame(width: diameter, height: diameter)
                .background(background)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(status == .current ? Theme.accent : .clear, lineWidth: 2)
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(accessibilityText))
        }

        private var accessibilityText: String {
            switch status {
            case .done:
                return String(localized: "Palier \(index + 1) sur \(total), \(reps) reps, fait")
            case .current:
                return String(localized: "Palier \(index + 1) sur \(total), \(reps) reps, en cours")
            case .upcoming:
                return String(localized: "Palier \(index + 1) sur \(total), \(reps) reps, à venir")
            }
        }

        private var foreground: Color {
            switch status {
            case .done: return .black
            case .current: return Theme.accent
            case .upcoming: return .secondary
            }
        }

        private var background: Color {
            switch status {
            case .done: return Theme.accent
            case .current: return Theme.card
            case .upcoming: return Theme.card.opacity(0.5)
            }
        }
    }
}

// MARK: - Palier courant

// Palier courant : reps geantes, stepper ajustable autour de la cible,
// repos exact qui suivra la validation.
private struct PyramidStepControl: View {
    let targetReps: Int
    let isLastStep: Bool
    /// Repos lance apres ce palier pour un nombre de reps donne (`nil` apres
    /// le dernier palier). Meme fonction que la machine a etats.
    let restAfter: (Int) -> Int?
    let onValidate: (Int) -> Void

    @State private var reps: Int

    init(targetReps: Int, isLastStep: Bool, restAfter: @escaping (Int) -> Int?, onValidate: @escaping (Int) -> Void) {
        self.targetReps = targetReps
        self.isLastStep = isLastStep
        self.restAfter = restAfter
        self.onValidate = onValidate
        _reps = State(initialValue: targetReps)
    }

    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 12) {
                Button {
                    reps = max(Pyramid.allowedStepReps.lowerBound, reps - 1)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .scaledSystemFont(size: 40, relativeTo: .title)
                }
                .disabled(reps <= Pyramid.allowedStepReps.lowerBound)
                .accessibilityLabel(Text("Une répétition de moins"))

                VStack(spacing: 0) {
                    Text(verbatim: "\(reps)")
                        .scaledSystemFont(size: 72, weight: .bold)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                        .contentTransition(.numericText())
                    Text("reps")
                        .font(.headline)
                        // Gris, pas un vert attenue : l'unite ne doit pas
                        // concurrencer le nombre.
                        .foregroundStyle(Color.secondary)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("\(reps) reps"))
                .accessibilityIdentifier("pyramid.reps")

                Button {
                    reps = min(Pyramid.allowedStepReps.upperBound, reps + 1)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .scaledSystemFont(size: 40, relativeTo: .title)
                }
                .disabled(reps >= Pyramid.allowedStepReps.upperBound)
                .accessibilityLabel(Text("Une répétition de plus"))
            }
            .foregroundStyle(Theme.accent)

            if reps != targetReps {
                Text("Objectif du palier : \(targetReps) reps")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            restLine
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("pyramid.restPreview")

            Button {
                onValidate(reps)
            } label: {
                Text("Valider")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .controlSize(.large)
        }
    }

    @ViewBuilder
    private var restLine: some View {
        if isLastStep {
            Text("Dernier palier")
        } else if let seconds = restAfter(reps), seconds > 0 {
            Text("Repos après ce palier : \(Self.formatRest(seconds))")
        } else {
            Text("Pas de repos après ce palier")
        }
    }

    static func formatRest(_ seconds: Int) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated))
    }
}

#Preview {
    ScrollView {
        PyramidStepControl(targetReps: 6, isLastStep: false, restAfter: { _ in 95 }) { _ in }
            .padding()
    }
    .background(Theme.background)
    .preferredColorScheme(.dark)
}
