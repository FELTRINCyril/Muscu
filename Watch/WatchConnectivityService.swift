import Foundation
import Observation
import WatchConnectivity
import WidgetKit

/// Lien entre la montre et le téléphone.
///
/// Le téléphone envoie l'instantané, la prochaine séance avec ses
/// exercices, et l'état de la séance en cours (miroir, lot 7). La montre
/// renvoie les séances faites seule, les commandes de la séance en miroir,
/// et ce qu'elle a enregistré dans Santé.
///
/// Les séances faites seule passent par `transferUserInfo`, qui met en FILE
/// D'ATTENTE : une séance faite hors de portée de l'iPhone part dès qu'il
/// redevient joignable, au lieu d'être perdue. Les commandes du miroir, au
/// contraire, ne partent QUE si l'iPhone est joignable (`sendMessage`) :
/// une commande différée s'appliquerait à un état qui a changé.
///
/// Isolée sur l'acteur principal : les rappels de `WCSessionDelegate`
/// arrivent sur une file de fond, on n'en extrait donc que des valeurs
/// transférables avant de revenir ici.
@MainActor
@Observable
final class WatchConnectivityService: NSObject {
    /// Service du lancement, joignable par la séance Santé.
    private(set) static weak var shared: WatchConnectivityService?

    private(set) var snapshot: WidgetSnapshot = .empty
    private(set) var plan: WatchPlanSummary = .empty
    private(set) var mirror = WatchMirrorMachine()
    private(set) var isReachable = false
    private(set) var pendingTransferCount = 0
    private(set) var lastError: String?

    private let session: WCSession?
    /// Réponses Santé déjà envoyées, par séance Muscu : une demande de fin
    /// reçue deux fois (message ET file d'attente) n'enregistre qu'une fois.
    @ObservationIgnored private var healthResults: [UUID: WatchHealthResult] = [:]
    @ObservationIgnored private var finishingWorkoutIds: Set<UUID> = []
    @ObservationIgnored private var lastMetricsSentAt: Date?

