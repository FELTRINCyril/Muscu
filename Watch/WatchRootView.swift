import SwiftUI

/// Séance faite à la montre seule (iPhone injoignable).
struct AutonomousRoute: Hashable, Identifiable {
    let id = UUID()
    let sessionName: String
    let exercises: [WatchPlannedExercise]
    let isFree: Bool
}

/// Écran d'accueil de la montre : la prochaine séance, et de quoi la faire.
///
/// Quand une séance tourne sur l'iPhone, la montre la suit en miroir.
/// Démarrer depuis la montre démarre la séance SUR L'IPHONE s'il est
/// joignable (puis bascule en miroir) ; sinon la séance est enregistrée à
/// la montre seule et part vers l'iPhone dès qu'il redevient joignable.
struct WatchRootView: View {
    @Environment(WatchConnectivityService.self) private var connectivity

    @State private var autonomous: AutonomousRoute?

    var body: some View {
        NavigationStack {
            if let state = connectivity.mirror.state, state.hasWorkout {
                WatchMirrorView(state: state)
            } else {
                home
                    .navigationDestination(item: $autonomous) { route in
                        WatchWorkoutView(route: route)
                    }
            }
        }
    }

    private var nextSessionName: String? {
        connectivity.plan.sessionName ?? connectivity.snapshot.nextSessionName
    }

    private var home: some View {
        List {
            Section {
                if let name = nextSessionName {
                    Button {
                        startNext(name: name)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name)
                                .font(.headline)
                            if let program = connectivity.plan.programName ?? connectivity.snapshot.programName {
                                Text(program)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(connectivity.mirror.isBusy)
                    .accessibilityIdentifier("watch.startNext")
                } else {
                    // Rien d'inventé : sans donnée reçue, on le dit.
                    Text("Aucune séance connue")
                        .font(.headline)
                    Text("Ouvrez Muscu sur l’iPhone pour transmettre votre programme.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Button {
                    startFree()
                } label: {
                    Label("Séance libre", systemImage: "plus.circle")
                }
                .disabled(connectivity.mirror.isBusy)
                .accessibilityIdentifier("watch.startFree")
            } header: {
                Text("Prochaine séance")
            } footer: {
                Text(connectivity.isReachable
                     ? "La séance démarre sur l’iPhone et se suit ici."
                     : "iPhone injoignable : la séance sera enregistrée à la montre puis envoyée.")
            }

            if let notice = connectivity.mirror.notice {
                Section {
                    Text(notice.message)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
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

    private func startNext(name: String) {
        if connectivity.isReachable {
            connectivity.send(.startNext)
        } else {
            autonomous = AutonomousRoute(sessionName: name, exercises: connectivity.plan.exercises, isFree: false)
        }
    }

    private func startFree() {
        if connectivity.isReachable {
            connectivity.send(.startFree)
        } else {
            autonomous = AutonomousRoute(
                sessionName: String(localized: "Séance libre"),
                exercises: connectivity.plan.exercises,
                isFree: true
            )
        }
    }
}
