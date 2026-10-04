import WidgetKit
import SwiftUI

/// Dernière séance terminée : date, durée, séries, tonnage, record.
///
/// Un tap ouvre l'application sur « Refaire » cette séance — toujours avec
/// une confirmation : un widget ne démarre rien seul.
struct LastSessionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.cyril.Muscu.LastSession", provider: MuscuProvider()) { entry in
            LastSessionWidgetView(snapshot: entry.snapshot)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Dernière séance")
        .description("Votre dernière séance, à refaire d’un tap.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct LastSessionWidgetView: View {
    let snapshot: WidgetSnapshot

    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetURL(snapshot.lastSession.map { MuscuDeepLink.replaySession($0.sessionId).url })
    }

    @ViewBuilder
    private var content: some View {
        if let session = snapshot.lastSession {
            VStack(alignment: .leading, spacing: 4) {
                Label("Dernière séance", systemImage: "clock.arrow.circlepath")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(verbatim: session.name)
                    .font(.headline)
                    .lineLimit(family == .systemSmall ? 2 : 1)

                Text(session.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if family == .systemMedium {
                    HStack(spacing: 16) {
                        metric(title: "Durée", value: Self.duration(session.durationSeconds))
                        metric(title: "Séries", value: "\(session.workingSets)")
                        metric(title: "Tonnage", value: tonnage(session))
                    }
                    .padding(.top, 2)
                } else {
                    Text("\(Self.duration(session.durationSeconds)) · \(session.workingSets) séries")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let tonnage = session.tonnageText {
                        Text(verbatim: session.tonnageIsPartial ? "≥ " + tonnage : tonnage)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)

                if let record = session.recordExerciseName {
                    recordLine(exercise: record, count: session.recordCount)
                }
            }
        } else {
            // Sans séance, le widget le DIT plutôt que d'afficher un cadre
            // vide qu'on prendrait pour une panne.
            VStack(alignment: .leading, spacing: 4) {
                Label("Dernière séance", systemImage: "clock.arrow.circlepath")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("Aucune séance terminée")
                    .font(.subheadline)
                Text("Elle apparaîtra ici après votre première séance.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func metric(title: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(verbatim: value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private func recordLine(exercise: String, count: Int) -> some View {
        Label {
            if count > 1 {
                Text("Records : \(exercise) +\(count - 1)")
                    .lineLimit(1)
            } else {
                Text("Record : \(exercise)")
                    .lineLimit(1)
            }
        } icon: {
            Image(systemName: "trophy.fill")
                .foregroundStyle(.yellow)
        }
        .font(.caption2)
    }

    /// Tonnage déjà mis en forme par l'application ; « — » s'il est
    /// inconnu (jamais « 0 kg »), « ≥ » s'il n'est que partiel.
    private func tonnage(_ session: LastSessionSummary) -> String {
        guard let text = session.tonnageText else { return "—" }
        return session.tonnageIsPartial ? "≥ " + text : text
    }

    /// « 52 min », « 1 h 05 ».
    static func duration(_ seconds: Int) -> String {
        let minutes = max(0, seconds) / 60
        guard minutes >= 60 else { return "\(minutes) min" }
        return String(format: "%d h %02d", minutes / 60, minutes % 60)
    }
}
