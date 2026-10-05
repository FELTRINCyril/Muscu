import SwiftUI
import SwiftData
import MuscuEngine

// Editeur de prescription pour un exercice d'une seance : format et
// parametres associes.
//
// Les options essentielles sont visibles d'emblee ; tempo, RPE/RIR, type de
// charge et convention unilaterale vivent dans une section « Avancé »
// repliee, pour ne pas surcharger l'ecran (cf. roadmap 02).
struct PrescriptionEditorView: View {
    @Bindable var exercise: PrescribedExercise

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.massUnit) private var massUnit
    @Environment(CatalogStore.self) private var catalogStore

    @State private var repsMode: RepsMode
    @State private var chargeMode: ChargeMode
    @State private var pyramidMaxReps: Int = 10
    /// Duree proposee pour « Appliquer à tous les paliers ».
    @State private var pyramidBulkRest: Int = 90

    private enum RepsMode: String { case fixed, range }
    private enum ChargeMode: String { case free, percent, percentMaxReps }

    init(exercise: PrescribedExercise) {
        self.exercise = exercise
        _repsMode = State(initialValue: exercise.repsLower == exercise.repsUpper ? .fixed : .range)
        if exercise.percentMaxReps != nil {
            _chargeMode = State(initialValue: .percentMaxReps)
        } else if exercise.percentOneRepMax != nil {
            _chargeMode = State(initialValue: .percent)
        } else {
            _chargeMode = State(initialValue: .free)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // Liste poussée plutôt que menu déroulant : avec neuf
                    // formats, un menu ancré sur la ligne peut dépasser
                    // l'écran et rendre ses dernières options inatteignables.
                    Picker("Format", selection: $exercise.format) {
                        ForEach(SetFormat.allCases, id: \.self) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    .accessibilityIdentifier("prescription.formatPicker")
                }

                switch exercise.format {
                case .classic:
                    classicSection
                case .pyramid:
                    pyramidSection
                case .dropset:
                    classicSection
                    dropsetSection
                case .restPause:
                    classicSection
                    restPauseSection
                case .myoReps:
                    classicSection
                    myoRepsSection
                case .intervals:
                    intervalsSection
                case .emom:
                    emomSection
                case .amrap:
                    amrapSection
                case .forTime:
                    forTimeSection
                }

                advancedSection

                Section("Notes") {
                    TextField("Notes (optionnel)", text: $exercise.notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .onChange(of: exercise.format) { _, newValue in
                // Une mesure en temps ou en distance n'existe qu'en format
                // classique : on ne la laisse pas cachee derriere un autre.
                if newValue != .classic, exercise.measure != .weightReps {
                    exercise.measure = .weightReps
                }
                applyDefaults(for: newValue)
            }
            .navigationTitle(exercise.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminé") {
                        _ = PersistenceSupport.save(modelContext, action: "Modification de la prescription")
                        dismiss()
                    }
                    // Une pyramide sans palier ne se deroulerait pas : on
                    // refuse de la valider plutot que d'inventer un palier.
                    .disabled(exercise.format == .pyramid && exercise.pyramidReps.isEmpty)
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

            // Ce que mesure l'exercice. Seul le format classique en porte
            // une autre que poids x repetitions.
            if exercise.format == .classic {
                Picker("Mesure", selection: Binding(
                    get: { exercise.measure },
                    set: { newValue in
                        exercise.measure = newValue
                        if newValue != .weightReps {
                            // Pourcentages de 1RM / de max sans objet ici.
                            chargeMode = .free
                        }
                    }
                )) {
                    ForEach(SetMeasure.allCases, id: \.self) { measure in
                        Text(measure.displayName).tag(measure)
                    }
                }
                .accessibilityIdentifier("prescription.measurePicker")
            }

            if exercise.format == .classic, exercise.measure != .weightReps {
                measuredTargets
            } else {
                repsAndChargeRows
            }
        }
    }

    /// Cibles d'une serie au temps et / ou a la distance, plus la charge
    /// facultative (lest, portage). Le repos reste celui d'une serie.
    @ViewBuilder
    private var measuredTargets: some View {
        if exercise.measure.measuresDuration {
            Stepper(
                "Durée visée : \(Self.formatDuration(exercise.targetDurationSeconds))",
                value: $exercise.targetDurationSeconds,
                in: 5...3_600,
                step: exercise.targetDurationSeconds >= 120 ? 30 : 5
            )
            .accessibilityIdentifier("prescription.targetDuration")
        }
        if exercise.measure.measuresDistance {
            Stepper(
                "Distance visée : \(MeasureFormatter.distance(meters: exercise.targetDistanceMeters))",
                value: $exercise.targetDistanceMeters,
                in: 10...100_000,
                step: exercise.targetDistanceMeters >= 1_000 ? 100 : 10
            )
            .accessibilityIdentifier("prescription.targetDistance")
        }
        restPicker
        targetWeightField
    }

    private var restPicker: some View {
        Picker("Repos", selection: $exercise.restSeconds) {
            ForEach(Array(stride(from: 15, through: 300, by: 15)), id: \.self) { seconds in
                Text(Self.formatDuration(seconds)).tag(seconds)
            }
        }
    }

    @ViewBuilder
    private var repsAndChargeRows: some View {
        Group {
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

            restPicker

            Picker("Charge", selection: $chargeMode) {
                Text("Libre").tag(ChargeMode.free)
                Text("% 1RM").tag(ChargeMode.percent)
                Text("% Max reps").tag(ChargeMode.percentMaxReps)
            }
            .pickerStyle(.segmented)
            .onChange(of: chargeMode) { _, newValue in
                exercise.percentOneRepMax = newValue == .percent ? (exercise.percentOneRepMax ?? 75) : nil
                exercise.percentMaxReps = newValue == .percentMaxReps ? (exercise.percentMaxReps ?? 75) : nil
                if newValue != .free { exercise.targetWeight = nil }
            }

            if chargeMode == .free {
                targetWeightField
            } else if chargeMode == .percent {
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
            } else if chargeMode == .percentMaxReps {
                VStack(alignment: .leading) {
                    Text("\(Int(exercise.percentMaxReps ?? 75)) %")
                        .foregroundStyle(.secondary)
                    Slider(
                        value: Binding(
                            get: { exercise.percentMaxReps ?? 75 },
                            set: { exercise.percentMaxReps = $0 }
                        ),
                        in: 40...95,
                        step: 5
                    )
                }
            }
        }
    }

    // Poids cible (optionnel) en mode de charge Libre : prefill prioritaire
    // dans le runner (cf. WorkoutState.suggestedWeight utilise cote runner,
    // et PrescribedExercise.targetWeight). TextField + steppers, meme motif
    // que SetLoggerView (UX5).
    @ViewBuilder
    private var targetWeightField: some View {
        if let weight = exercise.targetWeight {
            HStack(spacing: 12) {
                Text("Poids cible")
                Spacer()
                Button {
                    exercise.targetWeight = LoadStep.stepped(weight, by: massUnit.defaultIncrementKilograms, up: false)
                } label: {
                    Image(systemName: "minus.circle")
                }
                // Saisie dans l'unite du profil, stockage en kg.
                TextField(
                    "Poids",
                    value: Binding(
                        get: { massUnit.fromKilograms(exercise.targetWeight ?? 0) },
                        set: { exercise.targetWeight = massUnit.toKilograms($0) }
                    ),
                    format: .number.precision(.fractionLength(0...1))
                )
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .frame(width: 60)
                Text(massUnit.symbol)
                    .foregroundStyle(.secondary)
                Button {
                    exercise.targetWeight = LoadStep.stepped(weight, by: massUnit.defaultIncrementKilograms, up: true)
                } label: {
                    Image(systemName: "plus.circle")
                }
                Button {
                    exercise.targetWeight = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Button("Poids cible (optionnel)") {
                exercise.targetWeight = 20
            }
        }
    }

    // MARK: - Pyramide

    private var pyramidSection: some View {
        Group {
            Section {
                // Ne sert qu'a dimensionner les modeles proposes : le repos
                // adaptatif, lui, se cale sur le palier le plus haut de la
                // pyramide (Pyramid.referenceMaxReps).
                Stepper("Max de reps : \(pyramidMaxReps)", value: $pyramidMaxReps, in: 1...50)

                ForEach(Pyramid.proposals(maxReps: pyramidMaxReps), id: \.name) { proposal in
                    Button {
                        editPyramid { $0.replaceSteps(proposal.reps, minRest: exercise.pyramidMinRest, maxRest: exercise.pyramidMaxRest) }
                    } label: {
                        PyramidProposalCard(
                            proposal: proposal,
                            isSelected: exercise.pyramidReps == proposal.reps,
                            minRest: exercise.pyramidMinRest,
                            maxRest: exercise.pyramidMaxRest
                        )
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Pyramide")
            } footer: {
                Text("Les modèles sont un point de départ : chaque palier se modifie ci-dessous.")
            }

            pyramidRestModeSection

            pyramidStepsSection
        }
    }

    /// Repos adaptatif (bornes mini/maxi) ou choisi palier par palier.
    private var pyramidRestModeSection: some View {
        Section {
            Picker("Repos", selection: pyramidRestModeBinding) {
                Text("Adaptatif").tag(false)
                Text("Par palier").tag(true)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("pyramid.restMode")

            if exercise.pyramidRestSeconds.isEmpty {
                Stepper("Repos mini : \(exercise.pyramidMinRest) s", value: $exercise.pyramidMinRest, in: 30...max(30, exercise.pyramidMaxRest), step: 15)
                Stepper("Repos maxi : \(exercise.pyramidMaxRest) s", value: $exercise.pyramidMaxRest, in: max(30, exercise.pyramidMinRest)...300, step: 15)
            } else if exercise.pyramidReps.count > 1 {
                PyramidRestStepper(title: String(localized: "Durée commune"), seconds: $pyramidBulkRest)
                Button("Appliquer à tous les paliers") {
                    editPyramid { $0.setAllRests(pyramidBulkRest) }
                }
                .accessibilityIdentifier("pyramid.applyRestToAll")
            }
        } header: {
            Text("Repos entre les paliers")
        } footer: {
            if exercise.pyramidRestSeconds.isEmpty {
                Text("Le repos s’adapte à chaque palier : plus le palier est proche du plus haut palier de la pyramide, plus il est long. Pas de repos après le dernier palier.")
            } else {
                Text("Réglez le repos sous chaque palier, de 0 à 10 min (pas de 5 s sous la minute, de 15 s au-delà). Pas de repos après le dernier palier.")
            }
        }
    }

    private var pyramidRestModeBinding: Binding<Bool> {
        Binding(
            get: { !exercise.pyramidRestSeconds.isEmpty },
            set: { perStep in
                editPyramid { steps in
                    if perStep {
                        steps.usePerStepRest(minRest: exercise.pyramidMinRest, maxRest: exercise.pyramidMaxRest)
                    } else {
                        steps.useAdaptiveRest()
                    }
                }
                if perStep, let first = exercise.pyramidRestSeconds.first {
                    pyramidBulkRest = first
                }
            }
        )
    }

    /// Pyramide libre : n'importe quelle suite de paliers, dans n'importe
    /// quel ordre. Le deroule n'a jamais suppose une forme particuliere — il
    /// lit les paliers un par un — seul l'editeur se limitait aux trois
    /// propositions. En mode « Par palier », chaque palier porte son repos
    /// (sauf le dernier) et l'emporte quand on le deplace.
    private var pyramidStepsSection: some View {
        Section {
            ForEach(Array(exercise.pyramidReps.enumerated()), id: \.offset) { index, reps in
                // Espacement genereux : deux steppers empiles se chevauchent
                // sinon (leur controle est plus haut que leur libelle).
                VStack(alignment: .leading, spacing: 14) {
                    Stepper(
                        "Palier \(index + 1) : \(reps) reps",
                        value: pyramidStepBinding(at: index),
                        in: Pyramid.allowedStepReps
                    )
                    .accessibilityIdentifier("pyramid.step.\(index)")

                    if let rest = pyramidRestLabel(afterStep: index) {
                        if !exercise.pyramidRestSeconds.isEmpty {
                            PyramidRestStepper(
                                title: String(localized: "Repos ensuite"),
                                seconds: pyramidRestBinding(at: index)
                            )
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("pyramid.rest.\(index)")
                        } else {
                            Text("Repos ensuite : \(rest)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .onDelete { offsets in
                editPyramid { $0.removeSteps(atOffsets: offsets) }
            }
            .onMove { source, destination in
                editPyramid { $0.moveSteps(fromOffsets: source, toOffset: destination) }
            }

            if exercise.pyramidReps.count < Pyramid.maximumSteps {
                Button {
                    editPyramid { $0.appendStep(maxReps: pyramidMaxReps, minRest: exercise.pyramidMinRest, maxRest: exercise.pyramidMaxRest) }
                } label: {
                    Label("Ajouter un palier", systemImage: "plus.circle")
                }
                .accessibilityIdentifier("pyramid.addStep")
            }
        } header: {
            HStack {
                Text("Paliers")
                Spacer()
                Text(pyramidShapeLabel)
            }
        } footer: {
            if exercise.pyramidReps.isEmpty {
                Text("Ajoutez au moins un palier.")
                    .foregroundStyle(.red)
            } else {
                Text("\(exercise.pyramidReps.count) séries · \(exercise.pyramidReps.reduce(0, +)) reps au total. Glissez pour supprimer, maintenez pour déplacer.")
            }
        }
    }

    /// Repos prevu apres ce palier, s'il est realise tel que prescrit —
    /// `nil` pour le dernier palier. Meme calcul que le deroule.
    private func pyramidRestLabel(afterStep index: Int) -> String? {
        guard exercise.pyramidReps.indices.contains(index) else { return nil }
        let rest = Pyramid.restAfterStep(
            at: index,
            repsDone: exercise.pyramidReps[index],
            steps: exercise.pyramidReps,
            stepRests: exercise.pyramidRestSeconds,
            minRest: exercise.pyramidMinRest,
            maxRest: exercise.pyramidMaxRest
        )
        return rest.map(PyramidRestStepper.format)
    }

    /// Paliers et repos modifies ENSEMBLE, pour qu'ils restent alignes.
    private func editPyramid(_ change: (inout PyramidSteps) -> Void) {
        var steps = PyramidSteps(reps: exercise.pyramidReps, restSeconds: exercise.pyramidRestSeconds)
        change(&steps)
        if exercise.pyramidReps != steps.reps { exercise.pyramidReps = steps.reps }
        if exercise.pyramidRestSeconds != steps.restSeconds { exercise.pyramidRestSeconds = steps.restSeconds }
    }

    private func pyramidRestBinding(at index: Int) -> Binding<Int> {
        Binding(
            get: { exercise.pyramidRestSeconds.indices.contains(index) ? exercise.pyramidRestSeconds[index] : 0 },
            set: { newValue in editPyramid { $0.setRest(newValue, at: index) } }
        )
    }

    private var pyramidShapeLabel: String {
        if let proposal = Pyramid.matchingProposal(for: exercise.pyramidReps, maxReps: pyramidMaxReps) {
            return proposal.name
        }
        return String(localized: "Personnalisée")
    }

    private func pyramidStepBinding(at index: Int) -> Binding<Int> {
        Binding(
            get: { exercise.pyramidReps.indices.contains(index) ? exercise.pyramidReps[index] : 1 },
            set: { newValue in
                editPyramid { $0.setReps(newValue, at: index) }
            }
        )
    }

    // MARK: - Intervalles

    private var intervalsSection: some View {
        // Plus de raccourci « EMOM » ici : l'EMOM est un format a part
        // entiere, avec son propre ecran et ses propres records. Le simuler
        // avec un repos nul enregistrerait les series comme des intervalles,
        // donc dans une categorie de records differente.
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

    // MARK: - EMOM

    private var emomSection: some View {
        Section {
            Stepper("Minutes : \(exercise.intervalRounds)", value: $exercise.intervalRounds, in: 1...60)
            Stepper(
                "Durée d'une minute : \(Self.formatDuration(exercise.intervalWork))",
                value: $exercise.intervalWork,
                in: 30...300,
                step: 30
            )
            LabeledContent("Durée totale", value: Self.formatDuration(exercise.intervalRounds * max(1, exercise.intervalWork)))
        } header: {
            Text("EMOM")
        } footer: {
            Text("Une série au début de chaque intervalle ; le temps restant sert de récupération.")
        }
    }

    // MARK: - For Time

    private var forTimeSection: some View {
        Section {
            Stepper("Tours à réaliser : \(exercise.sets)", value: $exercise.sets, in: 1...50)
            Stepper("Répétitions par tour : \(exercise.repsLower)", value: $exercise.repsLower, in: 1...100)
                .onChange(of: exercise.repsLower) { _, newValue in
                    // repsUpper doit rester >= repsLower (contrainte validee
                    // a l'import) : sur ce format les deux sont identiques.
                    exercise.repsUpper = newValue
                }
            Toggle("Plafond de temps", isOn: Binding(
                get: { exercise.forTimeCapSeconds > 0 },
                set: { exercise.forTimeCapSeconds = $0 ? 600 : 0 }
            ))
            if exercise.forTimeCapSeconds > 0 {
                Stepper(
                    "Plafond : \(Self.formatDuration(exercise.forTimeCapSeconds))",
                    value: $exercise.forTimeCapSeconds,
                    in: 60...3_600,
                    step: 60
                )
            }
        } header: {
            Text("For Time")
        } footer: {
            Text("Le travail est fixe : c'est le temps mis pour le terminer qui est mesuré.")
        }
    }

    // MARK: - Dropset

    /// Baisse d'un palier : pourcentage tel quel, charge (stockee en kg)
    /// dans l'unite du profil.
    private func dropLabel(_ drop: Double) -> String {
        exercise.dropsetUsesPercent
            ? String(format: "%g", drop) + " %"
            : WeightFormatter.string(kilograms: drop, unit: massUnit)
    }

    private var dropsetSection: some View {
        Section {
            Picker("Unité des paliers", selection: $exercise.dropsetUsesPercent) {
                Text("Pourcentage").tag(true)
                Text(massUnit == .kilograms ? "Kilogrammes" : "Livres").tag(false)
            }
            .pickerStyle(.segmented)

            Stepper("Paliers : \(exercise.dropsetDrops.count)", value: dropCountBinding, in: 1...5)

            ForEach(Array(exercise.dropsetDrops.enumerated()), id: \.offset) { index, drop in
                Stepper(
                    "Palier \(index + 1) : -\(dropLabel(drop))",
                    value: dropBinding(at: index),
                    in: exercise.dropsetUsesPercent ? 5...80 : massUnit.defaultIncrementKilograms...100,
                    step: exercise.dropsetUsesPercent ? 5 : massUnit.defaultIncrementKilograms
                )
            }

            Stepper(
                "Repos entre paliers : \(exercise.dropsetRestSeconds == 0 ? "aucun" : "\(exercise.dropsetRestSeconds) s")",
                value: $exercise.dropsetRestSeconds,
                in: 0...120,
                step: 5
            )
        } header: {
            Text("Dropset")
        } footer: {
            Text("Chaque palier part de la charge du palier précédent. Un repos de 0 s est normal sur ce format.")
        }
    }

    // MARK: - Rest-pause

    private var restPauseSection: some View {
        Section {
            Stepper("Mini-séries maximum : \(exercise.restPauseMaxMiniSets)", value: $exercise.restPauseMaxMiniSets, in: 1...10)
            Stepper(
                "Micro-repos : \(exercise.restPauseMicroRestSeconds) s",
                value: $exercise.restPauseMicroRestSeconds,
                in: 5...60,
                step: 5
            )
            Stepper("Seuil d'arrêt : \(exercise.restPauseMinimumReps) reps", value: $exercise.restPauseMinimumReps, in: 0...20)
        } header: {
            Text("Rest-pause")
        } footer: {
            Text("Le bloc s'arrête sous le seuil de répétitions, au nombre maximum de mini-séries, ou sur votre décision.")
        }
    }

    // MARK: - Myo-reps

    private var myoRepsSection: some View {
        Section {
            Stepper("Activation mini : \(exercise.myoRepsActivationLower) reps", value: $exercise.myoRepsActivationLower, in: 1...50)
                .onChange(of: exercise.myoRepsActivationLower) { _, newValue in
                    if exercise.myoRepsActivationUpper < newValue { exercise.myoRepsActivationUpper = newValue }
                }
            Stepper("Activation maxi : \(exercise.myoRepsActivationUpper) reps", value: $exercise.myoRepsActivationUpper, in: 1...60)
                .onChange(of: exercise.myoRepsActivationUpper) { _, newValue in
                    if exercise.myoRepsActivationLower > newValue { exercise.myoRepsActivationLower = newValue }
                }
            Stepper("RIR visé sur l'activation : \(exercise.myoRepsTargetRepsInReserve)", value: $exercise.myoRepsTargetRepsInReserve, in: 0...5)
            Stepper("Répétitions par mini-série : \(exercise.myoRepsMiniSetReps)", value: $exercise.myoRepsMiniSetReps, in: 1...20)
            Stepper("Mini-séries maximum : \(exercise.myoRepsMaxMiniSets)", value: $exercise.myoRepsMaxMiniSets, in: 1...15)
            Stepper("Repos : \(exercise.myoRepsRestSeconds) s", value: $exercise.myoRepsRestSeconds, in: 5...60, step: 5)
        } header: {
            Text("Myo-reps")
        } footer: {
            Text("Le bloc s'arrête quand une mini-série n'atteint plus la cible, au maximum configuré, ou sur votre décision.")
        }
    }

    // MARK: - Avancé

    private var advancedSection: some View {
        Section {
            DisclosureGroup("Options avancées") {
                Picker("Type de charge", selection: loadKindBinding) {
                    Text("Automatique").tag("")
                    Text("Charge externe").tag(LoadKind.external.rawValue)
                    Text("Poids du corps").tag(LoadKind.bodyweight.rawValue)
                    Text("Lesté").tag(LoadKind.weighted.rawValue)
                    Text("Assisté").tag(LoadKind.assisted.rawValue)
                }

                Picker("Saisie unilatérale", selection: Binding(
                    get: { exercise.sideConvention },
                    set: { exercise.sideConvention = $0 }
                )) {
                    Text("Bilatéral").tag(SideConvention.bilateral)
                    Text("Par côté").tag(SideConvention.perSide)
                    Text("Les deux côtés cumulés").tag(SideConvention.combined)
                }

                TextField("Tempo (ex. 3-1-1-0)", text: $exercise.tempoNotation)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("prescription.tempoField")
                if !exercise.tempoNotation.isEmpty, exercise.tempo == nil {
                    Text("Format attendu : quatre chiffres séparés par des tirets, par exemple 3-1-1-0.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Toggle("Effort cible (RIR)", isOn: targetEffortEnabledBinding)
                if let rir = exercise.targetEffort?.repsInReserve {
                    Stepper("RIR visé : \(rir)", value: targetEffortBinding, in: 0...5)
                }
            }
        } footer: {
            Text("Ces réglages sont facultatifs. « Automatique » déduit le type de charge du catalogue.")
        }
    }

    // MARK: - Liaisons avancées

    private var loadKindBinding: Binding<String> {
        Binding(
            get: { exercise.loadKindRaw },
            set: { exercise.loadKindRaw = $0 }
        )
    }

    private var targetEffortEnabledBinding: Binding<Bool> {
        Binding(
            get: { exercise.targetEffort != nil },
            set: { exercise.targetEffort = $0 ? .rir(2) : nil }
        )
    }

    private var targetEffortBinding: Binding<Int> {
        Binding(
            get: { exercise.targetEffort?.repsInReserve ?? 2 },
            set: { exercise.targetEffort = .rir($0) }
        )
    }

    private var dropCountBinding: Binding<Int> {
        Binding(
            get: { exercise.dropsetDrops.count },
            set: { newCount in
                var drops = exercise.dropsetDrops
                let defaultDrop: Double = exercise.dropsetUsesPercent ? 20 : 5
                while drops.count < newCount { drops.append(defaultDrop) }
                while drops.count > newCount, !drops.isEmpty { drops.removeLast() }
                exercise.dropsetDrops = drops
            }
        )
    }

    private func dropBinding(at index: Int) -> Binding<Double> {
        Binding(
            get: { index < exercise.dropsetDrops.count ? exercise.dropsetDrops[index] : 0 },
            set: { newValue in
                guard index < exercise.dropsetDrops.count else { return }
                var drops = exercise.dropsetDrops
                drops[index] = newValue
                exercise.dropsetDrops = drops
            }
        )
    }

    // Initialise des valeurs par defaut sures pour eviter des plages vides
    // (steppers/pickers avec bornes invalides) quand on bascule de format ou
    // qu'on ouvre l'editeur sur un exercice tout juste cree.
    private func applyDefaults(for format: SetFormat) {
        let defaultRest = WorkoutPlanBuilder.defaultRestSeconds(
            forExerciseId: exercise.exerciseId,
            catalogStore: catalogStore,
            context: modelContext
        )
        switch format {
        case .classic:
            applyClassicDefaults(defaultRest: defaultRest)
        case .pyramid:
            if exercise.pyramidMinRest == 0 { exercise.pyramidMinRest = 30 }
            if exercise.pyramidMaxRest == 0 { exercise.pyramidMaxRest = 180 }
            if exercise.pyramidReps.isEmpty {
                exercise.pyramidReps = Pyramid.proposals(maxReps: pyramidMaxReps).first?.reps ?? []
            }
        case .dropset:
            applyClassicDefaults(defaultRest: defaultRest)
            if exercise.dropsetDrops.isEmpty {
                exercise.dropsetDrops = exercise.dropsetUsesPercent ? [20, 20] : [5, 5]
            }
        case .restPause:
            applyClassicDefaults(defaultRest: defaultRest)
            if exercise.restPauseMaxMiniSets == 0 { exercise.restPauseMaxMiniSets = 3 }
            if exercise.restPauseMicroRestSeconds == 0 { exercise.restPauseMicroRestSeconds = 15 }
            if exercise.restPauseMinimumReps == 0 { exercise.restPauseMinimumReps = 3 }
        case .myoReps:
            applyClassicDefaults(defaultRest: defaultRest)
            if exercise.myoRepsActivationLower == 0 { exercise.myoRepsActivationLower = 12 }
            if exercise.myoRepsActivationUpper < exercise.myoRepsActivationLower {
                exercise.myoRepsActivationUpper = exercise.myoRepsActivationLower + 3
            }
            if exercise.myoRepsMiniSetReps == 0 { exercise.myoRepsMiniSetReps = 5 }
            if exercise.myoRepsMaxMiniSets == 0 { exercise.myoRepsMaxMiniSets = 5 }
            if exercise.myoRepsRestSeconds == 0 { exercise.myoRepsRestSeconds = 20 }
        case .intervals:
            if exercise.intervalWork == 0 { exercise.intervalWork = 30 }
            if exercise.intervalRest == 0 { exercise.intervalRest = 30 }
            if exercise.intervalRounds == 0 { exercise.intervalRounds = 8 }
        case .emom:
            if exercise.intervalWork < 30 { exercise.intervalWork = 60 }
            if exercise.intervalRounds == 0 { exercise.intervalRounds = 10 }
            // Un EMOM n'a pas de repos propre : le temps restant dans la
            // minute EST la recuperation.
            exercise.intervalRest = 0
        case .amrap:
            if exercise.amrapSeconds == 0 { exercise.amrapSeconds = 60 }
        case .forTime:
            if exercise.sets == 0 { exercise.sets = 5 }
            if exercise.repsLower == 0 { exercise.repsLower = 10 }
            exercise.repsUpper = max(exercise.repsLower, exercise.repsUpper)
        }
    }

    private func applyClassicDefaults(defaultRest: Int) {
        if exercise.sets == 0 { exercise.sets = 3 }
        if exercise.repsLower == 0 { exercise.repsLower = 8 }
        if exercise.repsUpper == 0 { exercise.repsUpper = exercise.repsLower }
        if exercise.restSeconds == 0 { exercise.restSeconds = defaultRest }
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

    // Meme calcul que le deroule : ce qui est annonce ici est ce qui sera
    // lance, palier tenu tel que prescrit.
    private var restsPreview: [String] {
        Pyramid.plannedRests(steps: proposal.reps, stepRests: [], minRest: minRest, maxRest: maxRest)
            .map { "\($0) s" }
    }
}

#Preview {
    let exercise = PrescribedExercise(exerciseId: "preview", displayName: "Développé couché", orderIndex: 0, sets: 4, repsLower: 8, repsUpper: 12, restSeconds: 90)
    return PrescriptionEditorView(exercise: exercise)
        .modelContainer(for: ExerciseRecord.self, inMemory: true)
        .preferredColorScheme(.dark)
}

/// Reglage d'un repos de pyramide, de 0 a 10 min : pas de 5 s sous la
/// minute, de 15 s au-dela (Pyramid.increasedRest / decreasedRest).
private struct PyramidRestStepper: View {
    let title: String
    @Binding var seconds: Int

    var body: some View {
        Stepper {
            Text("\(title) : \(Self.format(seconds))")
        } onIncrement: {
            seconds = Pyramid.increasedRest(seconds)
        } onDecrement: {
            seconds = Pyramid.decreasedRest(seconds)
        }
    }

    static func format(_ seconds: Int) -> String {
        guard seconds > 0 else { return String(localized: "aucun") }
        return Duration.seconds(seconds).formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated))
    }
}
