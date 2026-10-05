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
/// l'écran de saisie et de l'écran de repos. Pas de bouton « Ouvrir » : un
/// tap sur le bandeau ouvre déjà l'application (`widgetURL`).
///
/// Le contenu d'un repos est juste SANS mise à jour à sa fin : la série qui
/// suit le repos et son bouton « Valider » sont déjà affichés pendant le
/// repos, et le décompte, tenu par le système, s'arrête à 0:00. La fin du
/// repos ne fait que retirer la ligne du repos (redessin à la péremption,
/// ou mise à jour poussée par l'application).
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
                        PositionText(state: context.state)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.controls(at: .now).showsRest {
                        RestCountdownText(state: context.state)
                            .font(.title3.monospacedDigit())
                            .multilineTextAlignment(.trailing)
                    } else {
                        PlannedSetText(state: context.state)
                            .font(.headline)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ActivityActions(state: context.state, showsPlannedSet: true)
                }
            } compactLeading: {
                Image(systemName: "dumbbell.fill")
            } compactTrailing: {
                if context.state.controls(at: .now).showsRest {
                    RestCountdownText(state: context.state)
                        .font(.caption2.monospacedDigit())
                        .frame(maxWidth: 44)
                } else if context.state.totalSets > 0 {
                    Text(verbatim: "\(context.state.setNumber)/\(context.state.totalSets)")
                        .font(.caption2.monospacedDigit())
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
        let state = context.state
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(context.attributes.sessionName, systemImage: "dumbbell.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                PositionText(state: state)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(state.exerciseName)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 8)
                PlannedSetText(state: state)
                    .font(.headline)
            }

            ActivityActions(state: state, showsPlannedSet: false)
        }
        .padding()
    }
}

// MARK: - Éléments communs

/// « Série 2/4 », « Échauffement 1/3 ».
private struct PositionText: View {
    let state: WorkoutActivityState

    var body: some View {
        if state.totalSets > 0 {
            if state.isWarmup {
                Text("Échauffement \(state.setNumber)/\(state.totalSets)")
            } else {
                Text("Série \(state.setNumber)/\(state.totalSets)")
            }
        }
    }
}

/// Ce que « Valider » enregistrera : « 80 kg × 8 ».
private struct PlannedSetText: View {
    let state: WorkoutActivityState

    var body: some View {
        if let planned = state.plannedSetText {
            Text(verbatim: planned)
                .monospacedDigit()
                .lineLimit(1)
        }
    }
}

/// Décompte du repos, tenu par le SYSTÈME à partir des dates : il reste
/// juste application suspendue et s'arrête de lui-même à 0:00 — jamais de
/// valeur négative ni de texte qui attend une mise à jour.
private struct RestCountdownText: View {
    let state: WorkoutActivityState

    var body: some View {
        if case .counting(let endsAt) = state.restPhase(at: .now) {
            let start = min(state.restStartedAt ?? .now, endsAt)
            Text(timerInterval: start...endsAt, countsDown: true)
                .foregroundStyle(.orange)
                .accessibilityLabel(Text("Repos en cours"))
        }
    }
}

/// Ligne du repos (pendant un repos) ou série suivante, puis « Valider ».
private struct ActivityActions: View {
    let state: WorkoutActivityState
    /// Dynamic Island : la charge prévue n'a pas de ligne à elle pendant un
    /// repos (le décompte occupe la région de droite).
    let showsPlannedSet: Bool

    var body: some View {
        let controls = state.controls(at: .now)
        VStack(alignment: .leading, spacing: 6) {
            if controls.showsRest {
                RestControls(state: state)
            } else if controls.showsNextStep, let next = state.nextStepText {
                Text("Ensuite : \(next)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if controls.showsValidate {
                Button(intent: CompleteSetActivityIntent(slotKey: state.slotKey)) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                        Text("Valider")
                        if showsPlannedSet, controls.showsRest, let planned = state.plannedSetText {
                            Text(verbatim: planned)
                                .monospacedDigit()
                                .opacity(0.85)
                        }
                    }
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .font(.subheadline.weight(.semibold))
                .accessibilityLabel(Text("Valider la série"))
            }
        }
    }
}

/// Décompte, « −15 s », « +15 s », « Passer ». Pas de barre de progression :
/// la hauteur d'une Live Activity est comptée, le décompte suffit.
private struct RestControls: View {
    let state: WorkoutActivityState

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "timer")
                .foregroundStyle(.orange)
            RestCountdownText(state: state)
                .font(.title3.monospacedDigit().weight(.semibold))
                .frame(minWidth: 56, alignment: .leading)
            Spacer(minLength: 4)
            Button(intent: AdjustRestActivityIntent(seconds: -15)) {
                Text(verbatim: "−15 s")
                    .monospacedDigit()
            }
            .accessibilityLabel(Text("Retirer 15 secondes au repos"))
            Button(intent: AdjustRestActivityIntent(seconds: 15)) {
                Text(verbatim: "+15 s")
                    .monospacedDigit()
            }
            .accessibilityLabel(Text("Ajouter 15 secondes au repos"))
            Button(intent: SkipRestActivityIntent()) {
                Text("Passer")
            }
            .accessibilityLabel(Text("Passer le repos"))
        }
        .buttonStyle(.bordered)
        .font(.subheadline.weight(.semibold))
        .lineLimit(1)
    }
}

// MARK: - Aperçus

#Preview("Série à faire", as: .content, using: WorkoutActivityAttributes(sessionName: "Push A", startedAt: .now)) {
    WorkoutLiveActivity()
} contentStates: {
    WorkoutActivityState(
        exerciseName: "Développé couché",
        setNumber: 2,
        totalSets: 4,
        completedSets: 1,
        plannedSetText: "80 kg × 8",
        nextStepText: "Série 3/4",
        canQuickLog: true,
        slotKey: "apercu"
    )
    WorkoutActivityState(
        exerciseName: "Développé couché",
        setNumber: 3,
        totalSets: 4,
        restEndsAt: .now.addingTimeInterval(75),
        completedSets: 2,
        restStartedAt: .now.addingTimeInterval(-15),
        plannedSetText: "80 kg × 8",
        nextStepText: "Série 4/4",
        canQuickLog: true,
        slotKey: "apercu"
    )
}
