import Foundation
import Testing
@testable import MuscuEngine

@Suite("Santé — cardio, effort, séance en direct, mesures (lot 5)")
struct HealthLot5Tests {
    private let reference = Date(timeIntervalSince1970: 1_772_000_000)

    // MARK: - Cardio

    @Test("Le cardio se calcule depuis les échantillons, arrondi au bpm")
    func cardioFromSamples() {
        let cardio = SessionCardio.from(heartRates: [100, 120, 141], activeEnergyKilocalories: 250.4)
        #expect(cardio.averageHeartRate == 120)
        #expect(cardio.minimumHeartRate == 100)
        #expect(cardio.maximumHeartRate == 141)
        #expect(cardio.activeEnergyKilocalories == 250)
    }

    @Test("Sans échantillon, aucune fréquence : jamais zéro")
    func noSamplesMeansNoHeartRate() {
        let cardio = SessionCardio.from(heartRates: [], activeEnergyKilocalories: nil)
        #expect(cardio.averageHeartRate == nil)
        #expect(cardio.minimumHeartRate == nil)
        #expect(cardio.maximumHeartRate == nil)
        #expect(cardio.isEmpty)
    }

    @Test("Les valeurs aberrantes sont écartées")
    func implausibleValuesAreDropped() {
        let cardio = SessionCardio.from(heartRates: [0, 5, 130, 400, .nan], activeEnergyKilocalories: -3)
        #expect(cardio.averageHeartRate == 130)
        #expect(cardio.minimumHeartRate == 130)
        #expect(cardio.maximumHeartRate == 130)
        #expect(cardio.activeEnergyKilocalories == nil)
    }

    @Test("Une énergie mesurée à zéro reste zéro")
    func zeroEnergyIsAMeasurement() {
        let cardio = SessionCardio(averageHeartRate: nil, minimumHeartRate: nil, maximumHeartRate: nil, activeEnergyKilocalories: 0)
        #expect(cardio.activeEnergyKilocalories == 0)
        #expect(!cardio.isEmpty)
    }

    @Test("Seules les séances récentes sans cardio sont relues dans Santé")
    func backfillCandidates() {
        let now = reference
        let recent = HealthCardioBackfill.Candidate(id: UUID(), start: now.addingTimeInterval(-7_200), end: now.addingTimeInterval(-3_600), hasCardio: false)
        let measured = HealthCardioBackfill.Candidate(id: UUID(), start: now.addingTimeInterval(-7_200), end: now.addingTimeInterval(-3_600), hasCardio: true)
        let old = HealthCardioBackfill.Candidate(id: UUID(), start: now.addingTimeInterval(-10 * 86_400), end: now.addingTimeInterval(-10 * 86_400 + 3_600), hasCardio: false)
        let deleted = HealthCardioBackfill.Candidate(id: UUID(), start: now.addingTimeInterval(-7_200), end: now.addingTimeInterval(-3_600), hasCardio: false, isDeleted: true)
        let result = HealthCardioBackfill.sessionsToFetch([old, measured, recent, deleted], now: now)
        #expect(result == [recent])
    }

    // MARK: - Effort

    @Test("La note d'effort passe telle quelle sur l'échelle de Santé")
    func effortMapping() {
        #expect(HealthEffortScore.appleEffortScore(for: 1) == 1)
        #expect(HealthEffortScore.appleEffortScore(for: 7) == 7)
        #expect(HealthEffortScore.appleEffortScore(for: 10) == 10)
        #expect(HealthEffortScore.appleEffortScore(for: 0) == nil)
        #expect(HealthEffortScore.appleEffortScore(for: 11) == nil)
        #expect(HealthEffortScore.appleEffortScore(for: nil) == nil)
    }

    private func linkedPlan(
        effort: Int?,
        writtenEffort: Int?,
        sampleId: String? = nil,
        editedAt: Date? = nil,
        writtenStart: Date? = nil,
        writtenDuration: Int? = nil,
        sessionStart: Date? = nil
    ) -> (UUID, HealthSyncPlan) {
        let id = UUID()
        let session = HealthSyncSession(
            id: id,
            startDate: sessionStart ?? reference,
            durationSeconds: 3_600,
            editedAt: editedAt,
            effortRating: effort
        )
        let link = HealthSyncLink(
            completedSessionId: id,
            workoutIdentifier: "hk-1",
            writtenAt: reference.addingTimeInterval(3_700),
            writtenStartDate: writtenStart,
            writtenDurationSeconds: writtenDuration,
            writtenEffortRating: writtenEffort,
            effortSampleIdentifier: sampleId
        )
        return (id, HealthSyncPlanner.plan(sessions: [session], links: [link]))
    }

