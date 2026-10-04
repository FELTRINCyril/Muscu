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

    @ObservationIgnored private var activeWorkoutId: UUID?
    @ObservationIgnored private var backend: AnyObject?

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
    var recordingSessionIds: Set<UUID> {
        marker?.completedSessionId.map { [$0] } ?? []
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
    func start(activeWorkoutId: UUID, store: HealthStoring) async {
        if self.activeWorkoutId == activeWorkoutId, backend != nil {
            resume()
            return
        }
        // Une autre seance Sante restee ouverte : elle ne correspond plus a
        // rien, elle n'est pas enregistree.
        if backend != nil { await discard() }
        guard Self.isAllowed(store: store) else { return }

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
#if !targetEnvironment(macCatalyst)
        guard #available(iOS 26.0, *), let session = backend as? LiveWorkoutSession, !isPaused else { return }
        session.pause()
        isPaused = true
#endif
    }

    func resume() {
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
        guard backend != nil, let activeWorkoutId else { return }
        marker = LiveWorkoutMarker(activeWorkoutId: activeWorkoutId, completedSessionId: completedSessionId)
    }

    /// Termine l'enregistrement, relie l'entrainement a la seance et y
    /// range le cardio mesure. En cas d'echec, la seance redevient une
    /// seance ordinaire, ecrite apres coup.
    func finishRecording(in context: ModelContext, store: HealthStoring) async {
        guard marker?.completedSessionId != nil else { return }
#if !targetEnvironment(macCatalyst)
        if #available(iOS 26.0, *), let sessionId = marker?.completedSessionId, let session = backend as? LiveWorkoutSession {
            await finish(session, completedSessionId: sessionId, in: context, store: store)
        }
#endif
        clearState()
    }

    /// Abandon de la seance : rien n'est enregistre dans Sante.
    func discard() async {
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
        activeWorkoutId = nil
        marker = nil
        isActive = false
        isPaused = false
        heartRate = nil
        activeEnergyKilocalories = nil
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
