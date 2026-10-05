import Foundation
import SwiftData
import MuscuEngine
import HealthKit

/// Seance Sante en direct sur iPhone (iOS 26 et plus).
///
/// Quand Sante est active et autorise, la seance Muscu demarre un
/// `HKWorkoutSession` et son `HKLiveWorkoutBuilder` : l'entrainement est
/// enregistre par le systeme pendant la seance, avec la frequence cardiaque
/// d'un capteur connecte et l'energie active. Il REMPLACE l'ecriture apres
/// coup : a la fin, il est relie a la seance par un `HealthWorkoutLink`, et
/// la synchronisation le reconnait comme deja ecrit.
///
/// Sur iOS 18-25 et sur Mac Catalyst, l'API n'existe pas : rien ne demarre,
/// et la seance est ecrite apres coup comme avant. Sante desactivee ou
/// refusee : rien ne demarre non plus, et rien ne casse.
///
/// Inspire de UpLift (`HealthKitWorkoutService`, licence MIT, voir
/// THIRD_PARTY_NOTICES.md), adapte : reprise apres un arret brutal, lien
/// anti-doublon, abandon sans enregistrement.
@MainActor
@Observable
final class LiveHealthWorkoutController {
    static let shared = LiveHealthWorkoutController()

    /// Une seance Sante est en cours (eventuellement en pause).
    private(set) var isActive = false
    private(set) var isPaused = false
    /// Derniere frequence cardiaque recue. `nil` = aucun capteur : la carte
    /// n'affiche alors pas de frequence, plutot qu'un « 0 » mensonger.
    private(set) var heartRate: Double?
    /// Energie active cumulee. `nil` = non mesuree.
    private(set) var activeEnergyKilocalories: Double?
    /// La seance Sante est enregistree par la montre (decision 0017) :
    /// l'iPhone n'en affiche que les mesures qu'elle lui envoie.
    private(set) var isHostedByWatch = false

    @ObservationIgnored private var activeWorkoutId: UUID?
    @ObservationIgnored private var backend: AnyObject?
    /// Seance de la montre reflechie sur l'iPhone (iOS 17+), retenue tant
    /// qu'elle dure.
    @ObservationIgnored private var mirroredSession: AnyObject?

    private init() {}

    // MARK: - Marqueur de reprise

    private static let markerKey = "health.live.marker"