    @Test("Une note d'effort non encore écrite est ajoutée au lien existant")
    func effortWrittenOnExistingWorkout() {
        let (id, plan) = linkedPlan(effort: 7, writtenEffort: nil)
        #expect(plan.toWrite.isEmpty)
        #expect(plan.toReplace.isEmpty)
        #expect(plan.effortUpdates == [HealthEffortUpdate(completedSessionId: id, workoutIdentifier: "hk-1", previousSampleIdentifier: nil, effortRating: 7)])
    }

    @Test("Une note corrigée remplace l'échantillon précédent, pas l'entraînement")
    func correctedEffortReplacesOnlyTheSample() {
        let (_, plan) = linkedPlan(
            effort: 9, writtenEffort: 7, sampleId: "effort-1",
            editedAt: reference.addingTimeInterval(9_000),
            writtenStart: reference, writtenDuration: 3_600
        )
        #expect(plan.toReplace.isEmpty, "Les horaires n'ont pas changé : l'entraînement est gardé")
        #expect(plan.effortUpdates.first?.previousSampleIdentifier == "effort-1")
        #expect(plan.effortUpdates.first?.effortRating == 9)
    }

    @Test("Une note retirée retire l'échantillon")
    func removedEffortRemovesTheSample() {
        let (_, plan) = linkedPlan(effort: nil, writtenEffort: 7, sampleId: "effort-1")
        #expect(plan.effortUpdates.first?.effortRating == nil)
        #expect(plan.effortUpdates.first?.previousSampleIdentifier == "effort-1")
    }

    @Test("Une note inchangée ne produit rien")
    func unchangedEffortDoesNothing() {
        let (_, plan) = linkedPlan(effort: 7, writtenEffort: 7, sampleId: "effort-1")
        #expect(plan.isEmpty)
    }

    @Test("Des horaires corrigés remplacent l'entraînement")
    func changedTimingStillReplaces() {
        let (_, plan) = linkedPlan(
            effort: 7, writtenEffort: 7,
            editedAt: reference.addingTimeInterval(9_000),
            writtenStart: reference, writtenDuration: 3_600,
            sessionStart: reference.addingTimeInterval(-600)
        )
        #expect(plan.toReplace.count == 1)
        #expect(plan.effortUpdates.isEmpty)
    }

    @Test("Un lien sans horaires mémorisés garde la règle de la correction")
    func legacyLinkKeepsEditRule() {
        let (_, plan) = linkedPlan(effort: nil, writtenEffort: nil, editedAt: reference.addingTimeInterval(9_000))
        #expect(plan.toReplace.count == 1)
    }

    @Test("Une séance en cours d'enregistrement en direct n'est pas écrite après coup")
    func liveSessionIsExcluded() {
        let id = UUID()
        let session = HealthSyncSession(id: id, startDate: reference, durationSeconds: 3_600)
        let excluded = HealthSyncPlanner.plan(sessions: [session], links: [], excluding: [id])
        #expect(excluded.toWrite.isEmpty)
        let later = HealthSyncPlanner.plan(sessions: [session], links: [])
        #expect(later.toWrite.count == 1, "Si la séance en direct échoue, l'écriture après coup reprend")
    }

    // MARK: - Récupération d'une séance en direct

    @Test("Une séance encore en cours est rattachée, en pause")
    func recoveryReattaches() {
        let active = UUID()
        let decision = LiveWorkoutRecovery.decide(
            marker: LiveWorkoutMarker(activeWorkoutId: active),
            pendingActiveWorkoutIds: [active],
            existingCompletedSessionIds: []
        )
        #expect(decision == .reattachPaused(activeWorkoutId: active))
    }

    @Test("Une séance terminée avant l'arrêt est terminée et reliée")
    func recoveryFinishes() {
        let completed = UUID()
        let decision = LiveWorkoutRecovery.decide(
            marker: LiveWorkoutMarker(activeWorkoutId: UUID(), completedSessionId: completed),
            pendingActiveWorkoutIds: [],
            existingCompletedSessionIds: [completed]
        )
        #expect(decision == .finish(completedSessionId: completed))
    }

