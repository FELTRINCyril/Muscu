import SwiftUI
import MuscuEngine

/// Calculateur de 1RM rapide : charge × repetitions -> 1RM estime (formule
/// du moteur) et tableau des pourcentages arrondis au palier chargeable.
///
/// Distinct du test de 1RM guide (`OneRepMaxTestView`) : rien n'est
/// enregistre ici, c'est une simple calculatrice.
struct OneRepMaxCalculatorView: View {
    var title: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.massUnit) private var massUnit

    /// Charge saisie dans l'unite du profil.
    @State private var weightText = ""
    @State private var reps = 5

    private var maximumReps: Int { WorkoutSettings.maximumRepsForOneRepMax }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Charge")
                        Spacer()
                        TextField("Ex : 80", text: $weightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 120)
                            .accessibilityIdentifier("oneRepMaxCalculator.weight")
                        Text(verbatim: massUnit.symbol)
                            .foregroundStyle(.secondary)
                    }
                    Stepper("Répétitions : \(reps)", value: $reps, in: 1...30)
                        .accessibilityIdentifier("oneRepMaxCalculator.reps")
                } header: {
                    Text("Performance")
                }

                Section {
                    if let estimate {
                        LabeledContent("1RM estimé", value: WeightFormatter.string(kilograms: estimate, unit: massUnit))
                            .font(.headline)
                            .accessibilityIdentifier("oneRepMaxCalculator.result")
                    } else if reps > maximumReps {
                        Text("Au-delà de \(maximumReps) répétitions, l’estimation n’est plus fiable (réglage du plafond).")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Saisissez une charge et un nombre de répétitions.")
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Estimation (formule d’Epley), pas une mesure. Pour un vrai maximum, utilisez le test de 1RM guidé.")
                }

                if let estimate {
                    Section {
                        ForEach(OneRepMaxCalculator.table(oneRepMaxKilograms: estimate, stepKilograms: stepKilograms)) { row in
                            HStack {
                                Text(verbatim: "\(row.percent) %")
                                    .monospacedDigit()
                                Spacer()
                                Text(verbatim: WeightFormatter.string(kilograms: row.roundedKilograms, unit: massUnit))
                                    .monospacedDigit()
                                    .fontWeight(.semibold)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    } header: {
                        Text("Pourcentages")
                    } footer: {
                        Text("Arrondis au palier chargeable le plus proche (\(WeightFormatter.number(massUnit.fromKilograms(stepKilograms), maximumFractionDigits: 2)) \(massUnit.symbol)).")
                    }
                }
            }
            .navigationTitle(title ?? String(localized: "Calculateur de 1RM"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
    }

    /// 1RM estime en kg canonique.
    private var estimate: Double? {
        let value = Double(weightText.replacingOccurrences(of: ",", with: "."))
        guard let value, value.isFinite, value > 0 else { return nil }
        return OneRepMaxCalculator.estimate(
            weightKilograms: massUnit.toKilograms(value),
            reps: reps,
            maximumReps: maximumReps
        )
    }

    /// Palier d'arrondi : pas minimal de l'inventaire de disques, sinon le
    /// pas usuel de l'unite.
    private var stepKilograms: Double {
        let inventory = WorkoutSettings.plateInventory(for: massUnit)
        let step = inventory.smallestStep
        return step > 0 ? massUnit.toKilograms(step) : massUnit.defaultIncrementKilograms
    }
}
