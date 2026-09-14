import Foundation
import SwiftData
import MuscuEngine

/// Réglages Santé. Comme pour l'IA, ce sont des préférences, pas des données
/// d'entraînement : elles vivent hors du modèle.
@MainActor
enum HealthSettings {
    private enum Key {
        static let enabled = "health.enabled"
        static let writesWorkouts = "health.writesWorkouts"
        static let sharesBodyweight = "health.sharesBodyweight"
        static let lastImport = "health.lastImport"
    }

    /// Désactivé par défaut : aucune autorisation n'est demandée tant que
    /// l'utilisateur n'a pas activé la fonction lui-même.
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Key.enabled) }
        set { UserDefaults.standard.set(newValue, forKey: Key.enabled) }
    }

    static var writesWorkouts: Bool {
        get { UserDefaults.standard.object(forKey: Key.writesWorkouts) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Key.writesWorkouts) }
    }

    static var sharesBodyweight: Bool {
        get { UserDefaults.standard.object(forKey: Key.sharesBodyweight) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: Key.sharesBodyweight) }
    }

    static var lastImportDate: Date? {
        get { UserDefaults.standard.object(forKey: Key.lastImport) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: Key.lastImport) }
    }

    static func reset() {
        let defaults = UserDefaults.standard
        for key in [Key.enabled, Key.writesWorkouts, Key.sharesBodyweight, Key.lastImport] {
            defaults.removeObject(forKey: key)
        }
    }
}

struct HealthSyncOutcome: Equatable, Sendable {
    var written: Int = 0
    var deleted: Int = 0
    var alreadyWritten: Int = 0
    var importedMeasurements: Int = 0
    var failures: [String] = []
    var authorization: HealthAuthorization = .notDetermined

    var summary: String {
        guard authorization == .authorized else {
            return String(localized: "Santé n’est pas autorisée : rien n’a été partagé.")
        }
        return String(localized: "\(written) séance(s) ajoutée(s), \(deleted) retirée(s), \(alreadyWritten) déjà présente(s), \(importedMeasurements) mesure(s) importée(s).")
    }
}

/// Synchronisation avec l'app Santé.
///
/// Deux garanties portées ici : une séance n'est écrite qu'une fois, quel que
/// soit le nombre de passages ; et un refus d'autorisation ne bloque ni
/// n'altère rien — l'application continue exactement comme avant.
@MainActor
enum HealthSyncService {
    /// Fenêtre de relecture du poids. Au-delà, ce sont des mesures anciennes
    /// que l'utilisateur n'attend plus.
    static let bodyweightLookbackDays = 90

    static func links(in context: ModelContext) -> [HealthWorkoutLink] {
        (try? context.fetch(FetchDescriptor<HealthWorkoutLink>())) ?? []
    }

    /// Active Santé : demande l'autorisation, puis synchronise.
    /// C'est la SEULE porte qui déclenche la demande système.
    static func enable(
        in context: ModelContext,
        store: HealthStoring,
        now: Date = .now
    ) async -> HealthSyncOutcome {
        guard store.isAvailable else {
            HealthSettings.isEnabled = false
            return HealthSyncOutcome(authorization: .unavailable)
        }

        var status = store.authorizationStatus()
        if status == .notDetermined {
            status = await store.requestAuthorization()
        }

        guard status == .authorized else {
            // Un refus n'active rien et ne supprime rien.
            HealthSettings.isEnabled = false
            return HealthSyncOutcome(authorization: status)
        }

        HealthSettings.isEnabled = true
        return await synchronize(in: context, store: store, now: now)
    }

    static func disable() {
        // On ne retire PAS les entraînements déjà écrits : ils appartiennent
        // à l'app Santé, et les effacer sans le demander serait une perte de
        // données décidée à la place de l'utilisateur.
        HealthSettings.isEnabled = false
    }

    /// Applique le plan de synchronisation.
    @discardableResult
    static func synchronize(
        in context: ModelContext,
        store: HealthStoring,
        now: Date = .now
    ) async -> HealthSyncOutcome {
        var outcome = HealthSyncOutcome(authorization: store.authorizationStatus())

        guard HealthSettings.isEnabled, outcome.authorization == .authorized else { return outcome }

        if HealthSettings.writesWorkouts {
            outcome = await synchronizeWorkouts(in: context, store: store, outcome: outcome, now: now)
        }
        if HealthSettings.sharesBodyweight {
            outcome = await importBodyweight(in: context, store: store, outcome: outcome, now: now)
        }
        return outcome
    }

