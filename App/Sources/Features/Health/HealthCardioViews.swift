import SwiftUI
import MuscuEngine

/// Carte discrete d'une seance Sante en direct : frequence cardiaque si un
/// capteur la fournit, energie active si elle est mesuree, duree. Sans
/// capteur, la frequence n'est PAS affichee : un « 0 bpm » serait faux.
///
/// Inspiree de UpLift (`LiveHealthKitCard`, licence MIT, voir
/// THIRD_PARTY_NOTICES.md).
struct LiveHealthCard: View {
    let controller: LiveHealthWorkoutController
    let startedAt: Date

    var body: some View {
        if controller.isActive {
            HStack(spacing: 14) {
                if let bpm = controller.heartRate {
                    Label("\(Int(bpm)) bpm", systemImage: "heart.fill")
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("workout.liveHealth.heartRate")
                }
                if let kcal = controller.activeEnergyKilocalories {
                    Label("\(Int(kcal)) kcal", systemImage: "flame.fill")
                        .foregroundStyle(.orange)
                }
                TimelineView(.periodic(from: startedAt, by: 1)) { context in
                    Label(
                        MeasureFormatter.clock(seconds: max(0, Int(context.date.timeIntervalSince(startedAt)))),
                        systemImage: "stopwatch"
                    )
                }
                Spacer(minLength: 0)
                Group {
                    if controller.isPaused {
                        Label("Santé · en pause", systemImage: "heart.text.square")
                    } else {
                        Label("Santé", systemImage: "heart.text.square")
                    }
                }
                .foregroundStyle(.secondary)
            }
            .font(.caption.monospacedDigit())
            .padding(.horizontal)
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("workout.liveHealth")
        }
    }
}

/// Cardio d'une seance terminee : seules les valeurs mesurees sont
/// affichees, jamais un zero a la place d'une absence.
struct SessionCardioView: View {
    let session: CompletedSession

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let average = session.avgHeartRate {
                LabeledContent("FC moyenne", value: Self.bpm(average))
            }
            if session.minHeartRate != nil || session.maxHeartRate != nil {
                LabeledContent(
                    "FC min. / max.",
                    value: String(localized: "\(Self.number(session.minHeartRate)) / \(Self.number(session.maxHeartRate)) bpm")
                )
            }
            if let energy = session.activeEnergyKcal {
                LabeledContent("Énergie active", value: String(localized: "\(Int(energy.rounded())) kcal"))
            }
            Text("Mesuré par une montre ou un capteur, via l’app Santé. Reste sur cet appareil.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("session.cardio")
    }

    private static func bpm(_ value: Double) -> String {
        String(localized: "\(Int(value.rounded())) bpm")
    }

    private static func number(_ value: Double?) -> String {
        value.map { String(Int($0.rounded())) } ?? "—"
    }
}
