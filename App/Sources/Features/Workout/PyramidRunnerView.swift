import SwiftUI
import MuscuEngine

// Deroule d'un exercice au format pyramide : sequence complete affichee en
// chips (paliers passes/en cours/a venir), palier courant en gros avec un
// nombre de reps ajustable, apercu du repos adaptatif avant meme de valider.
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
            VStack(spacing: 24) {
                VStack(spacing: 4) {
                    Text(exercise.displayName)
                        .font(.title3.weight(.semibold))
                    Text(exercise.objectiveLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                sequenceChips

                PyramidStepControl(
                    targetReps: exercise.pyramidReps[currentStepIndex],
                    maxReps: state.pyramidMaxReps(for: exercise),
                    minRest: exercise.pyramidMinRest,
                    maxRest: exercise.pyramidMaxRest,
                    isLastStep: currentStepIndex + 1 >= exercise.pyramidReps.count,
                    onValidate: { reps in
                        state.logPyramidStep(reps: reps)
                    }
                )
                .id("\(exercise.id)-\(currentStepIndex)")
            }
            .padding()
        }
    }

    // Palier courant, borne aux paliers reellement configures : la machine
    // a etats reste la seule source de la position.
    private var currentStepIndex: Int {
        guard let target = state.currentTarget, target.exercise.id == exercise.id else { return 0 }
        return min(max(0, target.setNumber - 1), max(0, exercise.pyramidReps.count - 1))
    }

    private var sequenceChips: some View {
        HStack(spacing: 8) {
            ForEach(Array(exercise.pyramidReps.enumerated()), id: \.offset) { index, reps in
                ChipView(reps: reps, status: status(for: index))
            }
        }
    }

    private enum ChipStatus { case done, current, upcoming }

    private func status(for index: Int) -> ChipStatus {
        if index < currentStepIndex { return .done }
        if index == currentStepIndex { return .current }
        return .upcoming
    }

    private struct ChipView: View {
        let reps: Int
        let status: ChipStatus

        var body: some View {
            Text("\(reps)")
                .font(status == .current ? .headline : .subheadline)
                .foregroundStyle(foreground)
                .frame(width: status == .current ? 44 : 34, height: status == .current ? 44 : 34)
                .background(background)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(status == .current ? Theme.accent : .clear, lineWidth: 2)
                )
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

// Palier courant : reps geantes, stepper ajustable +-1 autour de la cible,
// apercu en direct du repos adaptatif qui suivra la validation.
private struct PyramidStepControl: View {
    let targetReps: Int
    let maxReps: Int
    let minRest: Int
    let maxRest: Int
    let isLastStep: Bool
    let onValidate: (Int) -> Void

    @State private var reps: Int

    init(targetReps: Int, maxReps: Int, minRest: Int, maxRest: Int, isLastStep: Bool, onValidate: @escaping (Int) -> Void) {
        self.targetReps = targetReps
        self.maxReps = maxReps
        self.minRest = minRest
        self.maxRest = maxRest
        self.isLastStep = isLastStep
        self.onValidate = onValidate
        _reps = State(initialValue: targetReps)
    }

    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 24) {
                Button {
                    reps = max(0, reps - 1)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 36))
                }

                Text("\(reps) reps")
                    .font(.system(size: 56, weight: .bold))
                    .monospacedDigit()
                    .frame(minWidth: 180)

                Button {
                    reps += 1
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 36))
                }
            }
            .foregroundStyle(Theme.accent)

            if !isLastStep {
                Text("Repos après cette série : ~\(Self.formatRest(computedRest))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

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

    private var computedRest: Int {
        Pyramid.adaptiveRest(repsDone: reps, maxReps: maxReps, minRest: minRest, maxRest: maxRest)
    }

    private static func formatRest(_ seconds: Int) -> String {
        guard seconds >= 60 else { return "\(seconds) s" }
        let minutes = seconds / 60
        let remainder = seconds % 60
        return remainder == 0 ? "\(minutes) min" : "\(minutes) min \(remainder)"
    }
}

#Preview {
    ScrollView {
        PyramidStepControl(targetReps: 6, maxReps: 10, minRest: 30, maxRest: 180, isLastStep: false) { _ in }
            .padding()
    }
    .background(Theme.background)
    .preferredColorScheme(.dark)
}
