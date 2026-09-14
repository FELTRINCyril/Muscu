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
            return "L’app Santé n’est pas disponible sur cet appareil. Muscu fonctionne normalement sans."
        case .notAuthorized:
            return "L’accès à Santé n’a pas été accordé. Muscu fonctionne normalement sans."
        case .writeFailed(let detail):
            return "Écriture dans Santé impossible : \(detail)"
        case .notFound:
            return "L’entraînement n’existe plus dans Santé."
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
    func readBodyweightSamples(since: Date) async throws -> [HealthBodyweightSample]
    func writeBodyweight(kilograms: Double, date: Date) async throws
}

/// Implementation HealthKit.
final class HealthKitStore: HealthStoring, @unchecked Sendable {
    private let store = HKHealthStore()

    private var workoutType: HKObjectType { HKObjectType.workoutType() }
    private var bodyMassType: HKQuantityType { HKQuantityType(.bodyMass) }
    private var activeEnergyType: HKQuantityType { HKQuantityType(.activeEnergyBurned) }

    private var typesToShare: Set<HKSampleType> {
        [HKObjectType.workoutType(), bodyMassType, activeEnergyType]
    }

    private var typesToRead: Set<HKObjectType> {
        [HKObjectType.workoutType(), bodyMassType]
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
        guard let uuid = UUID(uuidString: identifier) else { throw HealthStoreError.notFound }

        let predicate = HKQuery.predicateForObject(with: uuid)
        let workouts: [HKSample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: samples ?? []) }
            }
            store.execute(query)
        }

        guard let workout = workouts.first else { throw HealthStoreError.notFound }
        try await store.delete(workout)
    }

    func readBodyweightSamples(since: Date) async throws -> [HealthBodyweightSample] {
        guard isAvailable else { throw HealthStoreError.unavailable }

        let predicate = HKQuery.predicateForSamples(withStart: since, end: nil)
        let samples: [HKSample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: bodyMassType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: samples ?? []) }
            }
            store.execute(query)
        }

        let bundleIdentifier = Bundle.main.bundleIdentifier
        return samples.compactMap { sample in
            guard let quantity = sample as? HKQuantitySample else { return nil }
            return HealthBodyweightSample(
                kilograms: quantity.quantity.doubleValue(for: .gramUnit(with: .kilo)),
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
    private var bodyweights: [HealthBodyweightSample] = []

    var isAvailable: Bool
    var answerOnRequest: HealthAuthorization = .authorized
    private(set) var authorizationRequestCount = 0
    /// Erreur a lever a la prochaine ecriture, pour tester les echecs.
    var nextWriteError: HealthStoreError?

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
            let identifier = "hk-\(workouts.count + 1)"
            workouts[identifier] = (sessionId, start, durationSeconds)
            return identifier
        }
    }

    func deleteWorkout(identifier: String) async throws {
        try lock.withLock {
            guard workouts.removeValue(forKey: identifier) != nil else { throw HealthStoreError.notFound }
        }
    }

    func readBodyweightSamples(since: Date) async throws -> [HealthBodyweightSample] {
        lock.withLock { bodyweights.filter { $0.date >= since } }
    }

    func writeBodyweight(kilograms: Double, date: Date) async throws {
        try lock.withLock {
            guard status == .authorized else { throw HealthStoreError.notAuthorized }
            bodyweights.append(HealthBodyweightSample(kilograms: kilograms, date: date, isFromThisApp: true))
        }
    }

    // MARK: - Aides de test

    func insertExternalBodyweight(kilograms: Double, date: Date) {
        lock.withLock {
            bodyweights.append(HealthBodyweightSample(kilograms: kilograms, date: date, isFromThisApp: false))
        }
    }

    var writtenWorkoutIdentifiers: [String] { lock.withLock { workouts.keys.sorted() } }

    func containsWorkout(for sessionId: UUID) -> Bool {
        lock.withLock { workouts.values.contains { $0.sessionId == sessionId } }
    }
}