    @Test("Une séance abandonnée ou inconnue n'est jamais enregistrée")
    func recoveryDiscards() {
        #expect(LiveWorkoutRecovery.decide(marker: nil, pendingActiveWorkoutIds: [], existingCompletedSessionIds: []) == .discard)
        #expect(LiveWorkoutRecovery.decide(
            marker: LiveWorkoutMarker(activeWorkoutId: UUID()),
            pendingActiveWorkoutIds: [UUID()],
            existingCompletedSessionIds: []
        ) == .discard)
        #expect(LiveWorkoutRecovery.decide(
            marker: LiveWorkoutMarker(activeWorkoutId: UUID(), completedSessionId: UUID()),
            pendingActiveWorkoutIds: [],
            existingCompletedSessionIds: []
        ) == .discard)
    }

    @Test("Une séance trop courte n'est pas enregistrée")
    func shortLiveSessionIsNotSaved() {
        #expect(!LiveWorkoutRecovery.shouldSave(durationSeconds: 30))
        #expect(LiveWorkoutRecovery.shouldSave(durationSeconds: 60))
    }

    @Test("Le marqueur survit à un aller-retour JSON")
    func markerRoundTrip() throws {
        let marker = LiveWorkoutMarker(activeWorkoutId: UUID(), completedSessionId: UUID())
        let decoded = try JSONDecoder().decode(LiveWorkoutMarker.self, from: JSONEncoder().encode(marker))
        #expect(decoded == marker)
    }

    // MARK: - Mesures

    private func sample(
        _ id: String,
        _ kind: HealthMeasurementKind = .bodyFatPercent,
        value: Double = 18,
        offset: TimeInterval = 0,
        mine: Bool = false
    ) -> HealthMeasurementSample {
        HealthMeasurementSample(sampleIdentifier: id, kind: kind, value: value, date: reference.addingTimeInterval(offset), isFromThisApp: mine)
    }

    @Test("Un échantillon déjà importé ne l'est jamais deux fois")
    func knownIdentifierIsSkipped() {
        let known = [KnownMeasurement(kindRaw: "bodyFatPercent", value: 18, date: reference, healthSampleIdentifier: "a")]
        let fresh = HealthMeasurementImporter.newSamples([sample("a"), sample("b", offset: 86_400)], known: known)
        #expect(fresh.map(\.sampleIdentifier) == ["b"])
    }

    @Test("Une mesure supprimée dans Muscu n'est pas réimportée")
    func deletedMeasurementIsNotReimported() {
        let known = [KnownMeasurement(kindRaw: "waist", value: 82, date: reference, healthSampleIdentifier: "a", isDeleted: true)]
        #expect(HealthMeasurementImporter.newSamples([sample("a", .waist, value: 82)], known: known).isEmpty)
    }

    @Test("Ce que Muscu a écrit, les doublons d'un lot et les aberrations sont écartés")
    func filtersOwnDuplicatesAndOutliers() {
        let fresh = HealthMeasurementImporter.newSamples(
            [sample("mine", mine: true), sample("x"), sample("x"), sample("absurd", value: 250)],
            known: []
        )
        #expect(fresh.map(\.sampleIdentifier) == ["x"])
    }

    @Test("Une saisie manuelle proche vaut la même mesure ; une autre métrique non")
    func approximateMatchIsPerKind() {
        let known = [KnownMeasurement(kindRaw: "waist", value: 82.2, date: reference.addingTimeInterval(600), healthSampleIdentifier: nil)]
        #expect(HealthMeasurementImporter.newSamples([sample("w", .waist, value: 82)], known: known).isEmpty)
        #expect(HealthMeasurementImporter.newSamples([sample("f", .bodyFatPercent, value: 82)], known: known).count == 0,
                "82 % de masse grasse est hors bornes")
        #expect(HealthMeasurementImporter.newSamples([sample("f", .bodyFatPercent, value: 20)], known: known).count == 1)
    }

    @Test("La lecture est incrémentale, avec recouvrement")
    func incrementalQueryStart() {
        #expect(HealthMeasurementImporter.queryStart(lastImport: nil, now: reference)
            == reference.addingTimeInterval(-90 * 86_400))
        #expect(HealthMeasurementImporter.queryStart(lastImport: reference, now: reference.addingTimeInterval(86_400))
            == reference.addingTimeInterval(-7 * 86_400))
    }

    @Test("Les types de mesure Santé portent les valeurs brutes de l'application")
    func rawValues() {
        #expect(HealthMeasurementKind.allCases.map(\.rawValue) == ["bodyweight", "bodyFatPercent", "waist"])
    }
}