    /// Ce qui permet de retrouver la seance apres un arret brutal. Persiste,
    /// pour que la synchronisation n'ecrive pas apres coup une seance dont
    /// l'entrainement est en train d'etre enregistre.
    private(set) var marker: LiveWorkoutMarker? {
        get {
            guard let data = UserDefaults.standard.data(forKey: Self.markerKey) else { return nil }
            return try? JSONDecoder().decode(LiveWorkoutMarker.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: Self.markerKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.markerKey)
            }
        }
    }

    /// Seances terminees dont l'entrainement en direct reste a finaliser.
    /// Une confirmation de la montre attendue au-dela du delai ne bloque
    /// plus l'ecriture apres coup (decision 0017).
    var recordingSessionIds: Set<UUID> {
        guard let marker, let completed = marker.completedSessionId else { return [] }
        if marker.isHostedByWatch,
           let requested = marker.finishRequestedAt,
           Date.now.timeIntervalSince(requested) >= RemoteHealthWorkout.confirmationTimeout {
            return []
        }
        return [completed]
    }

    // MARK: - Disponibilite

    /// L'appareil sait-il enregistrer une seance Sante en direct ?
    static var isSupported: Bool {
#if targetEnvironment(macCatalyst)
        return false
#else
        guard #available(iOS 26.0, *) else { return false }
        return HKHealthStore.isHealthDataAvailable()
#endif
    }

    /// Sante active, ecriture des seances active et autorisee : la montre
    /// peut enregistrer la seance. Independant d'iOS 26, puisque c'est la
    /// montre qui enregistre. Jamais de demande d'autorisation ici.
    static func isAllowedForWatch(store: HealthStoring) -> Bool {
#if targetEnvironment(macCatalyst)
        return false
#else
        return HKHealthStore.isHealthDataAvailable()
            && HealthSettings.isEnabled
            && HealthSettings.writesWorkouts
            && store.authorizationStatus() == .authorized
#endif
    }

    /// L'utilisateur a active Sante ET l'ecriture des seances, et l'a
    /// autorise. Jamais de demande d'autorisation ici.
    private static func isAllowed(store: HealthStoring) -> Bool {
        isSupported
            && HealthSettings.isEnabled
            && HealthSettings.writesWorkouts
            && store.authorizationStatus() == .authorized
    }

    // MARK: - Cycle de vie

    /// Demarre (ou reprend) la seance Sante de la seance en cours.
    ///
    /// L'hote est choisi par `HealthWorkoutCoordination` (decision 0017) :
    /// la montre si elle est appairee et equipee, sinon l'iPhone (iOS 26+),
    /// sinon personne — la seance est alors ecrite apres coup. Il ne change
    /// plus ensuite.
    func start(activeWorkoutId: UUID, store: HealthStoring) async {
        if let marker, marker.isHostedByWatch, marker.activeWorkoutId == activeWorkoutId,
           marker.completedSessionId == nil {
            resume()
            return
        }
        if self.activeWorkoutId == activeWorkoutId, backend != nil {
            resume()
            return
        }
        // Une autre seance Sante restee ouverte : elle ne correspond plus a
        // rien, elle n'est pas enregistree.
        if backend != nil || (marker?.isHostedByWatch == true && marker?.completedSessionId == nil) {
            await discard()
        }

        let connectivity = PhoneConnectivityService.shared
        let context = HealthWorkoutCoordination.Context(
            healthAllowed: Self.isAllowedForWatch(store: store),
            watchPaired: connectivity?.isWatchPaired ?? false,
            watchAppInstalled: connectivity?.isWatchAppAvailable ?? false,
            phoneLiveSupported: Self.isSupported
        )
        var host = HealthWorkoutCoordination.host(for: context)
        if host == .watch {
            if await launchWatch(activeWorkoutId: activeWorkoutId) { return }
            host = HealthWorkoutCoordination.fallbackHost(for: context)
        }
        guard host == .phone, Self.isAllowed(store: store) else { return }

#if !targetEnvironment(macCatalyst)
        guard #available(iOS 26.0, *) else { return }
        do {
            let session = try LiveWorkoutSession(onUpdate: { [weak self] statistics in
                Task { @MainActor in self?.receive(statistics) }
            })
            try await session.begin(at: .now)
            backend = session
            self.activeWorkoutId = activeWorkoutId
            marker = LiveWorkoutMarker(activeWorkoutId: activeWorkoutId)
            isActive = true
            isPaused = false
        } catch {
            // La seance continue exactement comme avant : elle sera ecrite
            // apres coup.
            DiagnosticsCenter.record(.health, code: "health.live.startFailed", error: error)
            clearState()
        }
#endif
    }

    /// « Reprendre plus tard » : la seance Muscu est mise de cote, la seance
    /// Sante aussi.
    func pause() {
        if isHostedByWatch {
            guard let activeWorkoutId, !isPaused else { return }
            PhoneConnectivityService.shared?.send(.pause(activeWorkoutId: activeWorkoutId))
            isPaused = true
            return
        }
#if !targetEnvironment(macCatalyst)
        guard #available(iOS 26.0, *), let session = backend as? LiveWorkoutSession, !isPaused else { return }
        session.pause()
        isPaused = true
#endif
    }

    func resume() {
        if isHostedByWatch {
            guard let activeWorkoutId, isPaused else { return }
            PhoneConnectivityService.shared?.send(.resume(activeWorkoutId: activeWorkoutId))
            isPaused = false
            return
        }
#if !targetEnvironment(macCatalyst)
        guard #available(iOS 26.0, *), let session = backend as? LiveWorkoutSession, isPaused else { return }
        session.resume()
        isPaused = false
#endif
    }

    /// La seance Muscu vient d'etre terminee : a partir de maintenant, la
    /// synchronisation ne l'ecrit plus apres coup. Synchrone, pour qu'aucune
    /// synchronisation ne s'intercale avant `finishRecording`.
    func markFinished(completedSessionId: UUID) {
        guard let activeWorkoutId else { return }
        if isHostedByWatch {
            marker = LiveWorkoutMarker(
                activeWorkoutId: activeWorkoutId,
                completedSessionId: completedSessionId,
                host: .watch,
                finishRequestedAt: .now
            )
            return
        }
        guard backend != nil else { return }
        marker = LiveWorkoutMarker(activeWorkoutId: activeWorkoutId, completedSessionId: completedSessionId)
    }

    /// Termine l'enregistrement, relie l'entrainement a la seance et y
    /// range le cardio mesure. En cas d'echec, la seance redevient une
    /// seance ordinaire, ecrite apres coup.
    func finishRecording(in context: ModelContext, store: HealthStoring) async {
        guard let marker, let completedSessionId = marker.completedSessionId else { return }
        if marker.isHostedByWatch {
            requestWatchFinish(marker: marker, completedSessionId: completedSessionId, in: context)
            return
        }
#if !targetEnvironment(macCatalyst)
        if #available(iOS 26.0, *), let session = backend as? LiveWorkoutSession {
            await finish(session, completedSessionId: completedSessionId, in: context, store: store)
        }
