import Foundation
import HealthKit
import MuscuEngine

/// Etat d'autorisation Sante, reduit a ce qui change nos decisions.
enum HealthAuthorization: Equatable, Sendable {
    /// L'appareil ne donne pas acces a Sante. Ce n'est pas un refus.
    case unavailable
    case notDetermined
    case authorized
    case denied

    var canWrite: Bool { self == .authorized }
}

/// Erreurs Sante, toutes destinees a etre AFFICHEES.
enum HealthStoreError: LocalizedError, Equatable {
    case unavailable
    case notAuthorized
    case writeFailed(String)
    case notFound

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return String(localized: "L’app Santé n’est pas disponible sur cet appareil. Muscu fonctionne normalement sans.")
        case .notAuthorized:
            return String(localized: "L’accès à Santé n’a pas été accordé. Muscu fonctionne normalement sans.")
        case .writeFailed(let detail):
            return String(localized: "Écriture dans Santé impossible : \(detail)")
        case .notFound:
            return String(localized: "L’entraînement n’existe plus dans Santé.")
        }
    }
}

/// Acces a l'app Sante, abstrait pour rester testable sans appareil.
protocol HealthStoring: AnyObject, Sendable {
    var isAvailable: Bool { get }
    func authorizationStatus() -> HealthAuthorization
    /// Demande l'autorisation. Appelee UNIQUEMENT apres que l'utilisateur a
    /// activé la fonction et lu ce qui sera partagé.
    func requestAuthorization() async -> HealthAuthorization

    func writeWorkout(
        sessionId: UUID,
        start: Date,
        durationSeconds: Int,
        energyKilocalories: Double?
    ) async throws -> String

    func deleteWorkout(identifier: String) async throws
    func writeBodyweight(kilograms: Double, date: Date) async throws

    // MARK: Lot 5

    /// Des types ajoutes depuis la derniere autorisation (cardio, effort,
    /// mesures) n'ont jamais ete presentes a l'utilisateur. Ne demande rien.
    func needsAuthorizationRequest() async -> Bool
    /// L'ecriture de la note d'effort est-elle autorisee ? Elle peut etre
    /// refusee seule, type par type, dans la feuille systeme.
    var canWriteWorkoutEffort: Bool { get }
    /// Relie une note d'effort (echelle Sante 1-10) a un entrainement.
    /// Retourne l'identifiant de l'echantillon cree.
    func writeWorkoutEffort(score: Double, workoutIdentifier: String) async throws -> String
    func deleteWorkoutEffort(sampleIdentifier: String) async throws
    /// Frequence cardiaque et energie active enregistrees dans Sante sur un
    /// intervalle. Une lecture refusee ressemble a une absence de donnees :
    /// HealthKit ne dit jamais si la lecture est autorisee.
    func readCardio(start: Date, end: Date) async throws -> HealthCardioReading
    func readMeasurementSamples(kind: HealthMeasurementKind, since: Date) async throws -> [HealthMeasurementSample]
}

/// Echantillons bruts du cardio d'une seance.
struct HealthCardioReading: Equatable, Sendable {
    var heartRates: [Double] = []
    var activeEnergyKilocalories: Double?

    var cardio: SessionCardio {
        SessionCardio.from(heartRates: heartRates, activeEnergyKilocalories: activeEnergyKilocalories)
    }
}

/// Implementation HealthKit.
final class HealthKitStore: HealthStoring, @unchecked Sendable {
    private let store = HKHealthStore()

    private var workoutType: HKObjectType { HKObjectType.workoutType() }
    private var bodyMassType: HKQuantityType { HKQuantityType(.bodyMass) }
    private var activeEnergyType: HKQuantityType { HKQuantityType(.activeEnergyBurned) }

    private var heartRateType: HKQuantityType { HKQuantityType(.heartRate) }
    private var effortType: HKQuantityType { HKQuantityType(.workoutEffortScore) }
    private static let beatsPerMinute = HKUnit.count().unitDivided(by: .minute())

    /// Ecritures : entrainements, poids (si active), energie et frequence
    /// cardiaque mesurees pendant une seance en direct (par un capteur
    /// connecte), note d'effort. Rien d'autre.
    private var typesToShare: Set<HKSampleType> {
        [HKObjectType.workoutType(), bodyMassType, activeEnergyType, heartRateType, effortType]
    }

