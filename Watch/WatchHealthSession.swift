import Foundation
import HealthKit
import Observation

/// Seance Sante au poignet : `HKWorkoutSession` + `HKLiveWorkoutBuilder`.
///
/// Elle ne demarre que pour une seance que l'iPhone a confiee a la montre
/// (decision 0017), ou pour une seance faite a la montre seule quand Sante
/// est active dans Muscu. Jamais deux a la fois : HealthKit n'en autorise
/// qu'une, et l'iPhone n'en demarre pas quand la montre est l'hote.
///
/// Pendant la seance, watchOS garde l'application active en arriere-plan
/// (mode « workout-processing ») : le repos peut vibrer poignet baisse.
///
/// Inspire d'Ischys (`WorkoutManager.swift`, licence MIT, voir
/// THIRD_PARTY_NOTICES.md), adapte : rattachement a la seance Muscu,
/// identifiant de la seance dans les metadonnees, fin decidee par l'iPhone.
@MainActor
@Observable
final class WatchHealthSession {
    static let shared = WatchHealthSession()

    /// Seance Muscu suivie : seance en cours sur l'iPhone, ou identifiant
    /// de la seance faite a la montre seule. `nil` tant qu'une seance lancee
    /// par l'iPhone n'est pas encore rattachee.
    private(set) var workoutId: UUID?
    private(set) var isRecording = false
    private(set) var isPaused = false
    private(set) var startDate: Date?
    /// Derniere frequence cardiaque. `nil` = aucune mesure : rien n'est
    /// affiche plutot qu'un « 0 » mensonger.
    private(set) var heartRate: Double?
    private(set) var activeEnergyKilocalories: Double?
    private(set) var lastError: String?

    /// Seances terminees ou abandonnees ici : un etat en retard ne les
    /// redemarre jamais.
    private(set) var closedWorkoutIds: Set<UUID> = []

    @ObservationIgnored private var engine: WatchWorkoutEngine?
    @ObservationIgnored private var orphanTask: Task<Void, Never>?
    /// Un demarrage est en cours (autorisation, debut de collecte) : un
    /// second demarrage ne doit jamais creer une seconde seance.
    @ObservationIgnored private var isStarting = false
    /// Seance Muscu annoncee pendant ce demarrage, a rattacher ensuite.
    @ObservationIgnored private var pendingWorkoutId: UUID?

    private static let store = HKHealthStore()
    private static let workoutIdKey = "watch.health.workoutId"

    private init() {}

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    // MARK: - Autorisation

