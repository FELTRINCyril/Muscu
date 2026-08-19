import SwiftUI

/// S1 — Start. The Watch's entry screen: pick a routine the phone has synced, or
/// start an empty workout. Every tap starts the local `HKWorkoutSession` and asks
/// the phone to begin; the phone pushes back state that flips `model.screen` to
/// `.session`, so this view never sets the screen itself.
///
/// Three states beyond the happy path (1b):
/// - **S-A** no routines: a dashed empty box below the Empty Workout card.
/// - **S-B** iPhone not reachable: a warning chip, dimmed routine rows, and an
///   Empty Workout that stays enabled (the Watch owns the session either way).
/// - **S-C** handing off: the tapped routine row holds a pending spinner while the
///   phone spins up; the other rows dim.
///
/// Follows the `ActiveSetView` conventions: Theme tokens for every colour,
/// `Ischys.mono` for numbers/labels, accent reserved for the status clock, the
/// title dot and the play affordance. Tappable cards are plain-styled Buttons.
struct StartView: View {
  @EnvironmentObject var model: WorkoutModel

  private var handingOff: Bool { model.pendingRoutineId != nil }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 9) {
        titleRow

        // S-B: an unreachable phone is urgent, so the status moves up top as a
        // warning rather than sitting in the footer as reassurance.
        if !model.phoneReachable {
          unreachableChip
        }

        emptyCard

        routinesLabel
        if model.routines.isEmpty {
          noRoutinesBox
        } else {
          ForEach(model.routines) { routine in
            routineRow(routine)
          }
        }

        // The reassuring "Synced" footer only earns its place when we're actually
        // reachable and not mid-handoff.
        if model.phoneReachable && !handingOff {
          footerChip
        }
      }
    }
    .onAppear {
      // A fresh appearance is never mid-handoff — clear any stale pending row.
      model.pendingRoutineId = nil
    }
  }

  // "Start" + a 6pt accent dot, left-aligned.
  private var titleRow: some View {
    HStack(spacing: 6) {
      Text("Start")
        .font(Ischys.ui(22, .bold))
        .foregroundStyle(Ischys.text1)
      Circle()
        .fill(Ischys.accent)
        .frame(width: 6, height: 6)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  // S-B — warning chip replacing "Synced with iPhone" when the phone is away.
  private var unreachableChip: some View {
    HStack(spacing: 7) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.system(size: 11))
        .foregroundStyle(Ischys.warning)
      Text("iPhone not reachable")
        .font(Ischys.mono(11))
        .foregroundStyle(Ischys.hex(0xFFD98A))
    }
    .frame(maxWidth: .infinity, alignment: .center)
    .padding(9)
    .background(
      Ischys.warning.opacity(0.09),
      in: RoundedRectangle(cornerRadius: 14)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 14).stroke(Ischys.warning.opacity(0.24), lineWidth: 1)
    )
  }

  private var emptyCard: some View {
    Button {
      WorkoutManager.shared.start()
      PhoneLink.shared.startEmpty()
    } label: {
      HStack(spacing: 12) {
        ZStack {
          Circle().fill(Ischys.accent).frame(width: 40, height: 40)
          Image(systemName: "play.fill")
            .font(.system(size: 15))
            .foregroundStyle(Ischys.accentFg)
        }
        VStack(alignment: .leading, spacing: 2) {
          Text("Empty Workout")
            .font(Ischys.ui(16, .semibold))
            .foregroundStyle(Ischys.text1)
          // S-B: sets logged on the wrist queue and reconcile, so say so rather
          // than blocking the one action that still works offline.
          Text(model.phoneReachable ? "Start fresh" : "Syncs when reconnected")
            .font(Ischys.mono(12))
            .foregroundStyle(Ischys.text3)
        }
        Spacer(minLength: 0)
      }
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Ischys.surface1, in: RoundedRectangle(cornerRadius: 20))
      .overlay(
        RoundedRectangle(cornerRadius: 20).stroke(Ischys.border, lineWidth: 1)
      )
    }
    .buttonStyle(.plain)
    // Empty Workout stays enabled offline; only a hand-off in flight dims it.
    .opacity(handingOff ? 0.34 : 1)
    .disabled(handingOff)
  }

  private var routinesLabel: some View {
    Text("ROUTINES")
      .font(Ischys.mono(10))
      .tracking(1.4)
      .foregroundStyle(Ischys.text3)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.top, 2)
  }

  // S-A — no routines synced yet.
  private var noRoutinesBox: some View {
    VStack(spacing: 5) {
      Text("No routines yet")
        .font(Ischys.ui(13.5, .semibold))
        .foregroundStyle(Ischys.text2)
      Text("Build one on your iPhone and it appears here.")
        .font(Ischys.ui(12, .regular))
        .foregroundStyle(Ischys.text3)
        .multilineTextAlignment(.center)
        .lineSpacing(1)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 18)
    .padding(.horizontal, 14)
    .overlay(
      RoundedRectangle(cornerRadius: 18)
        .strokeBorder(Ischys.border, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
    )
  }

  private func routineRow(_ routine: RoutineItem) -> some View {
    let isPending = model.pendingRoutineId == routine.id
    // S-B dims all rows; S-C dims every row except the one handing off.
    let dimmed = (!model.phoneReachable && !handingOff) || (handingOff && !isPending)

    return Button {
      // S-C: hold this row's pending state while the phone spins the workout up.
      // The phone's `.session` push (or `onAppear`) clears it.
      model.pendingRoutineId = routine.id
      WorkoutManager.shared.start()
      PhoneLink.shared.startRoutine(routine.id)
    } label: {
      HStack(spacing: 12) {
        if isPending {
          PendingRing().frame(width: 40, height: 40)
        } else {
          Text(routine.initials)
            .font(Ischys.mono(14, .semibold))
            .foregroundStyle(Ischys.accent)
            .frame(width: 40, height: 40)
            .background(Ischys.surface3, in: RoundedRectangle(cornerRadius: 12))
        }
        VStack(alignment: .leading, spacing: 2) {
          Text(routine.name)
            .font(Ischys.ui(16, .semibold))
            .foregroundStyle(Ischys.text1)
            .lineLimit(1).minimumScaleFactor(0.8)
          if isPending {
            Text("Starting on iPhone…")
              .font(Ischys.mono(12))
              .foregroundStyle(Ischys.accent)
          } else {
            Text("\(routine.exerciseCount) exercises")
              .font(Ischys.mono(12))
              .foregroundStyle(Ischys.text3)
          }
        }
        Spacer(minLength: 0)
        if !isPending {
          Image(systemName: "chevron.right")
            .font(.system(size: 14))
            .foregroundStyle(Ischys.text3)
        }
      }
      .padding(isPending ? 13 : 12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        isPending ? Ischys.accent.opacity(0.07) : Ischys.surface1,
        in: RoundedRectangle(cornerRadius: 20)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 20)
          .stroke(isPending ? Ischys.accent.opacity(0.4) : Ischys.border, lineWidth: 1)
      )
    }
    .buttonStyle(.plain)
    .opacity(dimmed ? 0.34 : 1)
    // Don't let a dimmed / already-handing-off list start a second workout.
    .disabled(handingOff)
  }

  private var footerChip: some View {
    HStack(spacing: 6) {
      Image(systemName: "iphone")
        .font(.system(size: 11))
        .foregroundStyle(Ischys.water)
      Text("Synced with iPhone")
        .font(Ischys.mono(11))
        .foregroundStyle(Ischys.hex(0x9FC0FF))
    }
    .frame(maxWidth: .infinity, alignment: .center)
    .padding(.vertical, 8)
    .padding(.horizontal, 12)
    .background(
      Color(.sRGB, red: 76 / 255, green: 141 / 255, blue: 255 / 255, opacity: 0.08),
      in: RoundedRectangle(cornerRadius: 14)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 14)
        .stroke(
          Color(.sRGB, red: 76 / 255, green: 141 / 255, blue: 255 / 255, opacity: 0.18),
          lineWidth: 1
        )
    )
  }
}

/// S-C — the accent spinner in the handing-off routine row.
private struct PendingRing: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var spinning = false

  var body: some View {
    ZStack {
      Circle().stroke(Ischys.accent.opacity(0.25), lineWidth: 3)
      Circle()
        .trim(from: 0, to: 0.25)
        .stroke(Ischys.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
        .rotationEffect(.degrees(spinning ? 360 : 0))
    }
    .onAppear {
      guard !reduceMotion else { return }
      withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
        spinning = true
      }
    }
  }
}
