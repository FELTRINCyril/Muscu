import WidgetKit
import SwiftUI

/// Entree de widget : l'instantane, et rien de plus.
struct MuscuEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

/// Fournisseur commun aux widgets.
///
/// Il LIT un fichier deja ecrit par l'application. Aucun calcul n'est refait
/// ici : deux vues qui recalculeraient le meme indicateur finiraient par
/// diverger, et un widget ne doit jamais contredire l'application.
struct MuscuProvider: TimelineProvider {
    func placeholder(in context: Context) -> MuscuEntry {
        MuscuEntry(date: .now, snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (MuscuEntry) -> Void) {
        completion(MuscuEntry(date: .now, snapshot: WidgetSnapshotStore.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MuscuEntry>) -> Void) {
        let entry = MuscuEntry(date: .now, snapshot: WidgetSnapshotStore.read())
        // Rafraichissement horaire : le contenu ne change qu'apres une seance
        // ou un changement de planning, et l'application demande alors
        // explicitement une mise a jour.
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}
