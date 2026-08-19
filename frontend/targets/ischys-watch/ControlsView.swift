import SwiftUI

/// S5 — Controls. A 2×2 grid of circular actions for the running session:
/// Finish and Discard both close the Watch's `HKWorkoutSession` before telling
/// the phone what to do with the workout; Pause holds the session; Add asks the
/// phone to append a set. The phone remains the source of truth for the data —
/// these buttons only send intents (see `PhoneLink`).
///
/// DECISION 2 (resolved — see `EndOfWorkoutState` in `ActiveSetView`): this was
/// "End" in error red, but `endWorkout()` SAVES the workout to history — red
/// implies loss, and the button that actually loses data is Discard. Colours were
/// inverted. Unified with the E1 end-state: this is **Finish** in accent (the
/// primary, saving action), **Discard** now carries the error red, and **Add**
/// moves to `water` to match E1's "Add from iPhone" and keep accent to one action.
struct ControlsView: View {
  @EnvironmentObject var model: WorkoutModel

  var body: some View {
    VStack(spacing: 0) {
      // No top clock — watchOS draws the system time top-right already.
      Spacer()

      LazyVGrid(columns: [GridItem(spacing: 12), GridItem(spacing: 12)], spacing: 12) {
        controlButton(color: Ischys.accent, icon: "stop.fill", label: "Finish") {
          WorkoutManager.shared.end()
          PhoneLink.shared.endWorkout()
        }
        controlButton(color: Ischys.warning, icon: "pause.fill", label: "Pause") {
          WorkoutManager.shared.pause()
        }
        controlButton(color: Ischys.error, icon: "trash", label: "Discard") {
          WorkoutManager.shared.discard()
          PhoneLink.shared.discardWorkout()
        }
        controlButton(color: Ischys.water, icon: "plus", label: "Add") {
          PhoneLink.shared.addSet()
        }
      }

      Spacer()
    }
  }

  /// One circular action: a tinted disc with an SF Symbol, a token label below.
  private func controlButton(
    color: Color,
    icon: String,
    label: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      VStack(spacing: 6) {
        Circle()
          .fill(color.opacity(0.14))
          .overlay(Circle().stroke(color.opacity(0.4), lineWidth: 1))
          .frame(width: 58, height: 58)
          .overlay(
            Image(systemName: icon)
              .font(.system(size: 24))
              .foregroundStyle(color)
          )
        Text(label)
          .font(Ischys.ui(13, .semibold))
          .foregroundStyle(Ischys.text2)
      }
    }
    .buttonStyle(.plain)
  }
}