    private static func synchronizeWorkouts(
        in context: ModelContext,
        store: HealthStoring,
        outcome: HealthSyncOutcome,
        now: Date
    ) async -> HealthSyncOutcome {
        var outcome = outcome
        let sessions = (try? context.fetch(FetchDescriptor<CompletedSession>())) ?? []
        let existingLinks = links(in: context)

        let plan = HealthSyncPlanner.plan(
            sessions: sessions.map {
                HealthSyncSession(
                    id: $0.id,
                    startDate: $0.date,
                    durationSeconds: $0.durationSeconds,
                    isDeleted: $0.deletedAt != nil
                )
            },
            links: existingLinks.map {
                HealthSyncLink(
                    completedSessionId: $0.completedSessionId,
                    workoutIdentifier: $0.healthKitWorkoutIdentifier,
                    isDeleted: $0.deletedAt != nil
                )
            }
        )
        outcome.alreadyWritten = plan.alreadyWritten.count

        for session in plan.toWrite {
            do {
                let identifier = try await store.writeWorkout(
                    sessionId: session.id,
                    start: session.startDate,
                    durationSeconds: session.durationSeconds,
                    energyKilocalories: session.activeEnergyKilocalories
                )
                context.insert(HealthWorkoutLink(
                    completedSessionId: session.id,
                    healthKitWorkoutIdentifier: identifier,
                    writtenAt: now
                ))
                outcome.written += 1
            } catch {
                // Un échec sur une séance n'interrompt pas les autres, et ne
                // laisse jamais de lien vers un entraînement inexistant.
                outcome.failures.append(error.localizedDescription)
                DiagnosticsCenter.record(.health, code: "health.workout.writeFailed", error: error)
            }
        }

        for identifier in plan.toDelete {
            do {
                try await store.deleteWorkout(identifier: identifier)
                outcome.deleted += 1
            } catch {
                outcome.failures.append(error.localizedDescription)
                DiagnosticsCenter.record(.health, code: "health.workout.deleteFailed", error: error)
            }
            // Le lien est retiré même si l'entraînement avait déjà disparu :
            // le garder ferait croire à un doublon protégé.
            for link in existingLinks where link.healthKitWorkoutIdentifier == identifier {
                link.deletedAt = now
                link.updatedAt = now
            }
        }

        _ = PersistenceSupport.save(context, action: "Synchronisation Santé")
        return outcome
    }

    private static func importBodyweight(
        in context: ModelContext,
        store: HealthStoring,
        outcome: HealthSyncOutcome,
        now: Date
    ) async -> HealthSyncOutcome {
        var outcome = outcome
        let since = HealthSettings.lastImportDate
            ?? Calendar.current.date(byAdding: .day, value: -bodyweightLookbackDays, to: now)
            ?? now

        do {
            let samples = try await store.readBodyweightSamples(since: since)
            let existing = ((try? context.fetch(FetchDescriptor<BodyMeasurement>())) ?? [])
                .filter { $0.deletedAt == nil && $0.kindRaw == BodyMeasurementKind.bodyweight.rawValue }
                .map { (kilograms: $0.value, date: $0.measuredAt) }

            let fresh = HealthBodyweightImporter.newSamples(samples, existing: existing)
            for sample in fresh {
                context.insert(BodyMeasurement(
                    kindRaw: BodyMeasurementKind.bodyweight.rawValue,
                    measuredAt: sample.date,
                    value: sample.kilograms,
                    sourceRaw: MeasurementSource.healthKit.rawValue
                ))
                outcome.importedMeasurements += 1
            }

            HealthSettings.lastImportDate = now
            _ = PersistenceSupport.save(context, action: "Import du poids depuis Santé")
        } catch {
            outcome.failures.append(error.localizedDescription)
            DiagnosticsCenter.record(.health, code: "health.bodyweight.importFailed", error: error)
        }
        return outcome
    }

    /// Écrit une pesée saisie dans Muscu vers Santé, si l'utilisateur l'a
    /// autorisé. Un échec n'empêche jamais l'enregistrement local.
    static func exportBodyweight(
        kilograms: Double,
        date: Date,
        store: HealthStoring
    ) async {
        guard HealthSettings.isEnabled, HealthSettings.sharesBodyweight else { return }
        guard store.authorizationStatus() == .authorized else { return }
        try? await store.writeBodyweight(kilograms: kilograms, date: date)
    }
}
