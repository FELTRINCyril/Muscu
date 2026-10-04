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
        static let importsBodyFat = "health.importsBodyFat"
        static let importsWaist = "health.importsWaist"
        static func lastImport(_ kind: HealthMeasurementKind) -> String {
            // Le poids garde sa cle d'origine : un import deja fait n'est
            // pas relu en entier apres la mise a jour.
            kind == .bodyweight ? lastImport : "health.lastImport.\(kind.rawValue)"
        }
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

    /// Import de la masse grasse et du tour de taille : lecture seule, jamais
    /// d'ecriture vers Sante. Desactives par defaut.
    static var importsBodyFat: Bool {
        get { UserDefaults.standard.bool(forKey: Key.importsBodyFat) }
        set { UserDefaults.standard.set(newValue, forKey: Key.importsBodyFat) }
    }

    static var importsWaist: Bool {
        get { UserDefaults.standard.bool(forKey: Key.importsWaist) }
        set { UserDefaults.standard.set(newValue, forKey: Key.importsWaist) }
    }

    /// Mesures a lire dans Sante, selon les interrupteurs.
    static var importedMeasurementKinds: [HealthMeasurementKind] {
        HealthMeasurementKind.allCases.filter { kind in
            switch kind {
            case .bodyweight: return sharesBodyweight
            case .bodyFatPercent: return importsBodyFat
            case .waist: return importsWaist
            }
        }
    }

    /// Dernier import du poids (cle historique).
    static var lastImportDate: Date? {
        get { lastImportDate(for: .bodyweight) }
        set { setLastImportDate(newValue, for: .bodyweight) }
    }

    static func lastImportDate(for kind: HealthMeasurementKind) -> Date? {
        UserDefaults.standard.object(forKey: Key.lastImport(kind)) as? Date
    }

    static func setLastImportDate(_ date: Date?, for kind: HealthMeasurementKind) {
        UserDefaults.standard.set(date, forKey: Key.lastImport(kind))
    }

    static func reset() {
        let defaults = UserDefaults.standard
        let keys = [Key.enabled, Key.writesWorkouts, Key.sharesBodyweight, Key.importsBodyFat, Key.importsWaist]
            + HealthMeasurementKind.allCases.map(Key.lastImport)
        for key in keys {
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
        // L'utilisateur vient d'activer la fonction apres avoir lu ce qui
        // sera partage : c'est le moment de presenter aussi les types
        // ajoutes depuis une autorisation plus ancienne.
        let hasNewTypes = status == .authorized ? await store.needsAuthorizationRequest() : false
        if status == .notDetermined || hasNewTypes {
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

    /// Presente les types ajoutes depuis la derniere autorisation (cardio,
    /// effort, mesures). Declenchee uniquement par un bouton explique.
    static func requestNewTypes(store: HealthStoring) async -> HealthAuthorization {
        guard store.isAvailable else { return .unavailable }
        guard await store.needsAuthorizationRequest() else { return store.authorizationStatus() }
        return await store.requestAuthorization()
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
        await backfillCardio(in: context, store: store, now: now)
        if !HealthSettings.importedMeasurementKinds.isEmpty {
            outcome = await importMeasurements(in: context, store: store, outcome: outcome, now: now)
        }
        return outcome
    }

    /// Seances dont l'entrainement est en cours d'enregistrement par une
    /// seance Sante en direct : jamais ecrites apres coup en parallele.
    private static var liveRecordingSessionIds: Set<UUID> {
        LiveHealthWorkoutController.shared.recordingSessionIds
    }

    private static func syncSession(_ session: CompletedSession) -> HealthSyncSession {
        HealthSyncSession(
            id: session.id,
            // Une seance terminee dans Muscu porte sa date de FIN :
            // l'entrainement Sante commence une duree plus tot.
            startDate: PastSessionEditor.interval(of: session).start,
            durationSeconds: session.durationSeconds,
            isDeleted: session.deletedAt != nil,
            editedAt: session.editedAt,
            effortRating: session.effortRating
        )
    }

    /// Lien d'un entrainement tout juste ecrit : il retient les horaires et
    /// la note ecrits, pour qu'une correction ulterieure sache quoi refaire.
    private static func insertLink(
        for session: HealthSyncSession,
        workoutIdentifier: String,
        source: String = "iphone",
        in context: ModelContext,
        now: Date
    ) -> HealthWorkoutLink {
        let link = HealthWorkoutLink(
            completedSessionId: session.id,
            healthKitWorkoutIdentifier: workoutIdentifier,
            writtenAt: now,
            sourceRaw: source,
            writtenStartDate: session.startDate,
            writtenDurationSeconds: session.durationSeconds
        )
        context.insert(link)
        return link
    }

    /// Ecrit la note d'effort sur l'entrainement du lien. Un refus de ce
    /// seul type n'est pas une erreur : la note reste dans Muscu.
    private static func writeEffort(
        _ rating: Int?,
        on link: HealthWorkoutLink,
        store: HealthStoring,
        outcome: inout HealthSyncOutcome
    ) async {
        guard let score = HealthEffortScore.appleEffortScore(for: rating), store.canWriteWorkoutEffort else { return }
        do {
            let sampleIdentifier = try await store.writeWorkoutEffort(score: score, workoutIdentifier: link.healthKitWorkoutIdentifier)
            link.writtenEffortRating = HealthEffortScore.validRating(rating)
            link.effortSampleIdentifier = sampleIdentifier
        } catch HealthStoreError.notFound {
            // Entrainement retire dans Sante par l'utilisateur : rien a relier.
        } catch {
            outcome.failures.append(error.localizedDescription)
            DiagnosticsCenter.record(.health, code: "health.effort.writeFailed", error: error)
        }
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
            sessions: sessions.map(syncSession),
            links: existingLinks.map {
                HealthSyncLink(
                    completedSessionId: $0.completedSessionId,
                    workoutIdentifier: $0.healthKitWorkoutIdentifier,
                    isDeleted: $0.deletedAt != nil,
                    writtenAt: $0.writtenAt,
                    writtenStartDate: $0.writtenStartDate,
                    writtenDurationSeconds: $0.writtenDurationSeconds,
                    writtenEffortRating: $0.writtenEffortRating,
                    effortSampleIdentifier: $0.effortSampleIdentifier
                )
            },
            excluding: liveRecordingSessionIds
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
                let link = insertLink(for: session, workoutIdentifier: identifier, in: context, now: now)
                outcome.written += 1
                await writeEffort(session.effortRating, on: link, store: store, outcome: &outcome)
            } catch {
                // Un échec sur une séance n'interrompt pas les autres, et ne
                // laisse jamais de lien vers un entraînement inexistant.
                outcome.failures.append(error.localizedDescription)
                DiagnosticsCenter.record(.health, code: "health.workout.writeFailed", error: error)
            }
        }

        // Seances corrigees apres leur ecriture : HealthKit ne modifie pas un
        // entrainement enregistre. L'ancien est retire et son lien aussi,
        // PUIS le nouveau est ecrit. Dans cet ordre, un echec ne double
        // jamais l'entrainement : sans lien vivant, la synchronisation
        // suivante ecrit simplement la seance.
        for replacement in plan.toReplace {
            let session = replacement.session
            do {
                try await store.deleteWorkout(identifier: replacement.previousWorkoutIdentifier)
                outcome.deleted += 1
            } catch HealthStoreError.notFound {
                // Deja supprime dans Sante : rien a regretter, on poursuit.
            } catch {
                // L'ancien entrainement est peut-etre toujours la : en ecrire
                // un second ferait un doublon. On retentera plus tard.
                outcome.failures.append(error.localizedDescription)
                DiagnosticsCenter.record(.health, code: "health.workout.deleteFailed", error: error)
                continue
            }
            for link in existingLinks where link.healthKitWorkoutIdentifier == replacement.previousWorkoutIdentifier {
                link.deletedAt = now
                link.updatedAt = now
            }
            do {
                let identifier = try await store.writeWorkout(
                    sessionId: session.id,
                    start: session.startDate,
                    durationSeconds: session.durationSeconds,
                    energyKilocalories: session.activeEnergyKilocalories
                )
                let link = insertLink(for: session, workoutIdentifier: identifier, in: context, now: now)
                outcome.written += 1
                await writeEffort(session.effortRating, on: link, store: store, outcome: &outcome)
            } catch {
                outcome.failures.append(error.localizedDescription)
                DiagnosticsCenter.record(.health, code: "health.workout.writeFailed", error: error)
            }
        }

        // Note d'effort corrigee, ajoutee ou retiree sur un entrainement
        // conserve : l'ancien echantillon part d'abord, puis le nouveau est
        // relie. L'entrainement lui-meme n'est pas touche.
        for update in plan.effortUpdates where store.canWriteWorkoutEffort {
            guard let link = existingLinks.first(where: {
                $0.deletedAt == nil && $0.healthKitWorkoutIdentifier == update.workoutIdentifier
            }) else { continue }
            if let previous = update.previousSampleIdentifier {
                do {
                    try await store.deleteWorkoutEffort(sampleIdentifier: previous)
                } catch HealthStoreError.notFound {
                    // Deja retiree dans Sante.
                } catch {
                    outcome.failures.append(error.localizedDescription)
                    DiagnosticsCenter.record(.health, code: "health.effort.deleteFailed", error: error)
                    continue
                }
                link.writtenEffortRating = nil
                link.effortSampleIdentifier = nil
            }
            await writeEffort(update.effortRating, on: link, store: store, outcome: &outcome)
            link.updatedAt = now
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

    /// Cardio des seances recentes qui n'en ont pas : lu dans Sante sur
    /// l'intervalle de la seance (montre portee sans seance en direct,
    /// version d'iOS sans seance en direct). Une valeur deja connue n'est
    /// jamais ecrasee ; rien n'est lu si l'autorisation de lecture manque —
    /// HealthKit repond alors comme s'il n'y avait aucune donnee.
    private static func backfillCardio(in context: ModelContext, store: HealthStoring, now: Date) async {
        let sessions = (try? context.fetch(FetchDescriptor<CompletedSession>())) ?? []
        let excluded = liveRecordingSessionIds
        let byId = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let candidates = sessions.filter { !excluded.contains($0.id) }.map { session in
            let interval = PastSessionEditor.interval(of: session)
            return HealthCardioBackfill.Candidate(
                id: session.id,
                start: interval.start,
                end: interval.end,
                hasCardio: session.hasCardio,
                isDeleted: session.deletedAt != nil
            )
        }

        var changed = false
        for candidate in HealthCardioBackfill.sessionsToFetch(candidates, now: now) {
            guard let session = byId[candidate.id] else { continue }
            do {
                let cardio = try await store.readCardio(start: candidate.start, end: candidate.end).cardio
                guard !cardio.isEmpty else { continue }
                session.apply(cardio)
                changed = true
            } catch {
                DiagnosticsCenter.record(.health, code: "health.cardio.readFailed", error: error)
            }
        }
        if changed {
            _ = PersistenceSupport.save(context, action: "Lecture du cardio dans Santé")
        }
    }

    /// Import incremental des mesures activees (poids, masse grasse, tour
    /// de taille), dedoublonne par identifiant d'echantillon Sante.
    private static func importMeasurements(
        in context: ModelContext,
        store: HealthStoring,
        outcome: HealthSyncOutcome,
        now: Date
    ) async -> HealthSyncOutcome {
        var outcome = outcome
        var imported = false

        for kind in HealthSettings.importedMeasurementKinds {
            let since = HealthMeasurementImporter.queryStart(lastImport: HealthSettings.lastImportDate(for: kind), now: now)
            do {
                let samples = try await store.readMeasurementSamples(kind: kind, since: since)
                let known = ((try? context.fetch(FetchDescriptor<BodyMeasurement>())) ?? [])
                    .filter { $0.kindRaw == kind.rawValue }
                    .map {
                        KnownMeasurement(
                            kindRaw: $0.kindRaw,
                            value: $0.value,
                            date: $0.measuredAt,
                            healthSampleIdentifier: $0.healthSampleUUID,
                            isDeleted: $0.deletedAt != nil
                        )
                    }

                for sample in HealthMeasurementImporter.newSamples(samples, known: known) {
                    context.insert(BodyMeasurement(
                        kindRaw: kind.rawValue,
                        measuredAt: sample.date,
                        value: sample.value,
                        sourceRaw: MeasurementSource.healthKit.rawValue,
                        healthSampleUUID: sample.sampleIdentifier
                    ))
                    outcome.importedMeasurements += 1
                    imported = true
                }
                HealthSettings.setLastImportDate(now, for: kind)
            } catch {
                outcome.failures.append(error.localizedDescription)
                DiagnosticsCenter.record(.health, code: "health.measurement.importFailed", error: error)
            }
        }

        if imported {
            _ = PersistenceSupport.save(context, action: "Import des mesures depuis Santé")
        }
        return outcome
    }

    /// Relie l'entrainement enregistre par une seance Sante en direct a la
    /// seance terminee : cardio mesure, lien (qui empeche toute ecriture
    /// apres coup) et note d'effort.
    @discardableResult
    static func attachLiveWorkout(
        identifier: String,
        to sessionId: UUID,
        cardio: SessionCardio,
        in context: ModelContext,
        store: HealthStoring,
        now: Date = .now
    ) async -> Bool {
        let descriptor = FetchDescriptor<CompletedSession>(predicate: #Predicate { $0.id == sessionId })
        guard let session = try? context.fetch(descriptor).first else { return false }

        session.apply(cardio)

        // Un entrainement ecrit apres coup entre-temps (reprise apres un
        // arret brutal) est retire : l'entrainement en direct, plus riche,
        // le remplace. Jamais deux entrainements pour une seance.
        var outcome = HealthSyncOutcome(authorization: store.authorizationStatus())
        for link in links(in: context) where link.completedSessionId == sessionId && link.deletedAt == nil {
            do {
                try await store.deleteWorkout(identifier: link.healthKitWorkoutIdentifier)
            } catch HealthStoreError.notFound {
                // Deja retire.
            } catch {
                DiagnosticsCenter.record(.health, code: "health.workout.deleteFailed", error: error)
            }
            link.deletedAt = now
            link.updatedAt = now
        }

        let link = insertLink(for: syncSession(session), workoutIdentifier: identifier, source: "iphone-live", in: context, now: now)
        await writeEffort(session.effortRating, on: link, store: store, outcome: &outcome)
        return PersistenceSupport.save(context, action: "Séance Santé en direct")
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