    override init() {
        session = WCSession.isSupported() ? .default : nil
        super.init()
        Self.shared = self
        snapshot = Self.readCached(WidgetSnapshot.self, key: Self.snapshotCacheKey) ?? .empty
        plan = Self.readCached(WatchPlanSummary.self, key: Self.planCacheKey) ?? .empty
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    /// Unité du profil : celle de la séance en cours, sinon de l'instantané.
    var unit: WatchMassUnit {
        WatchMassUnit(symbol: mirror.state?.massUnitSymbol ?? plan.massUnitSymbol)
    }

    // MARK: - Séance faite à la montre seule

    /// Envoie une séance terminée. L'appel revient immédiatement : la
    /// livraison est garantie par le système, pas par cet appel.
    func send(_ payload: WatchSessionPayload) {
        guard let session else {
            lastError = String(localized: "La communication avec l’iPhone n’est pas disponible sur cet appareil.")
            return
        }
        guard let data = WatchMessageCodec.encode(payload) else {
            lastError = String(localized: "La séance n’a pas pu être préparée pour l’envoi.")
            return
        }

        session.transferUserInfo([WatchTransferKey.session: data])
        pendingTransferCount = session.outstandingUserInfoTransfers.count
    }

    // MARK: - Séance en miroir

    /// Envoie une commande à l'iPhone. Refusée sur place s'il est
    /// injoignable ; ignorée si une commande est déjà en route.
    func send(_ command: WatchCommand) {
        let reachable = session?.activationState == .activated && session?.isReachable == true
        guard case .send(let envelope) = mirror.prepare(command, reachable: reachable),
              let session,
              let message = WatchMessageCodec.message(envelope, key: WatchTransferKey.command) else { return }
        let commandId = envelope.id
        session.sendMessage(
            message,
            replyHandler: { reply in
                let data = reply[WatchTransferKey.reply] as? Data
                Task { @MainActor in
                    WatchConnectivityService.shared?.receive(replyData: data, commandId: commandId)
                }
            },
            errorHandler: { _ in
                Task { @MainActor in
                    WatchConnectivityService.shared?.mirror.sendFailed(commandId: commandId)
                }
            }
        )
    }

    func clearNotice() {
        mirror.clearNotice()
    }

    private func receive(replyData data: Data?, commandId: UUID) {
        guard let reply = WatchMessageCodec.decode(WatchCommandReply.self, from: data) else {
            // Réponse illisible (versions différentes) : rien n'a changé ici.
            mirror.receive(WatchCommandReply(
                commandId: commandId,
                rejection: .unsupported,
                state: mirror.state ?? .idle(sequence: 0)
            ))
            return
        }
        mirror.receive(reply)
        reconcileHealth()
        updateComplication()
    }

    // MARK: - Santé

    /// Mesures en direct pour l'iPhone, au plus toutes les 5 s et seulement
    /// s'il est joignable : une mesure périmée n'a aucun intérêt.
    func sendMetrics(now: Date = .now) {
        let health = WatchHealthSession.shared
        guard let session, session.activationState == .activated, session.isReachable,
              let workoutId = health.workoutId else { return }
        if let lastMetricsSentAt, now.timeIntervalSince(lastMetricsSentAt) < 5 { return }
        lastMetricsSentAt = now
        let metrics = WatchLiveMetrics(
            activeWorkoutId: workoutId,
            heartRate: health.heartRate,
            activeEnergyKilocalories: health.activeEnergyKilocalories
        )
        guard let message = WatchMessageCodec.message(metrics, key: WatchTransferKey.metrics) else { return }
        session.sendMessage(message, replyHandler: nil, errorHandler: nil)
    }

    /// Démarre ou rattache la séance Santé selon l'état de l'iPhone.
    private func reconcileHealth() {
        guard let state = mirror.state else { return }
        let health = WatchHealthSession.shared
        switch WatchHealthPlanner.action(
            for: state,
            isRecording: health.isRecording,
            recordingWorkoutId: health.workoutId,
            closedWorkoutIds: health.closedWorkoutIds
        ) {
        case .none:
            break
        case .associate(let id):
            health.associate(workoutId: id)
        case .start(let id):
            Task { await health.start(workoutId: id, mirrorToPhone: true) }
        }
    }

    private func handle(_ command: WatchHealthCommand) async {
        let health = WatchHealthSession.shared
        switch command {
        case .finish(let activeWorkoutId, let completedSessionId, let endDate):
            if let done = healthResults[activeWorkoutId] {
                // Demande rejouée : même réponse, rien n'est réenregistré.
                sendHealthResult(done)
                return
            }
            guard !finishingWorkoutIds.contains(activeWorkoutId) else { return }
            finishingWorkoutIds.insert(activeWorkoutId)
            let outcome: (identifier: String?, cardio: WatchCardio)
            if health.isRecording, health.workoutId == activeWorkoutId {
                outcome = await health.finish(endDate: endDate, externalId: completedSessionId)
            } else {
                outcome = (nil, WatchCardio())
            }
            finishingWorkoutIds.remove(activeWorkoutId)
            let result = WatchHealthResult(
                activeWorkoutId: activeWorkoutId,
                completedSessionId: completedSessionId,
                workoutIdentifier: outcome.identifier,
                cardio: outcome.cardio
            )
            healthResults[activeWorkoutId] = result
            sendHealthResult(result)
        case .discard(let activeWorkoutId):
            if health.workoutId == activeWorkoutId { await health.discard() }
        case .pause(let activeWorkoutId):
            if health.workoutId == activeWorkoutId { health.pause() }
        case .resume(let activeWorkoutId):
            if health.workoutId == activeWorkoutId { health.resume() }
        }
    }

    /// Réponse Santé : file d'attente garantie, et message immédiat si
    /// l'iPhone est joignable. L'iPhone relie l'entraînement une seule fois.
    private func sendHealthResult(_ result: WatchHealthResult) {
        guard let session, let message = WatchMessageCodec.message(result, key: WatchTransferKey.healthResult) else { return }
        session.transferUserInfo(message)
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil, errorHandler: nil)
        }
    }

    // MARK: - Cache local

    /// Ce qui est reçu est conservé : la montre doit afficher quelque chose
    /// même quand l'iPhone est hors de portée.
    private static let snapshotCacheKey = "watch.snapshot"
    private static let planCacheKey = "watch.plan"

    private static func readCached<Value: Decodable>(_ type: Value.Type, key: String) -> Value? {
        WatchMessageCodec.decode(type, from: UserDefaults.standard.data(forKey: key))
    }

    fileprivate func apply(context: [String: Data]) {
        if let data = context[WatchTransferKey.snapshot],
           let received = WatchMessageCodec.decode(WidgetSnapshot.self, from: data),
           // Un instantané plus récent que ce que la montre sait lire est
           // ignoré, pas affiché de travers.
           received.version <= WidgetSnapshot.currentVersion {
            snapshot = received
            UserDefaults.standard.set(data, forKey: Self.snapshotCacheKey)
        }
        if let data = context[WatchTransferKey.plan],
           let received = WatchMessageCodec.decode(WatchPlanSummary.self, from: data),
           received.version <= WatchPlanSummary.currentVersion {
            plan = received
            UserDefaults.standard.set(data, forKey: Self.planCacheKey)
        }
        if let data = context[WatchTransferKey.mirror] {
            apply(mirrorData: data)
        } else {
            updateComplication()
        }
    }

    fileprivate func apply(mirrorData data: Data) {
        guard let state = WatchMessageCodec.decode(WatchMirrorState.self, from: data) else { return }
        mirror.receive(state)
        reconcileHealth()
        updateComplication()
    }

    /// La complication suit la séance en cours, ou la prochaine séance.
    /// Rechargée seulement quand ce qu'elle affiche change.
    private func updateComplication() {
        let state = WatchComplicationState.make(
            mirror: mirror.state,
            nextSessionName: plan.sessionName ?? snapshot.nextSessionName
        )
        if WatchComplicationStore.write(state) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    fileprivate func apply(healthCommandData data: Data) {
        guard let command = WatchMessageCodec.decode(WatchHealthCommand.self, from: data) else { return }
        Task { await handle(command) }
    }

    fileprivate func noteTransferFinished(outstanding: Int, error: String?) {
        pendingTransferCount = outstanding
        if let error { lastError = error }
    }

    fileprivate func note(reachable: Bool) {
        isReachable = reachable
    }

    fileprivate func note(error: String) {
        lastError = error
    }
}

