import SwiftUI
import WidgetKit

/// Complication de la montre (lot 7) : séance en cours ou prochaine séance.
///
/// Elle lit l'état déposé par l'application de la montre
/// (`WatchComplicationStore`), jamais autre chose. L'application la
/// recharge à chaque changement visible ; le décompte du repos est tenu par
/// le système, sans rechargement.
@main
struct MuscuWatchWidgets: WidgetBundle {
    var body: some Widget {
        MuscuComplication()
    }
}

struct MuscuComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.cyril.Muscu.watch.complication", provider: ComplicationProvider()) { entry in
            ComplicationView(state: entry.state)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Muscu")
        .description("La séance en cours, ou la prochaine.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular])
    }
}

struct ComplicationEntry: TimelineEntry {
    let date: Date
    let state: WatchComplicationState
}

struct ComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> ComplicationEntry {
        ComplicationEntry(date: .now, state: WatchComplicationState(title: String(localized: "Prochaine séance")))
    }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        completion(ComplicationEntry(date: .now, state: WatchComplicationStore.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        let state = WatchComplicationStore.read()
        var entries = [ComplicationEntry(date: .now, state: state)]
        // Fin du repos : la complication cesse d'afficher le décompte.
        if let end = state.restEndsAt, end > .now {
            var after = state
            after.restEndsAt = nil
            entries.append(ComplicationEntry(date: end, state: after))
        }
        completion(Timeline(entries: entries, policy: .never))
    }
}

struct ComplicationView: View {
    let state: WatchComplicationState

    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            circular
        default:
            rectangular
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label(state.isWorkoutRunning ? "Séance en cours" : "Prochaine séance", systemImage: "dumbbell.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .widgetAccentable()
            if let title = state.title {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
            } else {
                // Rien d'inventé : sans donnée reçue, on le dit.
                Text("Aucune séance connue")
                    .font(.headline)
                    .lineLimit(1)
            }
            if let end = state.restEndsAt {
                Text(timerInterval: Date.now...end, countsDown: true)
                    .font(.caption.monospacedDigit())
            } else if let detail = state.detail {
                Text(detail)
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var circular: some View {
        if state.isWorkoutRunning {
            if let end = state.restEndsAt {
                ProgressView(timerInterval: Date.now...end, countsDown: true) {
                    Image(systemName: "timer")
                }
                .progressViewStyle(.circular)
            } else {
                VStack(spacing: 0) {
                    Image(systemName: "dumbbell.fill")
                        .font(.caption)
                    Text("\(state.completedSets)")
                        .font(.headline.monospacedDigit())
                }
            }
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "dumbbell.fill")
                    .font(.title3)
                    .widgetAccentable()
            }
        }
    }
}
