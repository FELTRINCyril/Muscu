import SwiftUI
import WatchKit

/// Séance en cours sur l'iPhone, au poignet (lot 7).
///
/// La montre affiche ce que l'iPhone lui pousse — exercice, série n/N,
/// charge × répétitions prévues, série suivante, repos — et ne change
/// jamais l'état elle-même : « Valider », « Passer », « −15 s » et « +15 s » sont des
/// commandes exécutées sur l'iPhone par le chemin des boutons de
/// l'application. Une commande refusée le dit et ne laisse rien diverger.
///
/// Mise en page inspirée d'Ischys (`ActiveSetView`, `RestView`, licence MIT,
/// voir THIRD_PARTY_NOTICES.md).
struct WatchMirrorView: View {
    let state: WatchMirrorState

    @Environment(WatchConnectivityService.self) private var connectivity
    @Environment(WatchHealthSession.self) private var health

    @State private var adjustment: WatchSetAdjustment?
    @State private var crownWeight: Double = 0
    @State private var crownReps: Double = 1
    @State private var haptics = RestHapticTracker()
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case weight
        case reps
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if !connectivity.isReachable {
                    Label("iPhone injoignable", systemImage: "iphone.slash")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                content
                if let notice = connectivity.mirror.notice {
                    Text(notice.message)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("watch.mirror.notice")
                }
                metrics
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(state.sessionName)
        .onAppear { resetAdjustment() }
        // Nouvelle série : la proposition de l'iPhone remplace l'ajustement.
        .onChange(of: state.activity?.slotKey) { _, _ in resetAdjustment() }
        .onChange(of: state.plannedWeightKilograms) { _, _ in resetAdjustment() }
        .task(id: state.activity?.restEndsAt) { await runRestHaptics(endsAt: state.activity?.restEndsAt) }
    }

    // MARK: - Contenu selon la phase