#endif
        clearState()
    }

    /// Abandon de la seance : rien n'est enregistre dans Sante.
    func discard() async {
        if let marker, marker.isHostedByWatch {
            // Une seance terminee attend la confirmation de la montre : un
            // abandon ulterieur ne la concerne pas.
            if marker.completedSessionId == nil {
                PhoneConnectivityService.shared?.send(.discard(activeWorkoutId: marker.activeWorkoutId))
                clearState()
            }
            return
        }
#if !targetEnvironment(macCatalyst)
        if #available(iOS 26.0, *), let session = backend as? LiveWorkoutSession {
            await session.discard()
        }
#endif
        clearState()
    }

    /// Au lancement : retrouve une seance Sante laissee ouverte par un arret
    /// brutal, et la rattache, la termine ou l'abandonne selon ce que la
    /// seance Muscu est devenue.
    func recover(in context: ModelContext, store: HealthStoring) async {
        guard backend == nil else { return }
        if let marker, marker.isHostedByWatch {
            recoverWatchHosted(marker: marker, in: context)
            return
        }
#if targetEnvironment(macCatalyst)
        marker = nil
#else
        guard #available(iOS 26.0, *), Self.isSupported else {
            marker = nil
            return
        }
        let recovered: LiveWorkoutSession?
        do {
            recovered = try await LiveWorkoutSession.recover(onUpdate: { [weak self] statistics in
                Task { @MainActor in self?.receive(statistics) }
            })
        } catch {
            DiagnosticsCenter.record(.health, code: "health.live.recoverFailed", error: error)
            recovered = nil
        }
        guard let recovered else {
            // Plus rien a rattacher : une seance terminee sera ecrite apres
            // coup par la synchronisation.
            marker = nil
            return
        }

        let pending = Set(((try? context.fetch(FetchDescriptor<ActiveWorkout>())) ?? []).map(\.id))
        let completed = Set(((try? context.fetch(FetchDescriptor<CompletedSession>())) ?? [])
            .filter { $0.deletedAt == nil && $0.id == marker?.completedSessionId }
            .map(\.id))

        switch LiveWorkoutRecovery.decide(marker: marker, pendingActiveWorkoutIds: pending, existingCompletedSessionIds: completed) {
        case .reattachPaused(let activeWorkoutId):
            recovered.pause()
            backend = recovered
            self.activeWorkoutId = activeWorkoutId
            isActive = true
            isPaused = true
        case .finish(let completedSessionId):
            await finish(recovered, completedSessionId: completedSessionId, in: context, store: store)
            clearState()
        case .discard:
            await recovered.discard()
            clearState()
        }
