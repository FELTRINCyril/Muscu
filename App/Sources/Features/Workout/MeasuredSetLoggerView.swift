import SwiftUI
import MuscuEngine

// Saisie d'une serie mesuree en temps et / ou en distance (gainage,
// portage, course). Pendant de `SetLoggerView` pour les series sans
// repetitions ; meme contrat : vue « sans memoire », a laquelle le parent
// donne une identite qui change a chaque serie.
//
// Le temps se mesure au chronometre (sans cible) ou au compte a rebours
// (avec cible, prolonge au-dela de zero si l'on tient plus longtemps), ou se
// saisit a la main. Le chrono part d'une date absolue : il reste juste apres
// un passage en arriere-plan.
struct MeasuredSetLoggerView: View {
    struct Result: Equatable {
        var measured: MeasuredSetResult
        /// Lest ou charge portee, en kg. Zero = aucune.
        var weight: Double
        var notes: String
        var role: SetRole
    }

    let measure: SetMeasure
    let targetDurationSeconds: Int?
    let targetDistanceMeters: Double?
    let initialWeight: Double
    let weightStepKilograms: Double
    let onValidate: (Result) -> Void

    @Environment(\.massUnit) private var massUnit

    @State private var durationSeconds: Int
    @State private var distanceMeters: Double
    @State private var weight: Double
    @State private var notes = ""
    @State private var role: SetRole = .working
    @State private var showingDetails = false
    /// Debut du chrono en cours, `nil` a l'arret.
    @State private var runningSince: Date?
    /// Temps deja chronometre avant la derniere reprise.
    @State private var accumulatedSeconds: TimeInterval = 0
    @State private var didSignalTarget = false
    @FocusState private var focusedField: Field?

    private enum Field { case minutes, seconds, distance, weight, notes }

    init(
        measure: SetMeasure,
        targetDurationSeconds: Int?,
        targetDistanceMeters: Double?,
        initialWeight: Double,
        weightStepKilograms: Double,
        onValidate: @escaping (Result) -> Void
    ) {
        self.measure = measure
        self.targetDurationSeconds = targetDurationSeconds
        self.targetDistanceMeters = targetDistanceMeters
        self.initialWeight = initialWeight
        self.weightStepKilograms = weightStepKilograms
        self.onValidate = onValidate
        // Saisie manuelle pre-remplie avec la cible : le cas le plus courant
        // est « j'ai tenu ce qui etait prevu ».
        _durationSeconds = State(initialValue: max(0, targetDurationSeconds ?? 0))
        _distanceMeters = State(initialValue: max(0, targetDistanceMeters ?? 0))
        _weight = State(initialValue: max(0, initialWeight))
    }