    @ViewBuilder
    private var content: some View {
        switch state.phase {
        case .idle:
            EmptyView()
        case .warmup:
            Text("Échauffement sur l’iPhone")
                .font(.headline)
            Button("Passer l’échauffement") { connectivity.send(.finishWarmup) }
                .disabled(connectivity.mirror.isBusy)
        case .running:
            if let activity = state.activity {
                rest(activity)
                setBlock(activity)
            }
        case .needsPhone:
            if let activity = state.activity {
                Text(activity.exerciseName)
                    .font(.headline)
                rest(activity)
            }
            Text("Cette étape se saisit sur l’iPhone.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .awaitingFinish:
            Text("Toutes les séries sont faites.")
                .font(.headline)
            Text("Terminez la séance sur l’iPhone pour noter l’effort.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func setBlock(_ activity: WorkoutActivityState) -> some View {
        Text(activity.exerciseName)
            .font(.headline)
            .lineLimit(2)
        if activity.totalSets > 0 {
            Text("Série \(activity.setNumber)/\(activity.totalSets)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if state.canLogFromWatch, let adjustment {
            HStack(spacing: 4) {
                valueField(weightText(adjustment), field: .weight)
                    .digitalCrownRotation(
                        $crownWeight,
                        from: 0,
                        through: adjustment.unit.maximum,
                        by: adjustment.unit.step,
                        sensitivity: .low,
                        isContinuous: false,
                        isHapticFeedbackEnabled: true
                    )
                Text("×")
                    .foregroundStyle(.secondary)
                valueField("\(adjustment.reps)", field: .reps)
                    .digitalCrownRotation(
                        $crownReps,
                        from: Double(WatchCommandPolicy.repsRange.lowerBound),
                        through: Double(WatchCommandPolicy.repsRange.upperBound),
                        by: 1,
                        sensitivity: .low,
                        isContinuous: false,
                        isHapticFeedbackEnabled: true
                    )
            }
            .onChange(of: crownWeight) { _, value in self.adjustment?.setDisplayWeight(value) }
            .onChange(of: crownReps) { _, value in self.adjustment?.setReps(Int(value.rounded())) }

            Button {
                connectivity.send(.logSet(
                    slotKey: activity.slotKey,
                    weightKilograms: adjustment.weightKilograms,
                    reps: adjustment.reps
                ))
            } label: {
                Label("Valider la série", systemImage: "checkmark")
            }
            .tint(.green)
            .disabled(connectivity.mirror.isBusy)
            .accessibilityIdentifier("watch.mirror.logSet")

            Text("Touchez la charge ou les répétitions, puis tournez la Digital Crown.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else {
            if let planned = activity.plannedSetText {
                Text(planned)
                    .font(.title3.monospacedDigit())
            }
            Text("Cette série se saisit sur l’iPhone.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }

        if let next = activity.nextStepText {
            Text("Ensuite : \(next)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private func valueField(_ text: String, field: Field) -> some View {
        Text(text)
            .font(.title3.monospacedDigit().weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(focus == field ? Color.green : Color.secondary.opacity(0.4), lineWidth: 1)
            )
            .focusable(true)
            .focused($focus, equals: field)
    }

    private func weightText(_ adjustment: WatchSetAdjustment) -> String {
        if state.isBodyweight, adjustment.displayWeight == 0 {
            return String(localized: "PDC")
        }
        let value = adjustment.displayWeight.formatted(.number.precision(.fractionLength(0...1)))
        return "\(value) \(adjustment.unit.symbol)"
    }

    // MARK: - Repos

    @ViewBuilder
    private func rest(_ activity: WorkoutActivityState) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            switch activity.restPhase(at: context.date) {
            case .none:
                EmptyView()
            case .counting(let end):
                VStack(alignment: .leading, spacing: 4) {
                    Text("Repos")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(Self.clock(end.timeIntervalSince(context.date)))
                        .font(.title2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(end.timeIntervalSince(context.date) <= 3 ? .orange : .primary)
                    HStack {
                        Button("−15 s") { connectivity.send(.adjustRest(seconds: -WatchCommandPolicy.restStepSeconds)) }
                            .accessibilityLabel(Text("Retirer 15 secondes au repos"))
                        Button("+15 s") { connectivity.send(.adjustRest(seconds: WatchCommandPolicy.restStepSeconds)) }
                            .accessibilityLabel(Text("Ajouter 15 secondes au repos"))
                    }
                    .monospacedDigit()
                    .disabled(connectivity.mirror.isBusy)
                    Button("Passer") { connectivity.send(.skipRest) }
                        .disabled(connectivity.mirror.isBusy)
                }
            }
        }
    }

    /// Vibre aux trois dernières secondes et à la fin du repos. Tourne tant
    /// que l'application est active — poignet baissé compris pendant une
    /// séance Santé (mode « workout-processing »).
    private func runRestHaptics(endsAt: Date?) async {
        _ = haptics.cues(at: .now, restEndsAt: endsAt)
        guard let endsAt else { return }
        while !Task.isCancelled {
            for cue in haptics.cues(at: .now, restEndsAt: endsAt) {
                WatchHaptics.play(cue)
            }
            if Date.now.timeIntervalSince(endsAt) > RestHapticTracker.lateFinishTolerance { return }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    // MARK: - Mesures

    @ViewBuilder
    private var metrics: some View {
        HStack(spacing: 8) {
            if health.isRecording {
                if let bpm = health.heartRate {
                    Label("\(Int(bpm))", systemImage: "heart.fill")
                        .foregroundStyle(.red)
                }
                if let kcal = health.activeEnergyKilocalories {
                    Label("\(Int(kcal)) kcal", systemImage: "flame.fill")
                        .foregroundStyle(.orange)
                }
            }
            if let startedAt = state.startedAt {
                TimelineView(.periodic(from: startedAt, by: 1)) { context in
                    Text(Self.clock(context.date.timeIntervalSince(startedAt)))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.caption2.monospacedDigit())
        if let error = health.lastError, state.healthHost == .watch {
            Text(error)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func resetAdjustment() {
        guard state.canLogFromWatch else {
            adjustment = nil
            return
        }
        let proposal = WatchSetAdjustment(proposal: state)
        adjustment = proposal
        crownWeight = proposal.displayWeight
        crownReps = Double(proposal.reps)
    }

    /// « 1:05 », « 12:30 », « 1:02:03 ».
    static func clock(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.up)))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

/// Retour haptique du repos.
enum WatchHaptics {
    static func play(_ cue: RestHapticCue) {
        switch cue {
        case .countdown:
            WKInterfaceDevice.current().play(.click)
        case .finished:
            WKInterfaceDevice.current().play(.notification)
        }
    }
}

extension WatchCommandRejection {
    /// Explication affichée sur la montre.
    var message: String {
        switch self {
        case .noWorkout:
            return String(localized: "Aucune séance en cours sur l’iPhone.")
        case .staleSet:
            return String(localized: "La séance a avancé sur l’iPhone : rien n’a été validé.")
        case .needsPhone:
            return String(localized: "Cette série se saisit sur l’iPhone.")
        case .invalidValues:
            return String(localized: "Valeurs hors limites : rien n’a été validé.")
        case .noRest:
            return String(localized: "Le repos est déjà terminé.")
        case .workoutAlreadyRunning:
            return String(localized: "Une séance est déjà en cours sur l’iPhone.")
        case .noNextSession:
            return String(localized: "Aucune séance de programme à démarrer.")
        case .saveFailed:
            return String(localized: "L’iPhone n’a pas pu enregistrer : rien n’a été validé.")
        case .unreachable:
            return String(localized: "iPhone injoignable : rien n’a été envoyé.")
        case .unsupported:
            return String(localized: "Mettez Muscu à jour sur l’iPhone et la montre.")
        }
    }
}
