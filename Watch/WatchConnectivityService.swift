import Foundation
import Observation
import WatchConnectivity

/// Lien entre la montre et le téléphone.
///
/// Deux directions : le téléphone envoie l'instantané (quelle séance faire),
/// la montre renvoie les séances terminées. Les envois passent par
/// `transferUserInfo`, qui met en FILE D'ATTENTE : une séance faite hors de
/// portée de l'iPhone part dès qu'il redevient joignable, au lieu d'être
/// perdue.
/// Isolee sur l'acteur principal : les rappels de `WCSessionDelegate`
/// arrivent sur une file de fond, on n'en extrait donc que des valeurs
/// transferables avant de revenir ici.
@MainActor
@Observable
final class WatchConnectivityService: NSObject {
    private(set) var snapshot: WidgetSnapshot = .empty
    private(set) var pendingTransferCount = 0
    private(set) var lastError: String?

    private let session: WCSession?

    override init() {
        session = WCSession.isSupported() ? .default : nil
        super.init()
        guard let session else { return }
        session.delegate = self
        session.activate()
        snapshot = Self.readCachedSnapshot()
    }

    /// Envoie une séance terminée. L'appel revient immédiatement : la
    /// livraison est garantie par le système, pas par cet appel.
    func send(_ payload: WatchSessionPayload) {
        guard let session else {
            lastError = "La communication avec l’iPhone n’est pas disponible sur cet appareil."
            return
        }
        guard let data = try? JSONEncoder().encode(payload) else {
            lastError = "La séance n’a pas pu être préparée pour l’envoi."
            return
        }

        session.transferUserInfo([WatchTransferKey.session: data])
        pendingTransferCount = session.outstandingUserInfoTransfers.count
    }

    // MARK: - Cache local

    /// L'instantané reçu est conservé : la montre doit afficher quelque
    /// chose même quand l'iPhone est hors de portée.
    private static let cacheKey = "watch.snapshot"

    private static func readCachedSnapshot() -> WidgetSnapshot {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return .empty }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(WidgetSnapshot.self, from: data)) ?? .empty
    }

    private func cache(_ snapshot: WidgetSnapshot) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: Self.cacheKey)
    }

    fileprivate func apply(snapshotData data: Data) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let received = try? decoder.decode(WidgetSnapshot.self, from: data) else { return }
        // Un instantane plus recent que ce que la montre sait lire est
        // ignore, pas affiche de travers.
        guard received.version <= WidgetSnapshot.currentVersion else { return }

        snapshot = received
        cache(received)
    }

    fileprivate func noteTransferFinished(outstanding: Int, error: String?) {
        pendingTransferCount = outstanding
        if let error { lastError = error }
    }

    fileprivate func note(error: String) {
        lastError = error
    }
}

// Les rappels arrivent hors de l'acteur principal : on en extrait des
// valeurs transferables (Data, Int, String) et rien d'autre.
extension WatchConnectivityService: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith state: WCSessionActivationState,
        error: Error?
    ) {
        let message = error?.localizedDescription
        let data = session.receivedApplicationContext[WatchTransferKey.snapshot] as? Data

        Task { @MainActor in
            if let message { self.note(error: message) }
            if let data { self.apply(snapshotData: data) }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext[WatchTransferKey.snapshot] as? Data else { return }
        Task { @MainActor in self.apply(snapshotData: data) }
    }

    nonisolated func session(
        _ session: WCSession,
        didFinish userInfoTransfer: WCSessionUserInfoTransfer,
        error: Error?
    ) {
        let outstanding = session.outstandingUserInfoTransfers.count
        let message = error?.localizedDescription
        Task { @MainActor in self.noteTransferFinished(outstanding: outstanding, error: message) }
    }
}
