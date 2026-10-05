import WidgetKit
import SwiftUI

/// Volume de la semaine et regularite.
struct WeeklyVolumeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.cyril.Muscu.WeeklyVolume", provider: MuscuProvider()) { entry in
            WeeklyVolumeWidgetView(snapshot: entry.snapshot)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Semaine")
        .description("Séances et séries de travail des sept derniers jours.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}

struct WeeklyVolumeWidgetView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("7 derniers jours", systemImage: "calendar")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text("\(snapshot.sessionsThisWeek) séance\(snapshot.sessionsThisWeek > 1 ? "s" : "")")
                .font(.headline)
            Text("\(snapshot.workingSetsThisWeek) série\(snapshot.workingSetsThisWeek > 1 ? "s" : "") de travail")
                .font(.caption)
                .foregroundStyle(.secondary)

            if snapshot.weeklyStreak > 1 {
                Text("\(snapshot.weeklyStreak) semaines d’affilée")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