    /// Demande l'autorisation au moment ou une seance demarre — jamais au
    /// lancement (decision 0009). Sans reponse positive, la seance continue
    /// sans Sante.
    func requestAuthorization() async -> Bool {
        guard Self.isAvailable else { return false }
        let share: Set<HKSampleType> = [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned)]
        let read: Set<HKObjectType> = [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)]
        do {
            try await Self.store.requestAuthorization(toShare: share, read: read)
        } catch {
            return false
        }
        return Self.store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
    }

    // MARK: - Cycle de vie

    /// Demarre la seance Sante de la seance `workoutId`.
    @discardableResult
    func start(workoutId: UUID?, mirrorToPhone: Bool) async -> Bool {
        guard !isRecording, Self.isAvailable else { return false }
        if let workoutId, closedWorkoutIds.contains(workoutId) { return false }
        guard !isStarting else {
            // Lancee par l'iPhone et deja en cours de demarrage : la seance
            // annoncee y sera rattachee.
            if let workoutId { pendingWorkoutId = workoutId }
            return false
        }
        isStarting = true
        defer { isStarting = false }
        guard await requestAuthorization() else {
            lastError = String(localized: "Santé n’est pas autorisée sur la montre : la séance continue sans fréquence cardiaque.")
            return false
        }
        // Une autre demande a pu aboutir pendant l'autorisation.
        guard !isRecording else { return false }
        do {
            let engine = try WatchWorkoutEngine(store: Self.store, onUpdate: { heartRate, energy in
                Task { @MainActor in WatchHealthSession.shared.receive(heartRate: heartRate, energy: energy) }
            })
            let start = Date.now
            try await engine.begin(at: start)
            self.engine = engine
            adopt(workoutId: workoutId ?? pendingWorkoutId, start: start)
            pendingWorkoutId = nil
            if mirrorToPhone { await engine.mirrorToPhone() }
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// L'iPhone a lance la montre dans une seance (`startWatchApp`) : on
    /// demarre tout de suite, et on rattache la seance Muscu des que l'etat
    /// de l'iPhone arrive. Sans rattachement sous deux minutes, la seance
    /// n'est pas enregistree.
    func startLaunchedByPhone() async {
        guard !isRecording else { return }
        guard await start(workoutId: nil, mirrorToPhone: true), workoutId == nil else { return }
        orphanTask?.cancel()
        orphanTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(120))
            guard let self, !Task.isCancelled, self.isRecording, self.workoutId == nil else { return }
            await self.discard()
        }
    }

    func associate(workoutId: UUID) {
        guard isRecording, self.workoutId == nil else { return }
        self.workoutId = workoutId
        UserDefaults.standard.set(workoutId.uuidString, forKey: Self.workoutIdKey)
        orphanTask?.cancel()
    }

    func pause() {
        guard isRecording, !isPaused else { return }
        engine?.pause()
        isPaused = true
    }

    func resume() {
        guard isRecording, isPaused else { return }
        engine?.resume()
        isPaused = false
    }

    /// Termine et enregistre l'entrainement. L'identifiant de la seance
    /// Muscu voyage dans les metadonnees, comme pour une ecriture de
    /// l'iPhone. Identifiant `nil` : rien n'a ete enregistre.
    func finish(endDate: Date, externalId: UUID) async -> (identifier: String?, cardio: WatchCardio) {
        guard let engine, isRecording else { return (nil, WatchCardio()) }
        if let workoutId { closedWorkoutIds.insert(workoutId) }
        let result: (identifier: String?, cardio: WatchCardio)
        do {
            result = try await engine.finish(at: endDate, externalId: externalId)
        } catch {
            lastError = error.localizedDescription
            result = (nil, engine.cardio())
        }
        clear()
        return result
    }

    /// Abandon : rien n'est enregistre dans Sante.
    func discard() async {
        if let workoutId { closedWorkoutIds.insert(workoutId) }
        await engine?.discard()
        clear()
    }

    /// Au lancement : une seance restee ouverte par un arret brutal est
    /// rattachee si l'on sait quelle seance Muscu elle suivait, abandonnee
    /// sinon (elle garderait le capteur allume et bloquerait la suivante).
    func recover() async {
        guard engine == nil, Self.isAvailable else { return }
        guard let session = try? await Self.store.recoverActiveWorkoutSession() else { return }
        let engine = WatchWorkoutEngine(recovered: session, store: Self.store, onUpdate: { heartRate, energy in
            Task { @MainActor in WatchHealthSession.shared.receive(heartRate: heartRate, energy: energy) }
        })
        let saved = UserDefaults.standard.string(forKey: Self.workoutIdKey).flatMap(UUID.init(uuidString:))
        guard let saved else {
            await engine.discard()
            return
        }
        self.engine = engine
        adopt(workoutId: saved, start: engine.startDate ?? .now)
    }

    // MARK: - Prive

    private func adopt(workoutId: UUID?, start: Date) {
        self.workoutId = workoutId
        isRecording = true
        isPaused = false
        startDate = start
        heartRate = nil
        activeEnergyKilocalories = nil
        lastError = nil
        if let workoutId {
            UserDefaults.standard.set(workoutId.uuidString, forKey: Self.workoutIdKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.workoutIdKey)
        }
    }

    private func receive(heartRate: Double?, energy: Double?) {
        guard isRecording else { return }
        if let heartRate, heartRate.isFinite, (20...300).contains(heartRate) {
            self.heartRate = heartRate.rounded()
        }
        if let energy, energy.isFinite, energy >= 0 {
            activeEnergyKilocalories = energy.rounded()
        }
        WatchConnectivityService.shared?.sendMetrics()
    }

    private func clear() {
        engine = nil
        orphanTask?.cancel()
        orphanTask = nil
        workoutId = nil
        isRecording = false
        isPaused = false
        startDate = nil
        heartRate = nil
        activeEnergyKilocalories = nil
        UserDefaults.standard.removeObject(forKey: Self.workoutIdKey)
    }
}

