import SwiftUI
import MuscuEngine

// Saisie d'une serie : poids et reps directement editables (TextField), avec
// les steppers +/- gardes autour pour l'ajustement rapide. Vue "sans
// memoire" : le parent doit lui donner une identite stable (.id(...)) qui
// change a chaque nouvelle serie/exercice pour que les valeurs pre-remplies
// soient reinitialisees correctement.
//
// L'effort ressenti, l'echec musculaire et le commentaire sont facultatifs
// et replies par defaut : ils ne doivent pas ralentir la saisie courante.
struct SetLoggerView: View {
    /// Ce que l'utilisateur a reellement fait sur cette serie.
    struct Result: Equatable {
        var weight: Double
        var reps: Int
        var effort: EffortRating?
        var reachedFailure: Bool
        var notes: String
    }

    let initialWeight: Double
    let initialReps: Int
    let onValidate: (Result) -> Void

    @State private var weight: Double
    @State private var reps: Int
    @State private var repsInReserve: Int?
    @State private var reachedFailure = false
    @State private var notes = ""
    @State private var showingDetails = false
    @FocusState private var focusedField: Field?

    private enum Field {
        case weight, reps, notes
    }

    init(initialWeight: Double, initialReps: Int, onValidate: @escaping (Result) -> Void) {
        self.initialWeight = initialWeight
        self.initialReps = initialReps
        self.onValidate = onValidate
        _weight = State(initialValue: initialWeight)
        _reps = State(initialValue: initialReps)
    }

    /// Forme courte, pour les appelants qui n'ont besoin que du couple
    /// poids/repetitions.
    init(initialWeight: Double, initialReps: Int, onValidate: @escaping (Double, Int) -> Void) {
        self.init(initialWeight: initialWeight, initialReps: initialReps) { result in
            onValidate(result.weight, result.reps)
        }
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

            detailsSection

            Button {
                focusedField = nil
                onValidate(
                    Result(
                        weight: weight,
                        reps: reps,
                        effort: repsInReserve.map { EffortRating.rir($0) },
                        reachedFailure: reachedFailure,
                        notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                )
            } label: {
                Text("Valider la série")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .controlSize(.large)
            .disabled(reps <= 0 || weight < 0 || !weight.isFinite)
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

    // Section repliee : effort ressenti, echec et commentaire. Repliee par
    // defaut pour garder l'ecran de saisie utilisable d'une main entre deux
    // series, conformement a la roadmap (options avancees a part).
    private var detailsSection: some View {
        DisclosureGroup(isExpanded: $showingDetails) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Effort ressenti (RIR)", isOn: Binding(
                    get: { repsInReserve != nil },
                    set: { repsInReserve = $0 ? 2 : nil }
                ))
                .accessibilityIdentifier("setLogger.effortToggle")

                if let value = repsInReserve {
                    Stepper("RIR : \(value)", value: Binding(
                        get: { value },
                        set: { repsInReserve = $0 }
                    ), in: 0...10)
                }

                Toggle("Échec musculaire atteint", isOn: $reachedFailure)
                    .accessibilityIdentifier("setLogger.failureToggle")

                TextField("Commentaire (optionnel)", text: $notes, axis: .vertical)
                    .lineLimit(1...3)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .notes)
                    .accessibilityIdentifier("setLogger.notesField")
            }
            .padding(.top, 4)
        } label: {
            Text("Détails de la série")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("setLogger.detailsDisclosure")
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
    SetLoggerView(initialWeight: 75, initialReps: 10) { (_: Double, _: Int) in }
        .padding()
        .background(Theme.background)
        .preferredColorScheme(.dark)
}
