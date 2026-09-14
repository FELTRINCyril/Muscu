import WidgetKit
import SwiftUI

/// Prochaine seance prevue.
struct NextSessionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.cyril.Muscu.NextSession", provider: MuscuProvider()) { entry in
            NextSessionWidgetView(snapshot: entry.snapshot)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Prochaine séance")
        .description("La séance qui vient, et son programme.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct NextSessionWidgetView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Prochaine séance", systemImage: "dumbbell.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let name = snapshot.nextSessionName {
                Text(name)
                    .font(.headline)
                    .lineLimit(2)
                if let date = snapshot.nextSessionDate {
                    Text(date, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let program = snapshot.programName {
                    Text(program)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                // Un widget sans donnee le DIT, plutot que d'afficher un
                // cadre vide qu'on prendrait pour une panne.
                Text("Aucune séance planifiée")
                    .font(.subheadline)
                Text("Ouvrez Muscu pour en prévoir une.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