/// Enveloppe des objets HealthKit : ils restent ici, seules des valeurs
/// (nombres, identifiants) en sortent.
private final class WatchWorkoutEngine: NSObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate, @unchecked Sendable {
    private static let beatsPerMinute = HKUnit.count().unitDivided(by: .minute())

    private let session: HKWorkoutSession
    private let builder: HKLiveWorkoutBuilder
    private let onUpdate: @Sendable (Double?, Double?) -> Void

    private static var configuration: HKWorkoutConfiguration {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        return configuration
    }

    convenience init(store: HKHealthStore, onUpdate: @escaping @Sendable (Double?, Double?) -> Void) throws {
        let session = try HKWorkoutSession(healthStore: store, configuration: Self.configuration)
        self.init(recovered: session, store: store, onUpdate: onUpdate)
    }

    init(recovered session: HKWorkoutSession, store: HKHealthStore, onUpdate: @escaping @Sendable (Double?, Double?) -> Void) {
        self.session = session
        self.builder = session.associatedWorkoutBuilder()
        self.onUpdate = onUpdate
        super.init()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: session.workoutConfiguration)
        session.delegate = self
        builder.delegate = self
    }

    var startDate: Date? { builder.startDate }

    func begin(at date: Date) async throws {
        session.prepare()
        session.startActivity(with: date)
        try await builder.beginCollection(at: date)
    }

    /// Partage la seance avec l'iPhone (iOS 17+) : il la voit comme
    /// tenue par la montre. Sans iPhone joignable, la seance continue.
    func mirrorToPhone() async {
        try? await session.startMirroringToCompanionDevice()
    }

    func pause() { session.pause() }
    func resume() { session.resume() }

    func finish(at end: Date, externalId: UUID) async throws -> (identifier: String?, cardio: WatchCardio) {
        let endDate = max(end, builder.startDate ?? end)
        session.end()
        try await builder.endCollection(at: endDate)
        try await builder.addMetadata([HKMetadataKeyExternalUUID: externalId.uuidString])
        let cardio = cardio()
        guard let workout = try await builder.finishWorkout() else { return (nil, cardio) }
        return (workout.uuid.uuidString, cardio)
    }

    func discard() async {
        session.end()
        builder.discardWorkout()
    }

    func cardio() -> WatchCardio {
        let heartRate = builder.statistics(for: HKQuantityType(.heartRate))
        let energy = builder.statistics(for: HKQuantityType(.activeEnergyBurned))
        return WatchCardio(
            averageHeartRate: heartRate?.averageQuantity()?.doubleValue(for: Self.beatsPerMinute),
            minimumHeartRate: heartRate?.minimumQuantity()?.doubleValue(for: Self.beatsPerMinute),
            maximumHeartRate: heartRate?.maximumQuantity()?.doubleValue(for: Self.beatsPerMinute),
            activeEnergyKilocalories: energy?.sumQuantity()?.doubleValue(for: .kilocalorie())
        )
    }

    // MARK: - HKLiveWorkoutBuilderDelegate

    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let heartRate = workoutBuilder.statistics(for: HKQuantityType(.heartRate))?
            .mostRecentQuantity()?.doubleValue(for: Self.beatsPerMinute)
        let energy = workoutBuilder.statistics(for: HKQuantityType(.activeEnergyBurned))?
            .sumQuantity()?.doubleValue(for: .kilocalorie())
        onUpdate(heartRate, energy)
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    // MARK: - HKWorkoutSessionDelegate

    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {}

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {}
}
