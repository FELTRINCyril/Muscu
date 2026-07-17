import SwiftUI

// Saisie d'une serie : poids et reps pre-remplis, gros steppers +/-, gros
// bouton de validation. Vue "sans memoire" : le parent doit lui donner une
// identite stable (.id(...)) qui change a chaque nouvelle serie/exercice
// pour que les valeurs pre-remplies soient reinitialisees correctement.
struct SetLoggerView: View {
    let initialWeight: Double
    let initialReps: Int
    let onValidate: (Double, Int) -> Void

    @State private var weight: Double
    @State private var reps: Int

    init(initialWeight: Double, initialReps: Int, onValidate: @escaping (Double, Int) -> Void) {
        self.initialWeight = initialWeight
        self.initialReps = initialReps
        self.onValidate = onValidate
        _weight = State(initialValue: initialWeight)
        _reps = State(initialValue: initialReps)
    }

    var body: some View {
        VStack(spacing: 24) {
            valueStepper(
                label: "Poids",
                valueText: "\(WorkoutState.formatWeight(weight)) kg",
                onDecrement: { weight = max(0, weight - 2.5) },
                onIncrement: { weight += 2.5 }
            )

            valueStepper(
                label: "Répétitions",
                valueText: "\(reps)",
                onDecrement: { reps = max(0, reps - 1) },
                onIncrement: { reps += 1 }
            )

            Button {
                onValidate(weight, reps)
            } label: {
                Text("Valider la série")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .controlSize(.large)
        }
    }

    private func valueStepper(
        label: String,
        valueText: String,
        onDecrement: @escaping () -> Void,
        onIncrement: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 24) {
                Button(action: onDecrement) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 36))
                }

                Text(valueText)
                    .font(.system(size: 34, weight: .bold))
                    .monospacedDigit()
                    .frame(minWidth: 120)

                Button(action: onIncrement) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 36))
                }
            }
            .foregroundStyle(Theme.accent)
        }
    }
}

#Preview {
    SetLoggerView(initialWeight: 75, initialReps: 10) { _, _ in }
        .padding()
        .background(Theme.background)
        .preferredColorScheme(.dark)
}
