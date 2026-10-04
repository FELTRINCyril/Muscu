import WidgetKit
import SwiftUI
import ActivityKit
import AppIntents

/// Interface de la Live Activity de séance en cours.
///
/// Elle s'affiche sur l'écran verrouillé : on n'y met que ce que l'écran de
/// saisie montre déjà (exercice, série, charge × répétitions prévues, série
/// suivante, repos), jamais un poids de corps ou une note.
///
/// Les boutons sont des `LiveActivityIntent` : ils s'exécutent dans
/// l'application, sur la séance en cours, comme les boutons équivalents de
/// l'écran de saisie. « Valider la série » n'apparaît que si la série est
/// entièrement connue ; sinon le bouton ouvre l'application.
struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            WorkoutActivityLockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.6))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(MuscuDeepLink.resumeWorkout.url)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.exerciseName)
                            .font(.headline)
                            .lineLimit(1)
                        if context.state.totalSets > 0 {
                            Text("Série \(context.state.setNumber)/\(context.state.totalSets)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RestTimerText(state: context.state, compact: false)
                        .font(.title3.monospacedDigit())
                        .multilineTextAlignment(.trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        PlannedSetLine(state: context.state)
                        ActivityButtons(state: context.state)
                    }
                }
            } compactLeading: {
                Image(systemName: "dumbbell.fill")
            } compactTrailing: {
                if case .none = context.state.restPhase(at: .now) {
                    Text(verbatim: "\(context.state.setNumber)/\(context.state.totalSets)")
                        .font(.caption2.monospacedDigit())
                } else {
                    RestTimerText(state: context.state, compact: true)
                        .font(.caption2.monospacedDigit())
                        .frame(maxWidth: 44)
                }
            } minimal: {
                Image(systemName: "dumbbell.fill")
            }
            .widgetURL(MuscuDeepLink.resumeWorkout.url)
        }
    }
}

// MARK: - Écran verrouillé

private struct WorkoutActivityLockScreenView: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(context.attributes.sessionName, systemImage: "dumbbell.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if context.state.totalSets > 0 {
                    Text("Série \(context.state.setNumber)/\(context.state.totalSets)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            HStack(alignment: .firstTextBaseline) {
                Text(context.state.exerciseName)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                RestTimerText(state: context.state, compact: false)
                    .font(.headline.monospacedDigit())
                    .multilineTextAlignment(.trailing)
            }

            RestProgress(state: context.state)
            PlannedSetLine(state: context.state)
            ActivityButtons(state: context.state)
        }
        .padding()
    }
}

// MARK: - Éléments communs

/// Repos : décompte jusqu'à la fin prévue, puis dépassement « +0:12 »
/// comme dans l'application. Les deux sont tenus par le SYSTÈME à partir des
/// dates : ils restent justes application suspendue. Le passage de l'un à
/// l'autre se fait au redessin que déclenche la péremption de l'activité,
/// fixée à la fin du repos.
private struct RestTimerText: View {
    let state: WorkoutActivityState
    let compact: Bool

    var body: some View {
        switch state.restPhase(at: .now) {
        case .counting(let endsAt):
            Text(timerInterval: Date.now...max(Date.now, endsAt), countsDown: true)
                .accessibilityLabel(Text("Repos en cours"))
        case .overtime(let since):
            HStack(spacing: 0) {
                Text(verbatim: "+")
                Text(
                    timerInterval: since...since.addingTimeInterval(WorkoutActivityState.maximumOvertimeSeconds),
                    countsDown: false
                )
            }
            .foregroundStyle(.orange)
            .accessibilityLabel(Text("Repos dépassé"))
        case .none:
            if !compact {
                Text("\(state.completedSets) série(s)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Barre de progression du repos, pendant le décompte seulement.
private struct RestProgress: View {
    let state: WorkoutActivityState

    var body: some View {
        if case .counting(let endsAt) = state.restPhase(at: .now),
           let start = state.restStartedAt, start < endsAt {
            ProgressView(timerInterval: start...endsAt, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .tint(.orange)
        }
    }
}

/// Série prévue et série suivante.
private struct PlannedSetLine: View {
    let state: WorkoutActivityState

    var body: some View {
        HStack(spacing: 12) {
            if let planned = state.plannedSetText {
                Label {
                    Text(verbatim: planned)
                        .monospacedDigit()
                } icon: {
                    Image(systemName: "scalemass")
                }
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let next = state.nextStepText {
                Text("Ensuite : \(next)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

/// Boutons : valider (ou ouvrir), passer le repos, +30 s.
private struct ActivityButtons: View {
    let state: WorkoutActivityState

    var body: some View {
        let phase = state.restPhase(at: .now)
        HStack(spacing: 8) {
            if state.canQuickLog {
                Button(intent: CompleteSetActivityIntent(slotKey: state.slotKey)) {
                    Label("Valider la série", systemImage: "checkmark")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
                .tint(.green)
            } else {
                // Une série qui demande une saisie (palier, temps, charge
                // inconnue) se valide dans l'application, jamais à l'aveugle.
                Link(destination: MuscuDeepLink.resumeWorkout.url) {
                    Label("Ouvrir", systemImage: "arrow.up.forward.app")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
            }

            if phase != .none {
                Button(intent: SkipRestActivityIntent()) {
                    Label("Passer", systemImage: "forward.end.fill")
                        .lineLimit(1)
                }
                .accessibilityLabel(Text("Passer le repos"))
            }
            if state.canExtendRest(at: .now) {
                Button(intent: ExtendRestActivityIntent()) {
                    Text("+30 s")
                        .monospacedDigit()
                }
                .accessibilityLabel(Text("Prolonger le repos de 30 secondes"))
            }
        }
        .buttonStyle(.bordered)
        .font(.subheadline.weight(.semibold))
    }
}