    var body: some View {
        VStack(spacing: 16) {
            if measure.measuresDuration {
                durationSection
            }
            if measure.measuresDistance {
                distanceSection
            }

            detailsSection

            Button {
                validate()
            } label: {
                Text(validateTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .controlSize(.large)
            .disabled(!canValidate)
            .accessibilityIdentifier("measuredLogger.validate")
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("OK") { focusedField = nil }
            }
        }
    }

    // MARK: - Temps

    private var durationSection: some View {
        VStack(spacing: 10) {
            Text(targetDurationSeconds != nil ? "Compte à rebours" : "Chronomètre")
                .font(.caption)
                .foregroundStyle(.secondary)

            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                let elapsed = elapsedSeconds(at: context.date)
                Text(verbatim: clockLabel(elapsed: elapsed))
                    .scaledSystemFont(size: 48, weight: .bold, relativeTo: .largeTitle)
                    .monospacedDigit()
                    .foregroundStyle(isOverTarget(elapsed) ? Color.orange : Color.white)
                    .accessibilityIdentifier("measuredLogger.clock")
                    .onChange(of: elapsed) { _, value in signalTargetIfNeeded(value) }
            }

            HStack(spacing: 12) {
                if runningSince == nil {
                    Button {
                        start()
                    } label: {
                        Label(accumulatedSeconds > 0 ? "Reprendre" : "Démarrer", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .accessibilityIdentifier("measuredLogger.start")
                } else {
                    Button {
                        stop()
                    } label: {
                        Label("Arrêter", systemImage: "stop.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .accessibilityIdentifier("measuredLogger.stop")
                }
                if runningSince == nil, accumulatedSeconds > 0 {
                    Button("Réinitialiser") { reset() }
                        .buttonStyle(.bordered)
                }
            }

            // Saisie manuelle : toujours possible a l'arret (chrono oublie,
            // serie faite hors de l'ecran).
            HStack(spacing: 8) {
                Text("Durée")
                    .foregroundStyle(.secondary)
                Spacer()
                TextField("min", value: minutesBinding, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 48)
                    .focused($focusedField, equals: .minutes)
                    .accessibilityLabel(Text("Minutes"))
                Text(verbatim: "min")
                    .foregroundStyle(.secondary)
                TextField("s", value: secondsBinding, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 40)
                    .focused($focusedField, equals: .seconds)
                    .accessibilityLabel(Text("Secondes"))
                Text(verbatim: "s")
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .disabled(runningSince != nil)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var minutesBinding: Binding<Int> {
        Binding(
            get: { durationSeconds / 60 },
            set: { durationSeconds = max(0, min($0, 1_440)) * 60 + durationSeconds % 60 }
        )
    }

    private var secondsBinding: Binding<Int> {
        Binding(
            get: { durationSeconds % 60 },
            set: { durationSeconds = (durationSeconds / 60) * 60 + max(0, min($0, 59)) }
        )
    }

    private func elapsedSeconds(at date: Date) -> TimeInterval {
        accumulatedSeconds + (runningSince.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }

    private func isOverTarget(_ elapsed: TimeInterval) -> Bool {
        guard let target = targetDurationSeconds, target > 0 else { return false }
        return elapsed >= Double(target) && (runningSince != nil || accumulatedSeconds > 0)
    }

    /// Avec une cible : temps restant, puis depassement « +0:05 ». Sans
    /// cible : temps ecoule. A l'arret sans chrono : la duree saisie.
    private func clockLabel(elapsed: TimeInterval) -> String {
        let isIdle = runningSince == nil && accumulatedSeconds == 0
        if isIdle {
            return MeasureFormatter.clock(seconds: durationSeconds)
        }
        let seconds = Int(elapsed.rounded(.down))
        guard let target = targetDurationSeconds, target > 0 else {
            return MeasureFormatter.clock(seconds: seconds)
        }
        if seconds < target {
            return MeasureFormatter.clock(seconds: target - seconds)
        }
        return "+" + MeasureFormatter.clock(seconds: seconds - target)
    }

    private func start() {
        focusedField = nil
        runningSince = .now
    }

    private func stop() {
        let elapsed = elapsedSeconds(at: .now)
        accumulatedSeconds = elapsed
        runningSince = nil
        durationSeconds = Int(elapsed.rounded())
    }

    private func reset() {
        runningSince = nil
        accumulatedSeconds = 0
        didSignalTarget = false
        durationSeconds = max(0, targetDurationSeconds ?? 0)
    }

    /// Cible atteinte : une vibration, une seule fois.
    private func signalTargetIfNeeded(_ elapsed: TimeInterval) {
        guard !didSignalTarget, runningSince != nil, isOverTarget(elapsed) else { return }
        didSignalTarget = true
        FeedbackSettings.notification(.success)
    }

    // MARK: - Distance

    private var distanceSection: some View {
        VStack(spacing: 4) {
            Text("Distance")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 24) {
                Button {
                    distanceMeters = max(0, distanceMeters - distanceStep)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .scaledSystemFont(size: 36, relativeTo: .title)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(Text("Diminuer la distance"))

                HStack(spacing: 4) {
                    TextField("Distance", value: $distanceMeters, format: .number.precision(.fractionLength(0...1)))
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .distance)
                        .scaledSystemFont(size: 34, weight: .bold, relativeTo: .title)
                        .monospacedDigit()
                        .multilineTextAlignment(.center)
                        .frame(minWidth: 90)
                        .accessibilityIdentifier("measuredLogger.distance")
                    Text(verbatim: "m")
                        .scaledSystemFont(size: 20, weight: .semibold, relativeTo: .body)
                        .foregroundStyle(.secondary)
                }

                Button {
                    distanceMeters += distanceStep
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .scaledSystemFont(size: 36, relativeTo: .title)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(Text("Augmenter la distance"))
            }
            .foregroundStyle(Theme.accent)
            if distanceMeters >= 1_000 {
                Text(verbatim: MeasureFormatter.distance(meters: distanceMeters))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Pas des boutons : 10 m pour un portage, 100 m pour une course.
    private var distanceStep: Double {
        distanceMeters >= 1_000 ? 100 : 10
    }

    // MARK: - Details

    private var detailsSection: some View {
        DisclosureGroup(isExpanded: $showingDetails) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Charge (facultatif)")
                    Spacer()
                    Button {
                        weight = LoadStep.stepped(weight, by: weightStepKilograms, up: false)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .accessibilityLabel(Text("Diminuer la charge"))
                    TextField(
                        "Charge",
                        value: Binding(
                            get: { massUnit.fromKilograms(weight) },
                            set: { weight = max(0, massUnit.toKilograms($0)) }
                        ),
                        format: .number.precision(.fractionLength(0...1))
                    )
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .frame(width: 60)
                    .focused($focusedField, equals: .weight)
                    Text(verbatim: massUnit.symbol)
                        .foregroundStyle(.secondary)
                    Button {
                        weight = LoadStep.stepped(weight, by: weightStepKilograms, up: true)
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .accessibilityLabel(Text("Augmenter la charge"))
                }
                Text("Lest ou charge portée. Une série au temps ou à la distance ne compte pas dans le tonnage.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Type de série", selection: $role) {
                    ForEach(SetRole.allCases, id: \.self) { value in
                        Text(SetLoggerView.label(for: value)).tag(value)
                    }
                }
                .pickerStyle(.segmented)

                TextField("Commentaire (optionnel)", text: $notes, axis: .vertical)
                    .lineLimit(1...3)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .notes)
            }
            .padding(.top, 4)
        } label: {
            Text("Détails de la série")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Validation

    private var currentResult: MeasuredSetResult {
        let duration: Int? = measure.measuresDuration
            ? (runningSince != nil ? Int(elapsedSeconds(at: .now).rounded()) : durationSeconds)
            : nil
        return MeasuredSetResult(
            durationSeconds: duration,
            distanceMeters: measure.measuresDistance ? distanceMeters : nil
        )
    }

    private var canValidate: Bool {
        // Chrono en marche : la validation l'arrete d'abord, la duree est
        // donc forcement positive des la premiere seconde.
        if runningSince != nil, measure.measuresDuration {
            return !measure.measuresDistance || MeasuredSetResult(
                durationSeconds: 1,
                distanceMeters: distanceMeters
            ).isValid(for: measure)
        }
        return currentResult.isValid(for: measure) && weight >= 0 && weight.isFinite
    }

    private func validate() {
        focusedField = nil
        // Le resultat est lu AVANT l'arret du chrono : il en prend la duree.
        let result = currentResult
        if runningSince != nil { stop() }
        guard result.isValid(for: measure) else { return }
        onValidate(Result(
            measured: result,
            weight: weight,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            role: role
        ))
        role = .working
    }

    private var validateTitle: String {
        switch role {
        case .working: return String(localized: "Valider la série")
        case .warmup: return String(localized: "Enregistrer l’échauffement")
        case .approach: return String(localized: "Enregistrer l’approche")
        case .backoff: return String(localized: "Enregistrer le back-off")
        }
    }
}