    /// Lectures : entrainements, poids, masse grasse, tour de taille,
    /// frequence cardiaque et energie active. Ni sommeil, ni pas, ni
    /// activite hors des seances.
    private var typesToRead: Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKObjectType.workoutType(), heartRateType, activeEnergyType]
        for kind in HealthMeasurementKind.allCases { types.insert(Self.quantityType(for: kind)) }
        return types
    }

    private static func quantityType(for kind: HealthMeasurementKind) -> HKQuantityType {
        switch kind {
        case .bodyweight: return HKQuantityType(.bodyMass)
        case .bodyFatPercent: return HKQuantityType(.bodyFatPercentage)
        case .waist: return HKQuantityType(.waistCircumference)
        }
    }

    /// Valeur dans l'unite canonique de Muscu : kg, % (Sante stocke une
    /// fraction), cm.
    private static func canonicalValue(of quantity: HKQuantity, kind: HealthMeasurementKind) -> Double {
        switch kind {
        case .bodyweight: return quantity.doubleValue(for: .gramUnit(with: .kilo))
        case .bodyFatPercent: return quantity.doubleValue(for: .percent()) * 100
        case .waist: return quantity.doubleValue(for: .meterUnit(with: .centi))
        }
    }

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func authorizationStatus() -> HealthAuthorization {
        guard isAvailable else { return .unavailable }
        switch store.authorizationStatus(for: workoutType) {
        case .sharingAuthorized: return .authorized
        case .sharingDenied: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    func requestAuthorization() async -> HealthAuthorization {
        guard isAvailable else { return .unavailable }
        do {
            try await store.requestAuthorization(toShare: typesToShare, read: typesToRead)
            return authorizationStatus()
        } catch {
            return .denied
        }
    }

    func writeWorkout(
        sessionId: UUID,
        start: Date,
        durationSeconds: Int,
        energyKilocalories: Double?
    ) async throws -> String {
        guard isAvailable else { throw HealthStoreError.unavailable }
        guard authorizationStatus() == .authorized else { throw HealthStoreError.notAuthorized }

        let end = start.addingTimeInterval(TimeInterval(durationSeconds))
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining

        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        do {
            try await builder.beginCollection(at: start)

            // L'identifiant de la seance Muscu voyage avec l'entrainement :
            // meme si notre lien local disparaissait, l'origine reste lisible
            // dans Sante.
            try await builder.addMetadata([
                HKMetadataKeyExternalUUID: sessionId.uuidString,
                HKMetadataKeyWasUserEntered: true,
            ])

            if let energyKilocalories, energyKilocalories > 0 {
                let sample = HKQuantitySample(
                    type: activeEnergyType,
                    quantity: HKQuantity(unit: .kilocalorie(), doubleValue: energyKilocalories),
                    start: start,
                    end: end
                )
                try await builder.addSamples([sample])
            }

            try await builder.endCollection(at: end)
            guard let workout = try await builder.finishWorkout() else {
                throw HealthStoreError.writeFailed("l’entraînement n’a pas été créé")
            }
            return workout.uuid.uuidString
        } catch let error as HealthStoreError {
            throw error
        } catch {
            throw HealthStoreError.writeFailed(error.localizedDescription)
        }
    }

    func deleteWorkout(identifier: String) async throws {
        guard isAvailable else { throw HealthStoreError.unavailable }
        guard let workout = try await workout(identifier: identifier) else { throw HealthStoreError.notFound }
        try await store.delete(workout)
    }

    private func workout(identifier: String) async throws -> HKWorkout? {
        guard let uuid = UUID(uuidString: identifier) else { return nil }
        return try await samples(of: HKObjectType.workoutType(), predicate: HKQuery.predicateForObject(with: uuid), limit: 1)
            .first as? HKWorkout
    }

    private func samples(
        of type: HKSampleType,
        predicate: NSPredicate?,
        limit: Int = HKObjectQueryNoLimit,
        newestFirst: Bool = false
    ) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: limit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: !newestFirst)]
            ) { _, samples, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: samples ?? []) }
            }
            store.execute(query)
        }
    }

    func needsAuthorizationRequest() async -> Bool {
        guard isAvailable else { return false }
        do {
            return try await store.statusForAuthorizationRequest(toShare: typesToShare, read: typesToRead) == .shouldRequest
        } catch {
            return false
        }
    }

    var canWriteWorkoutEffort: Bool {
        isAvailable && store.authorizationStatus(for: effortType) == .sharingAuthorized
    }

    func writeWorkoutEffort(score: Double, workoutIdentifier: String) async throws -> String {
        guard isAvailable else { throw HealthStoreError.unavailable }
        guard canWriteWorkoutEffort else { throw HealthStoreError.notAuthorized }
        guard let workout = try await workout(identifier: workoutIdentifier) else { throw HealthStoreError.notFound }

        let sample = HKQuantitySample(
            type: effortType,
            quantity: HKQuantity(unit: .appleEffortScore(), doubleValue: score),
            start: workout.startDate,
            end: workout.endDate,
            metadata: [HKMetadataKeyWasUserEntered: true]
        )
        do {
            _ = try await store.relateWorkoutEffortSample(sample, with: workout, activity: nil)
            return sample.uuid.uuidString
        } catch {
            throw HealthStoreError.writeFailed(error.localizedDescription)
        }
    }

    func deleteWorkoutEffort(sampleIdentifier: String) async throws {
        guard isAvailable else { throw HealthStoreError.unavailable }
        guard let uuid = UUID(uuidString: sampleIdentifier),
              let sample = try await samples(of: effortType, predicate: HKQuery.predicateForObject(with: uuid), limit: 1).first
        else { throw HealthStoreError.notFound }
        try await store.delete(sample)
    }

    func readCardio(start: Date, end: Date) async throws -> HealthCardioReading {
        guard isAvailable else { throw HealthStoreError.unavailable }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        let heartRates = try await samples(of: heartRateType, predicate: predicate).compactMap { sample in
            (sample as? HKQuantitySample)?.quantity.doubleValue(for: Self.beatsPerMinute)
        }
        let energy: Double? = try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: activeEnergyType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error = error as? HKError, error.code == .errorNoData {
                    continuation.resume(returning: nil)
                } else if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: statistics?.sumQuantity()?.doubleValue(for: .kilocalorie()))
                }
            }
            store.execute(query)
        }
        return HealthCardioReading(heartRates: heartRates, activeEnergyKilocalories: energy)
    }

    func readMeasurementSamples(kind: HealthMeasurementKind, since: Date) async throws -> [HealthMeasurementSample] {
        guard isAvailable else { throw HealthStoreError.unavailable }

        let predicate = HKQuery.predicateForSamples(withStart: since, end: nil)
        let samples = try await samples(of: Self.quantityType(for: kind), predicate: predicate, newestFirst: true)

        let bundleIdentifier = Bundle.main.bundleIdentifier
        return samples.compactMap { sample in
            guard let quantity = sample as? HKQuantitySample else { return nil }
            return HealthMeasurementSample(
                sampleIdentifier: quantity.uuid.uuidString,
                kind: kind,
                value: Self.canonicalValue(of: quantity.quantity, kind: kind),
                date: quantity.startDate,
                isFromThisApp: quantity.sourceRevision.source.bundleIdentifier == bundleIdentifier
            )
        }
    }

    func writeBodyweight(kilograms: Double, date: Date) async throws {
        guard isAvailable else { throw HealthStoreError.unavailable }
        guard authorizationStatus() == .authorized else { throw HealthStoreError.notAuthorized }

        let sample = HKQuantitySample(
            type: bodyMassType,
            quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kilograms),
            start: date,
            end: date,
            metadata: [HKMetadataKeyWasUserEntered: true]
        )
        do {
            try await store.save(sample)
        } catch {
            throw HealthStoreError.writeFailed(error.localizedDescription)
        }
    }
}

