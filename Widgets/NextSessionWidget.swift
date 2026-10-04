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

    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            // Un tap demarre la prochaine seance : l'application ouvre
            // l'ecran de preparation (ou reprend la seance en cours), comme
            // le bouton de l'accueil. Rien ne demarre sans elle.
            .widgetURL(snapshot.nextSessionName != nil ? MuscuDeepLink.startNextSession.url : nil)
    }

    @ViewBuilder
    private var content: some View {
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
                if family == .systemMedium {
                    Spacer(minLength: 0)
                    Link(destination: MuscuDeepLink.startNextSession.url) {
                        Label("Démarrer la prochaine séance", systemImage: "play.fill")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.accentColor.opacity(0.25), in: Capsule())
                    }
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
