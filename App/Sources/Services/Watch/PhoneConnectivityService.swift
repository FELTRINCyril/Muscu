import Foundation
import SwiftData
import WatchConnectivity
import Observation
import MuscuEngine

/// Côté téléphone du lien avec la montre.
///
/// Il envoie l'instantané (quelle séance faire), la prochaine séance et ses
/// exercices, et l'état de la séance en cours (lot 7) ; il reçoit les
/// séances terminées à la montre, les commandes de la séance en miroir et
/// ce que la montre a enregistré dans Santé. Rien d'autre ne transite : la
/// montre ne reçoit ni historique, ni mesures, ni notes.
@MainActor
@Observable
final class PhoneConnectivityService: NSObject {
    /// Service du lancement, joignable par ce qui agit hors de l'interface
    /// (déroulé, boutons de la Live Activity, Santé).
    private(set) static weak var shared: PhoneConnectivityService?

    private(set) var lastReceived: Date?
    private(set) var lastDecision: String?
    private(set) var isReachable = false

    private let modelContainer: ModelContainer
    private let session: WCSession?

    /// Contenu du contexte d'application. `updateApplicationContext`
    /// REMPLACE tout le dictionnaire : chaque envoi y remet les trois parts.
    @ObservationIgnored private var context: [String: Data] = [:]

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        self.session = WCSession.isSupported() ? .default : nil
        super.init()
        Self.shared = self
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    // MARK: - Etat de la montre

    /// Une montre est appairée et l'application Muscu y est installée.
    var isWatchAppAvailable: Bool {
#if targetEnvironment(macCatalyst)
        return false
#else
        guard let session, session.activationState == .activated else { return false }
        return session.isPaired && session.isWatchAppInstalled
#endif
    }

    var isWatchPaired: Bool {
#if targetEnvironment(macCatalyst)
        return false
#else
        guard let session, session.activationState == .activated else { return false }
        return session.isPaired
#endif
    }

    // MARK: - Envois