#endif
    }

    // MARK: - Seance Sante tenue par la montre (decision 0017)

    /// La montre enregistre la seance Sante de cette seance Muscu : demarree
    /// depuis la montre, ou lancee par l'iPhone (`startWatchApp`).
    func adoptWatchHost(activeWorkoutId: UUID) {
        if backend != nil {
            // Jamais deux seances Sante : celle de l'iPhone n'est pas
            // enregistree.
            Task { await discardLocalBackend() }
        }
        marker = LiveWorkoutMarker(activeWorkoutId: activeWorkoutId, host: .watch)
        self.activeWorkoutId = activeWorkoutId
        isHostedByWatch = true
        isActive = true
        isPaused = false
        heartRate = nil
        activeEnergyKilocalories = nil
    }

    /// Hote annonce a la montre pour cette seance.
    func watchHealthHost(forActiveWorkoutId id: UUID) -> WatchHealthHost {
        guard isActive, activeWorkoutId == id else { return .afterTheFact }
        return isHostedByWatch ? .watch : .phone
    }

    /// Mesures en direct envoyees par la montre.
    func receiveWatchMetrics(_ metrics: WatchLiveMetrics) {
        guard isHostedByWatch, metrics.activeWorkoutId == activeWorkoutId else { return }
        if let bpm = metrics.heartRate, bpm.isFinite, SessionCardio.heartRateRange.contains(bpm) {
            heartRate = bpm.rounded()
        } else {
            heartRate = nil
        }
        if let kcal = metrics.activeEnergyKilocalories, kcal.isFinite, SessionCardio.energyRange.contains(kcal) {
            activeEnergyKilocalories = kcal.rounded()
        }
    }

    /// Reponse de la montre a la demande de fin.
    func receiveWatchResult(_ result: WatchHealthResult, in context: ModelContext, store: HealthStoring) async {
        if marker?.completedSessionId == result.completedSessionId {
            marker = nil
            mirroredSession = nil
        }
        guard let identifier = result.workoutIdentifier else {
            // Rien n'a ete enregistre a la montre : la seance est ecrite
            // apres coup, sans attendre le delai.
            await HealthSyncService.synchronize(in: context, store: store)
            return
        }
        await attachWatchWorkout(
            identifier: identifier,
            completedSessionId: result.completedSessionId,
            cardio: result.cardio,
            in: context,
            store: store
        )
    }

    /// Relie un entrainement enregistre par la montre a sa seance, et y
    /// range le cardio. Idempotent : un transfert rejoue ne change rien.
    func attachWatchWorkout(
        identifier: String,
        completedSessionId: UUID,
        cardio: WatchCardio,
        in context: ModelContext,
        store: HealthStoring
    ) async {
        let existing = Set(((try? context.fetch(FetchDescriptor<CompletedSession>())) ?? [])
            .filter { $0.deletedAt == nil && $0.id == completedSessionId }
            .map(\.id))
        guard RemoteHealthWorkout.acceptsConfirmation(
            completedSessionId: completedSessionId,
            existingCompletedSessionIds: existing
        ) else {
            // Seance supprimee entre-temps : son entrainement ne doit pas
            // lui survivre (decision 0009).
            try? await store.deleteWorkout(identifier: identifier)
            return
        }
        await HealthSyncService.attachLiveWorkout(
            identifier: identifier,
            to: completedSessionId,
            cardio: SessionCardio(
                averageHeartRate: cardio.averageHeartRate,
                minimumHeartRate: cardio.minimumHeartRate,
                maximumHeartRate: cardio.maximumHeartRate,
                activeEnergyKilocalories: cardio.activeEnergyKilocalories
            ),
            in: context,
            store: store,
            source: "watch"
        )
    }

    /// Pose le gestionnaire des seances reflechies (iOS 17+) : la seance
    /// Sante de la montre est partagee avec l'iPhone, qui la retient tant
    /// qu'elle dure.
    func installWatchMirroring() {
#if !targetEnvironment(macCatalyst)
        Self.mirroringStore.workoutSessionMirroringStartHandler = { session in
            let box = MirroredSessionBox(session: session)
            Task { @MainActor in
                LiveHealthWorkoutController.shared.retainMirrored(box)
            }
        }
#endif
    }

    private func retainMirrored(_ box: MirroredSessionBox) {
        // Une seance reflechie hors d'une seance confiee a la montre (mode
        // autonome) n'est pas retenue : elle se termine a la montre.
        guard isHostedByWatch else { return }
        mirroredSession = box
    }

    /// Lance l'application de la montre dans la seance (`startWatchApp`).
    /// `false` si la montre n'a pas pu etre lancee : l'iPhone prend le
    /// relais selon la regle de repli.
    private func launchWatch(activeWorkoutId: UUID) async -> Bool {
#if targetEnvironment(macCatalyst)
        return false
#else
        // L'hote est publie AVANT le lancement : la montre, a peine lancee,
        // sait quelle seance elle enregistre.
        adoptWatchHost(activeWorkoutId: activeWorkoutId)
        if let workout = LiveWorkoutRegistry.shared.current { WatchMirrorPublisher.publish(workout) }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        let launched = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            Self.mirroringStore.startWatchApp(with: configuration) { success, _ in
                continuation.resume(returning: success)
            }
        }
        guard launched else {
            clearState()
            if let workout = LiveWorkoutRegistry.shared.current { WatchMirrorPublisher.publish(workout) }
            return false
        }
        return true
