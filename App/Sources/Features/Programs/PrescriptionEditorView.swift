import SwiftUI
import SwiftData
import MuscuEngine

// Editeur de prescription pour un exercice d'une seance : format (classique,
// pyramide, intervalles, AMRAP) et parametres associes.
struct PrescriptionEditorView: View {
    @Bindable var exercise: PrescribedExercise

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var repsMode: RepsMode
    @State private var chargeMode: ChargeMode
    @State private var pyramidMaxReps: Int = 10

    private enum RepsMode: String { case fixed, range }
    private enum ChargeMode: String { case free, percent }

    init(exercise: PrescribedExercise) {
        self.exercise = exercise
        _repsMode = State(initialValue: exercise.repsLower == exercise.repsUpper ? .fixed : .range)
        _chargeMode = State(initialValue: exercise.percentOneRepMax != nil ? .percent : .free)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Format", selection: $exercise.format) {
                        Text("Classique").tag(SetFormat.classic)
                        Text("Pyramide").tag(SetFormat.pyramid)
                        Text("Intervalles").tag(SetFormat.intervals)
                        Text("AMRAP").tag(SetFormat.amrap)
                    }
                    .pickerStyle(.segmented)
                }

                switch exercise.format {
                case .classic:
                    classicSection
                case .pyramid:
                    pyramidSection
                case .intervals:
                    intervalsSection
                case .amrap:
                    amrapSection
                }

                Section("Notes") {
                    TextField("Notes (optionnel)", text: $exercise.notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .onChange(of: exercise.format) { _, newValue in
                applyDefaults(for: newValue)
            }
            .navigationTitle(exercise.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminé") {
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
            .task {
                await prefillPyramidMaxReps()
                applyDefaults(for: exercise.format)
            }
        }
    }

    // MARK: - Classique

    private var classicSection: some View {
        Section("Séries classiques") {
            Stepper("Séries : \(exercise.sets)", value: $exercise.sets, in: 1...10)

            Picker("Mode", selection: $repsMode) {
                Text("Fixe").tag(RepsMode.fixed)
                Text("Fourchette").tag(RepsMode.range)
            }
            .pickerStyle(.segmented)
            .onChange(of: repsMode) { _, newValue in
                if newValue == .fixed {
                    exercise.repsUpper = exercise.repsLower
                }
            }

            if repsMode == .fixed {
                Stepper("Répétitions : \(exercise.repsLower)", value: $exercise.repsLower, in: 1...50)
                    .onChange(of: exercise.repsLower) { _, newValue in
                        exercise.repsUpper = newValue
                    }
            } else {
                Stepper("Reps mini : \(exercise.repsLower)", value: $exercise.repsLower, in: 1...max(1, exercise.repsUpper))
                Stepper("Reps maxi : \(exercise.repsUpper)", value: $exercise.repsUpper, in: max(1, exercise.repsLower)...50)
            }

            Picker("Repos", selection: $exercise.restSeconds) {
                ForEach(Array(stride(from: 15, through: 300, by: 15)), id: \.self) { seconds in
                    Text(Self.formatDuration(seconds)).tag(seconds)
                }
            }

            Picker("Charge", selection: $chargeMode) {
                Text("Libre").tag(ChargeMode.free)
                Text("%1RM").tag(ChargeMode.percent)
            }
            .pickerStyle(.segmented)
            .onChange(of: chargeMode) { _, newValue in
                exercise.percentOneRepMax = newValue == .percent ? (exercise.percentOneRepMax ?? 75) : nil
            }

            if chargeMode == .percent {
                VStack(alignment: .leading) {
                    Text("\(Int(exercise.percentOneRepMax ?? 75)) %")
                        .foregroundStyle(.secondary)
                    Slider(
                        value: Binding(
                            get: { exercise.percentOneRepMax ?? 75 },
                            set: { exercise.percentOneRepMax = $0 }
                        ),
                        in: 40...95,
                        step: 5
                    )
                }
            }
        }
    }

    // MARK: - Pyramide

    private var pyramidSection: some View {
        Section("Pyramide") {
            Stepper("Max de reps : \(pyramidMaxReps)", value: $pyramidMaxReps, in: 1...50)

            ForEach(Pyramid.proposals(maxReps: pyramidMaxReps), id: \.name) { proposal in
                Button {
                    exercise.pyramidReps = proposal.reps
                } label: {
                    PyramidProposalCard(
                        proposal: proposal,
                        isSelected: exercise.pyramidReps == proposal.reps,
                        maxReps: pyramidMaxReps,
                        minRest: exercise.pyramidMinRest,
                        maxRest: exercise.pyramidMaxRest
                    )
                }
                .buttonStyle(.plain)
            }

            Stepper("Repos mini : \(exercise.pyramidMinRest) s", value: $exercise.pyramidMinRest, in: 30...max(30, exercise.pyramidMaxRest), step: 15)
            Stepper("Repos maxi : \(exercise.pyramidMaxRest) s", value: $exercise.pyramidMaxRest, in: max(30, exercise.pyramidMinRest)...300, step: 15)
        }
    }

    // MARK: - Intervalles

    private var intervalsSection: some View {
        Section("Intervalles") {
            HStack {
                Button("30-30") {
                    exercise.intervalWork = 30
                    exercise.intervalRest = 30
                    if exercise.intervalRounds == 0 { exercise.intervalRounds = 8 }
                }
                Spacer()
                Button("Tabata") {
                    exercise.intervalWork = 20
                    exercise.intervalRest = 10
                    exercise.intervalRounds = 8
                }
                Spacer()
                Button("EMOM") {
                    exercise.intervalWork = 60
                    exercise.intervalRest = 0
                    if exercise.intervalRounds == 0 { exercise.intervalRounds = 10 }
                }
            }
            .buttonStyle(.bordered)

            Stepper("Effort : \(exercise.intervalWork) s", value: $exercise.intervalWork, in: 10...120, step: 5)
            Stepper("Repos : \(exercise.intervalRest) s", value: $exercise.intervalRest, in: 0...120, step: 5)
            Stepper("Rounds : \(exercise.intervalRounds)", value: $exercise.intervalRounds, in: 1...30)

            let plan = IntervalPlan(workSeconds: exercise.intervalWork, restSeconds: exercise.intervalRest, rounds: exercise.intervalRounds)
            LabeledContent("Durée totale", value: Self.formatDuration(plan.totalDuration))
        }
    }

    // MARK: - AMRAP

    private var amrapSection: some View {
        Section("AMRAP") {
            Stepper("Durée : \(Self.formatDuration(exercise.amrapSeconds))", value: $exercise.amrapSeconds, in: 30...600, step: 30)
        }
    }

    // Initialise des valeurs par defaut sures pour eviter des plages vides
    // (steppers/pickers avec bornes invalides) quand on bascule de format ou
    // qu'on ouvre l'editeur sur un exercice tout juste cree.
    private func applyDefaults(for format: SetFormat) {
        let defaultRest = UserDefaults.standard.object(forKey: "defaultRestSeconds") != nil ? UserDefaults.standard.integer(forKey: "defaultRestSeconds") : 90
        switch format {
        case .classic:
            if exercise.sets == 0 { exercise.sets = 3 }
            if exercise.repsLower == 0 { exercise.repsLower = 8 }
            if exercise.repsUpper == 0 { exercise.repsUpper = exercise.repsLower }
            if exercise.restSeconds == 0 { exercise.restSeconds = defaultRest }
        case .pyramid:
            if exercise.pyramidMinRest == 0 { exercise.pyramidMinRest = 30 }
            if exercise.pyramidMaxRest == 0 { exercise.pyramidMaxRest = 180 }
            if exercise.pyramidReps.isEmpty {
                exercise.pyramidReps = Pyramid.proposals(maxReps: pyramidMaxReps).first?.reps ?? []
            }
        case .intervals:
            if exercise.intervalWork == 0 { exercise.intervalWork = 30 }
            if exercise.intervalRounds == 0 { exercise.intervalRounds = 8 }
        case .amrap:
            if exercise.amrapSeconds == 0 { exercise.amrapSeconds = 60 }
        }
    }

    private func prefillPyramidMaxReps() async {
        let exerciseId = exercise.exerciseId
        let descriptor = FetchDescriptor<ExerciseRecord>(predicate: #Predicate { $0.exerciseId == exerciseId })
        if let record = try? modelContext.fetch(descriptor).first, let maxReps = record.maxReps {
            pyramidMaxReps = maxReps
        }
    }

    private static func formatDuration(_ seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds) s"
        }
        let minutes = seconds / 60
        let remainder = seconds % 60
        return remainder == 0 ? "\(minutes) min" : "\(minutes) min \(remainder) s"
    }
}

private struct PyramidProposalCard: View {
    let proposal: PyramidProposal
    let isSelected: Bool
    let maxReps: Int
    let minRest: Int
    let maxRest: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(proposal.name)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.accent)
                }
            }
            Text(proposal.reps.map(String.init).joined(separator: "-"))
                .font(.body)
            Text("Volume total : \(proposal.totalVolume) reps")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Repos : " + restsPreview.joined(separator: " - "))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Theme.accent.opacity(0.15) : Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var restsPreview: [String] {
        proposal.reps.dropLast().map { repsDone in
            "\(Pyramid.adaptiveRest(repsDone: repsDone, maxReps: maxReps, minRest: minRest, maxRest: maxRest)) s"
        }
    }
}

#Preview {
    let exercise = PrescribedExercise(exerciseId: "preview", displayName: "Développé couché", orderIndex: 0, sets: 4, repsLower: 8, repsUpper: 12, restSeconds: 90)
    return PrescriptionEditorView(exercise: exercise)
        .modelContainer(for: ExerciseRecord.self, inMemory: true)
        .preferredColorScheme(.dark)
}
