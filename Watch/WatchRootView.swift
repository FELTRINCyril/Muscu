import SwiftUI

/// Écran d'accueil de la montre : la prochaine séance, et de quoi la faire.
///
/// La montre n'est pas une seconde application complète : elle enregistre des
/// séries et les renvoie au téléphone, qui reste la source de vérité.
struct WatchRootView: View {
    @Environment(WatchConnectivityService.self) private var connectivity

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let name = connectivity.snapshot.nextSessionName {
                        NavigationLink {
                            WatchWorkoutView(sessionName: name)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(name)
                                    .font(.headline)
                                if let program = connectivity.snapshot.programName {
                                    Text(program)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } else {
                        // Rien d'inventé : sans donnée reçue, on le dit.
                        Text("Aucune séance connue")
                            .font(.headline)
                        Text("Ouvrez Muscu sur l’iPhone pour transmettre votre programme.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Prochaine séance")
                }

                Section {
                    LabeledContent("Cette semaine", value: "\(connectivity.snapshot.sessionsThisWeek) séance(s)")
                    LabeledContent("Séries", value: "\(connectivity.snapshot.workingSetsThisWeek)")
                }

                if connectivity.pendingTransferCount > 0 {
                    Section {
                        Label(
                            "\(connectivity.pendingTransferCount) séance(s) en attente d’envoi",
                            systemImage: "arrow.up.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    } footer: {
                        Text("Elles partiront dès que l’iPhone sera joignable. Rien n’est perdu.")
                    }
                }
            }
            .navigationTitle("Muscu")
        }
    }
}