#endif
    }

    private func requestWatchFinish(marker: LiveWorkoutMarker, completedSessionId: UUID, in context: ModelContext) {
        let descriptor = FetchDescriptor<CompletedSession>(predicate: #Predicate { $0.id == completedSessionId })
        let duration = (try? context.fetch(descriptor).first)?.durationSeconds ?? 0
        let connectivity = PhoneConnectivityService.shared
        if LiveWorkoutRecovery.shouldSave(durationSeconds: duration) {
            connectivity?.send(.finish(
                activeWorkoutId: marker.activeWorkoutId,
                completedSessionId: completedSessionId,
                endDate: .now
            ))
            // Le marqueur reste jusqu'a la confirmation (ou au delai) : la
            // synchronisation n'ecrit pas la seance entre-temps.
            isActive = false
            isPaused = false
            isHostedByWatch = false
            heartRate = nil
            activeEnergyKilocalories = nil
            activeWorkoutId = nil
        } else {
            // Trop courte : rien n'est enregistre, ni a la montre ni apres
            // coup (meme regle que la synchronisation).
            connectivity?.send(.discard(activeWorkoutId: marker.activeWorkoutId))
            clearState()
        }
    }

    private func recoverWatchHosted(marker: LiveWorkoutMarker, in context: ModelContext) {
        let pending = Set(((try? context.fetch(FetchDescriptor<ActiveWorkout>())) ?? []).map(\.id))
        let completed = Set(((try? context.fetch(FetchDescriptor<CompletedSession>())) ?? [])
            .filter { $0.deletedAt == nil && $0.id == marker.completedSessionId }
            .map(\.id))
        switch RemoteHealthWorkout.resolve(
            marker: marker,
            pendingActiveWorkoutIds: pending,
            existingCompletedSessionIds: completed,
            now: .now
        ) {
        case .keepWaiting:
            guard marker.completedSessionId == nil else { return }
            activeWorkoutId = marker.activeWorkoutId
            isHostedByWatch = true
            isActive = true
        case .discardOnWatch:
            PhoneConnectivityService.shared?.send(.discard(activeWorkoutId: marker.activeWorkoutId))
            clearState()
        case .giveUp:
            clearState()
        }
    }

    private func discardLocalBackend() async {
#if !targetEnvironment(macCatalyst)
        if #available(iOS 26.0, *), let session = backend as? LiveWorkoutSession {
            await session.discard()
        }
#endif
        backend = nil
    }

    // MARK: - Prive

    private func receive(_ statistics: LiveWorkoutStatistics) {
        guard isActive else { return }
        if let bpm = statistics.latestHeartRate, bpm.isFinite, SessionCardio.heartRateRange.contains(bpm) {
            heartRate = bpm.rounded()
        } else {
            heartRate = nil
        }
        activeEnergyKilocalories = statistics.cardio.activeEnergyKilocalories
    }

#if !targetEnvironment(macCatalyst)
    @available(iOS 26.0, *)
    private func finish(
        _ session: LiveWorkoutSession,
        completedSessionId: UUID,
        in context: ModelContext,
        store: HealthStoring
    ) async {
        let descriptor = FetchDescriptor<CompletedSession>(predicate: #Predicate { $0.id == completedSessionId })
        guard let completed = try? context.fetch(descriptor).first,
              LiveWorkoutRecovery.shouldSave(durationSeconds: completed.durationSeconds) else {
            // Seance trop courte ou introuvable : rien n'est enregistre.
            await session.discard()
            return
        }
        do {
            guard let result = try await session.finish(at: completed.date, sessionId: completedSessionId) else {
                return
            }
            await HealthSyncService.attachLiveWorkout(
                identifier: result.workoutIdentifier,
                to: completedSessionId,
                cardio: result.cardio,
                in: context,
                store: store
            )
        } catch {
            DiagnosticsCenter.record(.health, code: "health.live.finishFailed", error: error)
        }
    }
#endif

    private func clearState() {
        backend = nil
        mirroredSession = nil
        isHostedByWatch = false
        activeWorkoutId = nil
        marker = nil
        isActive = false
        isPaused = false
        heartRate = nil
        activeEnergyKilocalories = nil
    }
}

#if !targetEnvironment(macCatalyst)
extension LiveHealthWorkoutController {
    /// Magasin dedie au lancement de la montre et aux seances reflechies.
    fileprivate static let mirroringStore = HKHealthStore()
}
#endif

/// Seance reflechie recue hors de l'acteur principal. `HKWorkoutSession`
/// n'est pas `Sendable` ; elle n'est que retenue, jamais manipulee.
private final class MirroredSessionBox: @unchecked Sendable {
    let session: AnyObject

