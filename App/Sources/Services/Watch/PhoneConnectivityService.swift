import Foundation
import SwiftData
import WatchConnectivity
import Observation

/// Côté téléphone du lien avec la montre.
///
/// Il envoie l'instantané (quelle séance faire) et reçoit les séances
/// terminées. Rien d'autre ne transite : la montre ne reçoit ni historique,
/// ni mesures, ni notes.
@MainActor
@Observable
final class PhoneConnectivityService: NSObject {
    private(set) var lastReceived: Date?
    private(set) var lastDecision: String?
    private(set) var isReachable = false

    private let modelContainer: ModelContainer
    private let session: WCSession?

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        self.session = WCSession.isSupported() ? .default : nil
        super.init()
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    /// Publie l'instantané vers la montre. `updateApplicationContext`
    /// REMPLACE le précédent : la montre voit toujours l'état courant, pas
    /// une file d'anciens messages.
    func publish(_ snapshot: WidgetSnapshot) {
        guard let session, session.activationState == .activated else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        try? session.updateApplicationContext([WatchTransferKey.snapshot: data])
    }

    fileprivate func receive(sessionData data: Data) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let payload = try? decoder.decode(WatchSessionPayload.self, from: data) else {
            lastDecision = "Transfert illisible : rien n’a été ajouté."
            return
        }

        let decision = WatchSessionImporter.importSession(payload, in: modelContainer.mainContext)
        lastReceived = .now
        lastDecision = decision.explanation

        guard decision.writesAnything else { return }
        WidgetSnapshotService.refresh(in: modelContainer.mainContext)
    }

    fileprivate func note(reachable: Bool) {
        isReachable = reachable
    }
}

extension PhoneConnectivityService: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith state: WCSessionActivationState,
        error: Error?
    ) {
        let reachable = session.isReachable
        Task { @MainActor in self.note(reachable: reachable) }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Changement de montre appairée : on réactive pour continuer à
        // recevoir, sans rien supposer de l'ancienne.
        session.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in self.note(reachable: reachable) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let data = userInfo[WatchTransferKey.session] as? Data else { return }
        Task { @MainActor in self.receive(sessionData: data) }
    }
}