/// Double en memoire : les tests ne touchent jamais l'app Sante.
final class InMemoryHealthStore: HealthStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var status: HealthAuthorization
    private var workouts: [String: (sessionId: UUID, start: Date, duration: Int)] = [:]
    private var measurements: [HealthMeasurementSample] = []
    private var efforts: [String: (workout: String, score: Double)] = [:]
    private var cardioReadings: [(start: Date, end: Date, reading: HealthCardioReading)] = []
    private var sampleCounter = 0
    private var workoutCounter = 0

    var isAvailable: Bool
    var answerOnRequest: HealthAuthorization = .authorized
    private(set) var authorizationRequestCount = 0
    /// Erreur a lever a la prochaine ecriture, pour tester les echecs.
    var nextWriteError: HealthStoreError?
    /// Types ajoutes depuis la derniere autorisation, encore a demander.
    var hasPendingTypes = false
    var effortAllowed = true

    init(status: HealthAuthorization = .notDetermined, isAvailable: Bool = true) {
        self.status = status
        self.isAvailable = isAvailable
    }

    func authorizationStatus() -> HealthAuthorization {
        lock.withLock { isAvailable ? status : .unavailable }
    }

    func requestAuthorization() async -> HealthAuthorization {
        lock.withLock {
            guard isAvailable else { return .unavailable }
            authorizationRequestCount += 1
            status = answerOnRequest
            hasPendingTypes = false
            return status
        }
    }

    func writeWorkout(
        sessionId: UUID,
        start: Date,
        durationSeconds: Int,
        energyKilocalories: Double?
    ) async throws -> String {
        if let nextWriteError { throw nextWriteError }
        return try lock.withLock {
            guard isAvailable else { throw HealthStoreError.unavailable }
            guard status == .authorized else { throw HealthStoreError.notAuthorized }
            workoutCounter += 1
            let identifier = "hk-\(workoutCounter)"
            workouts[identifier] = (sessionId, start, durationSeconds)
            return identifier
        }
    }

    func deleteWorkout(identifier: String) async throws {
        try lock.withLock {
            guard workouts.removeValue(forKey: identifier) != nil else { throw HealthStoreError.notFound }
        }
    }

    func writeBodyweight(kilograms: Double, date: Date) async throws {
        try lock.withLock {
            guard status == .authorized else { throw HealthStoreError.notAuthorized }
            sampleCounter += 1
            measurements.append(HealthMeasurementSample(
                sampleIdentifier: "mine-\(sampleCounter)", kind: .bodyweight, value: kilograms, date: date, isFromThisApp: true
            ))
        }
    }

    func needsAuthorizationRequest() async -> Bool {
        lock.withLock { isAvailable && hasPendingTypes }
    }

    var canWriteWorkoutEffort: Bool {
        lock.withLock { isAvailable && status == .authorized && effortAllowed }
    }

    func writeWorkoutEffort(score: Double, workoutIdentifier: String) async throws -> String {
        try lock.withLock {
            guard status == .authorized, effortAllowed else { throw HealthStoreError.notAuthorized }
            guard workouts[workoutIdentifier] != nil else { throw HealthStoreError.notFound }
            sampleCounter += 1
            let identifier = "effort-\(sampleCounter)"
            efforts[identifier] = (workoutIdentifier, score)
            return identifier
        }
    }

    func deleteWorkoutEffort(sampleIdentifier: String) async throws {
        try lock.withLock {
            guard efforts.removeValue(forKey: sampleIdentifier) != nil else { throw HealthStoreError.notFound }
        }
    }

    func readCardio(start: Date, end: Date) async throws -> HealthCardioReading {
        lock.withLock {
            cardioReadings.first { $0.start >= start.addingTimeInterval(-1) && $0.end <= end.addingTimeInterval(1) }?.reading
                ?? HealthCardioReading()
        }
    }

    func readMeasurementSamples(kind: HealthMeasurementKind, since: Date) async throws -> [HealthMeasurementSample] {
        lock.withLock { measurements.filter { $0.kind == kind && $0.date >= since } }
    }

    // MARK: - Aides de test

    func insertExternalBodyweight(kilograms: Double, date: Date) {
        insertExternalMeasurement(.bodyweight, value: kilograms, date: date)
    }

    @discardableResult
    func insertExternalMeasurement(_ kind: HealthMeasurementKind, value: Double, date: Date, identifier: String? = nil) -> String {
        lock.withLock {
            sampleCounter += 1
            let identifier = identifier ?? "ext-\(sampleCounter)"
            measurements.append(HealthMeasurementSample(
                sampleIdentifier: identifier, kind: kind, value: value, date: date, isFromThisApp: false
            ))
            return identifier
        }
    }

    func insertCardio(_ reading: HealthCardioReading, start: Date, end: Date) {
        lock.withLock { cardioReadings.append((start, end, reading)) }
    }

    /// Entrainement deja present dans Sante (enregistre par une seance en
    /// direct), pour tester son rattachement.
    func insertWorkout(identifier: String, sessionId: UUID, start: Date, duration: Int) {
        lock.withLock { workouts[identifier] = (sessionId, start, duration) }
    }

    var bodyweightSamples: [HealthMeasurementSample] {
        lock.withLock { measurements.filter { $0.kind == .bodyweight } }
    }

    /// Notes d'effort presentes, par entrainement.
    var effortScores: [String: Double] {
        lock.withLock { Dictionary(efforts.values.map { ($0.workout, $0.score) }, uniquingKeysWith: { first, _ in first }) }
    }

    var effortSampleCount: Int { lock.withLock { efforts.count } }

    var writtenWorkoutIdentifiers: [String] { lock.withLock { workouts.keys.sorted() } }

    func containsWorkout(for sessionId: UUID) -> Bool {
        lock.withLock { workouts.values.contains { $0.sessionId == sessionId } }
    }
}