/// Extrait les `Data` d'un dictionnaire reçu : seules des valeurs
/// transférables quittent la file du délégué.
private func dataEntries(_ dictionary: [String: Any]) -> [String: Data] {
    dictionary.compactMapValues { $0 as? Data }
}

// Les rappels arrivent hors de l'acteur principal : on en extrait des
// valeurs transférables (Data, Int, String, Bool) et rien d'autre.
extension WatchConnectivityService: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith state: WCSessionActivationState,
        error: Error?
    ) {
        let message = error?.localizedDescription
        let context = dataEntries(session.receivedApplicationContext)
        let reachable = session.isReachable

        Task { @MainActor in
            if let message { self.note(error: message) }
            self.note(reachable: reachable)
            self.apply(context: context)
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in
            self.note(reachable: reachable)
            // De nouveau joignable : on redemande l'état, qui a pu avancer.
            if reachable, self.mirror.state?.hasWorkout == true { self.send(.requestState) }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let context = dataEntries(applicationContext)
        Task { @MainActor in self.apply(context: context) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let entries = dataEntries(message)
        Task { @MainActor in
            if let data = entries[WatchTransferKey.mirror] { self.apply(mirrorData: data) }
            if let data = entries[WatchTransferKey.healthCommand] { self.apply(healthCommandData: data) }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        let entries = dataEntries(userInfo)
        Task { @MainActor in
            if let data = entries[WatchTransferKey.healthCommand] { self.apply(healthCommandData: data) }
        }
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