    /// Publie l'instantané vers la montre. `updateApplicationContext`
    /// REMPLACE le précédent : la montre voit toujours l'état courant, pas
    /// une file d'anciens messages.
    func publish(_ snapshot: WidgetSnapshot) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        context[WatchTransferKey.snapshot] = data
        pushContext()
    }

    /// Prochaine séance et ses exercices (démarrage et mode autonome).
    func publish(_ plan: WatchPlanSummary) {
        guard let data = WatchMessageCodec.encode(plan) else { return }
        context[WatchTransferKey.plan] = data
        pushContext()
    }

    /// État de la séance en cours : dans le contexte (la montre le retrouve
    /// à son lancement) ET en message immédiat quand elle est joignable.
    func publishMirror(_ state: WatchMirrorState) {
        guard let data = WatchMessageCodec.encode(state) else { return }
        context[WatchTransferKey.mirror] = data
        pushContext()
        guard let session, isWatchAppAvailable, session.isReachable else { return }
        session.sendMessage([WatchTransferKey.mirror: data], replyHandler: nil, errorHandler: nil)
    }

    /// Commande Santé à la montre hôte. File d'attente garantie
    /// (`transferUserInfo`) ET message immédiat si elle est joignable : la
    /// montre traite chaque commande une seule fois par séance.
    func send(_ command: WatchHealthCommand) {
        guard let session, isWatchAppAvailable,
              let message = WatchMessageCodec.message(command, key: WatchTransferKey.healthCommand) else { return }
        session.transferUserInfo(message)
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil, errorHandler: nil)
        }
    }

    private func pushContext() {
        // Sans montre equipee, l'envoi echouerait a chaque transition : on
        // ne l'essaie pas.
        guard let session, isWatchAppAvailable else { return }
        try? session.updateApplicationContext(context)
    }

    // MARK: - Réceptions

    fileprivate func receive(sessionData data: Data) {
        // Dates ISO 8601 depuis le lot 7 ; une montre plus ancienne les
        // encodait en secondes : les deux formats restent lisibles.
        let payload = WatchMessageCodec.decode(WatchSessionPayload.self, from: data)
            ?? (try? JSONDecoder().decode(WatchSessionPayload.self, from: data))
        guard let payload else {
            lastDecision = "Transfert illisible : rien n’a été ajouté."
            return
        }

        let context = modelContainer.mainContext
        let decision = WatchSessionImporter.importSession(payload, in: context)
        lastReceived = .now
        lastDecision = decision.explanation

        // L'entraînement que la montre a enregistré dans Santé est relié à
        // la séance : la synchronisation ne l'écrira pas une seconde fois.
        // Relier aussi après un transfert rejoué (séance déjà importée) :
        // l'opération est idempotente.
        if let identifier = payload.healthWorkoutIdentifier {
            let cardio = payload.cardio ?? WatchCardio()
            Task {
                await LiveHealthWorkoutController.shared.attachWatchWorkout(
                    identifier: identifier,
                    completedSessionId: payload.id,
                    cardio: cardio,
                    in: context,
                    store: AppServices.healthStore
                )
            }
        }

        guard decision.writesAnything else { return }
        WidgetSnapshotService.refresh(in: context)
    }

    fileprivate func receive(healthResultData data: Data) {
        guard let result = WatchMessageCodec.decode(WatchHealthResult.self, from: data) else { return }
        let context = modelContainer.mainContext
        Task {
            await LiveHealthWorkoutController.shared.receiveWatchResult(result, in: context, store: AppServices.healthStore)
        }
    }

    fileprivate func receive(metricsData data: Data) {
        guard let metrics = WatchMessageCodec.decode(WatchLiveMetrics.self, from: data) else { return }
        LiveHealthWorkoutController.shared.receiveWatchMetrics(metrics)
    }

    fileprivate func note(reachable: Bool) {
        isReachable = reachable
    }

    /// Session activée : la montre reçoit aussitôt l'état courant.
    fileprivate func sessionDidActivate() {
        pushContext()
        // L'etat courant n'est calcule que pour une montre equipee : il
        // peut reprendre la seance persistee en memoire.
        if context[WatchTransferKey.mirror] == nil, isWatchAppAvailable {
            publishMirror(WatchMirrorPublisher.currentState())
        }
    }
}

/// Réponse d'une commande. `WCSession` ne la déclare pas `Sendable` ; elle
/// n'est appelée qu'une fois, depuis l'acteur principal.
private struct ReplyHandler: @unchecked Sendable {
    let send: ([String: Any]) -> Void
}

extension PhoneConnectivityService: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith state: WCSessionActivationState,
        error: Error?
    ) {
        let reachable = session.isReachable
        let activated = state == .activated
        Task { @MainActor in
            self.note(reachable: reachable)
            if activated { self.sessionDidActivate() }
        }
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
        if let data = userInfo[WatchTransferKey.session] as? Data {
            Task { @MainActor in self.receive(sessionData: data) }
        }
        if let data = userInfo[WatchTransferKey.healthResult] as? Data {
            Task { @MainActor in self.receive(healthResultData: data) }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if let data = message[WatchTransferKey.metrics] as? Data {
            Task { @MainActor in self.receive(metricsData: data) }
        }
        if let data = message[WatchTransferKey.healthResult] as? Data {
            Task { @MainActor in self.receive(healthResultData: data) }
        }
    }

    /// Commande de la séance en miroir : exécutée, puis réponse avec l'état
    /// à jour — acceptée ou refusée, la montre affiche ce que sait l'iPhone.
    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        let reply = ReplyHandler(send: replyHandler)
        guard let data = message[WatchTransferKey.command] as? Data,
              let envelope = WatchMessageCodec.decode(WatchCommandEnvelope.self, from: data) else {
            reply.send([:])
            return
        }
        Task { @MainActor in
            let result = await WatchCommandHandler.handle(envelope)
            reply.send(WatchMessageCodec.message(result, key: WatchTransferKey.reply) ?? [:])
        }
    }
}