    init(session: AnyObject) {
        self.session = session
    }
}

/// Statistiques d'une seance en direct, extraites hors de l'acteur
/// principal.
struct LiveWorkoutStatistics: Sendable {
    var latestHeartRate: Double?
    var cardio: SessionCardio
}

#if !targetEnvironment(macCatalyst)

/// Enveloppe d'un `HKWorkoutSession` et de son constructeur. Les objets
/// HealthKit restent dans cette classe ; seules des valeurs (nombres,
/// identifiants) en sortent.
@available(iOS 26.0, *)
private final class LiveWorkoutSession: NSObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate, @unchecked Sendable {
    private static let healthStore = HKHealthStore()
    private static let beatsPerMinute = HKUnit.count().unitDivided(by: .minute())

    private let session: HKWorkoutSession
    private let builder: HKLiveWorkoutBuilder
    private let onUpdate: @Sendable (LiveWorkoutStatistics) -> Void

    private static var configuration: HKWorkoutConfiguration {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        return configuration
    }

    convenience init(onUpdate: @escaping @Sendable (LiveWorkoutStatistics) -> Void) throws {
        let session = try HKWorkoutSession(healthStore: Self.healthStore, configuration: Self.configuration)
        self.init(session: session, onUpdate: onUpdate)
    }

    private init(session: HKWorkoutSession, onUpdate: @escaping @Sendable (LiveWorkoutStatistics) -> Void) {
        self.session = session
        self.builder = session.associatedWorkoutBuilder()
        self.onUpdate = onUpdate
        super.init()
        builder.dataSource = HKLiveWorkoutDataSource(
            healthStore: Self.healthStore,
            workoutConfiguration: session.workoutConfiguration
        )
        session.delegate = self
        builder.delegate = self
    }

    /// Seance laissee ouverte par un arret brutal de l'application.
    static func recover(onUpdate: @escaping @Sendable (LiveWorkoutStatistics) -> Void) async throws -> LiveWorkoutSession? {
        guard let session = try await healthStore.recoverActiveWorkoutSession() else { return nil }
        return LiveWorkoutSession(session: session, onUpdate: onUpdate)
    }

    func begin(at date: Date) async throws {
        session.prepare()
        session.startActivity(with: date)
        try await builder.beginCollection(at: date)
    }

    func pause() { session.pause() }
    func resume() { session.resume() }

    /// Termine et enregistre l'entrainement. `nil` = rien n'a ete cree.
    func finish(at end: Date, sessionId: UUID) async throws -> (workoutIdentifier: String, cardio: SessionCardio)? {
        let endDate = max(end, builder.startDate ?? end)
        session.end()
        try await builder.endCollection(at: endDate)
        // L'identifiant de la seance Muscu voyage avec l'entrainement, comme
        // pour une ecriture apres coup.
        try await builder.addMetadata([HKMetadataKeyExternalUUID: sessionId.uuidString])
        let cardio = statistics().cardio
        guard let workout = try await builder.finishWorkout() else { return nil }
        return (workout.uuid.uuidString, cardio)
    }

    func discard() async {
        session.end()
        builder.discardWorkout()
    }

    private func statistics() -> LiveWorkoutStatistics {
        let heartRate = builder.statistics(for: HKQuantityType(.heartRate))
        let energy = builder.statistics(for: HKQuantityType(.activeEnergyBurned))
        return LiveWorkoutStatistics(
            latestHeartRate: heartRate?.mostRecentQuantity()?.doubleValue(for: Self.beatsPerMinute),
            cardio: SessionCardio(
                averageHeartRate: heartRate?.averageQuantity()?.doubleValue(for: Self.beatsPerMinute),
                minimumHeartRate: heartRate?.minimumQuantity()?.doubleValue(for: Self.beatsPerMinute),
                maximumHeartRate: heartRate?.maximumQuantity()?.doubleValue(for: Self.beatsPerMinute),
                activeEnergyKilocalories: energy?.sumQuantity()?.doubleValue(for: .kilocalorie())
            )
        )
    }

    // MARK: - HKLiveWorkoutBuilderDelegate

    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        onUpdate(statistics())
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    // MARK: - HKWorkoutSessionDelegate

    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {}

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            DiagnosticsCenter.record(.health, code: "health.live.sessionFailed", error: error)
        }
    }
}

#endif
