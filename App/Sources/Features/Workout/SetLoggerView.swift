import SwiftUI

// Saisie d'une serie : poids et reps directement editables (TextField), avec
// les steppers +/- gardes autour pour l'ajustement rapide. Vue "sans
// memoire" : le parent doit lui donner une identite stable (.id(...)) qui
// change a chaque nouvelle serie/exercice pour que les valeurs pre-remplies
// soient reinitialisees correctement.
struct SetLoggerView: View {
    let initialWeight: Double
    let initialReps: Int
    let onValidate: (Double, Int) -> Void

    @State private var weight: Double
    @State private var reps: Int
    @FocusState private var focusedField: Field?

    private enum Field {
        case weight, reps
    }

    init(initialWeight: Double, initialReps: Int, onValidate: @escaping (Double, Int) -> Void) {
        self.initialWeight = initialWeight
        self.initialReps = initialReps
        self.onValidate = onValidate
        _weight = State(initialValue: initialWeight)
        _reps = State(initialValue: initialReps)
    }

    var body: some View {
        VStack(spacing: 24) {
            editableValue(
                label: "Poids",
                suffix: "kg",
                onDecrement: { weight = max(0, weight - 2.5) },
                onIncrement: { weight += 2.5 }
            ) {
                TextField(
                    "Poids",
                    value: $weight,
                    format: .number.precision(.fractionLength(0...1))
                )
                .keyboardType(.decimalPad)
                .focused($focusedField, equals: .weight)
            }

            editableValue(
                label: "Répétitions",
                suffix: nil,
                onDecrement: { reps = max(0, reps - 1) },
                onIncrement: { reps += 1 }
            ) {
                TextField("Répétitions", value: $reps, format: .number)
                    .keyboardType(.numberPad)
                    .focused($focusedField, equals: .reps)
            }

            Button {
                focusedField = nil
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
        .toolbar {
            // Les claviers decimalPad/numberPad n'ont pas de touche retour :
            // sans ce bouton "OK", rien ne permet de refermer le clavier une
            // fois la saisie terminee.
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("OK") { focusedField = nil }
            }
        }
    }

    private func editableValue(
        label: String,
        suffix: String?,
        onDecrement: @escaping () -> Void,
        onIncrement: @escaping () -> Void,
        @ViewBuilder field: () -> some View
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

                HStack(spacing: 4) {
                    field()
                        .font(.system(size: 34, weight: .bold))
                        .monospacedDigit()
                        .multilineTextAlignment(.center)
                        .frame(minWidth: 80)
                    if let suffix {
                        Text(suffix)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
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
