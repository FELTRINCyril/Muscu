import WidgetKit
import SwiftUI
import ActivityKit

/// Interface de la Live Activity de séance en cours.
///
/// Elle s'affiche sur l'écran verrouillé : on n'y met que ce qui est déjà
/// visible dans l'application, jamais une charge, un poids de corps ou une
/// note.
struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            lockScreenView(context)
                .activityBackgroundTint(Color.black.opacity(0.6))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.sessionName, systemImage: "dumbbell.fill")
                        .font(.caption)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.setNumber)/\(context.state.totalSets)")
                        .font(.caption.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.exerciseName)
                            .font(.headline)
                            .lineLimit(1)
                        restLine(context.state)
                    }
                }
            } compactLeading: {
                Image(systemName: "dumbbell.fill")
            } compactTrailing: {
                Text("\(context.state.setNumber)/\(context.state.totalSets)")
                    .font(.caption2.monospacedDigit())
            } minimal: {
                Image(systemName: "dumbbell.fill")
            }
        }
    }

    private func lockScreenView(_ context: ActivityViewContext<WorkoutActivityAttributes>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(context.attributes.sessionName, systemImage: "dumbbell.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Série \(context.state.setNumber)/\(context.state.totalSets)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(context.state.exerciseName)
                .font(.headline)
                .lineLimit(1)

            restLine(context.state)
        }
        .padding()
    }

    @ViewBuilder
    private func restLine(_ state: WorkoutActivityState) -> some View {
        if let restEndsAt = state.restEndsAt, restEndsAt > .now {
            // Compte a rebours pilote par le SYSTEME a partir d'une date de
            // fin : il reste juste meme si l'application est suspendue.
            Text("Repos jusqu’à \(restEndsAt, style: .timer)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        } else {
            Text("\(state.completedSets) série(s) enregistrée(s)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
