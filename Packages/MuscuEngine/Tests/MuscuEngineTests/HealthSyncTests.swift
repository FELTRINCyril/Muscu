import Foundation
import Testing
@testable import MuscuEngine

@Suite("Synchronisation Santé")
struct HealthSyncPlannerTests {
    private let reference = Date(timeIntervalSince1970: 1_772_000_000)

    private func session(
        _ id: UUID = UUID(),
        offsetDays: Int = 0,
        duration: Int = 3_600,
        deleted: Bool = false
    ) -> HealthSyncSession {
        HealthSyncSession(
            id: id,
            startDate: reference.addingTimeInterval(Double(offsetDays) * 86_400),
            durationSeconds: duration,
            isDeleted: deleted
        )
    }

    @Test("Une séance sans lien est écrite")
    func unlinkedSessionIsWritten() {
        let plan = HealthSyncPlanner.plan(sessions: [session()], links: [])
        #expect(plan.toWrite.count == 1)
        #expect(plan.toDelete.isEmpty)
    }

    @Test("Une séance déjà écrite ne l'est jamais deux fois")
    func linkedSessionIsNeverRewritten() {
        let id = UUID()
        let plan = HealthSyncPlanner.plan(
            sessions: [session(id)],
            links: [HealthSyncLink(completedSessionId: id, workoutIdentifier: "hk-1")]
        )
        #expect(plan.toWrite.isEmpty)
        #expect(plan.alreadyWritten == [id])
    }

    @Test("Rejouer la synchronisation ne produit rien de plus")
    func replayingChangesNothing() {
        let id = UUID()
        let links = [HealthSyncLink(completedSessionId: id, workoutIdentifier: "hk-1")]
        let first = HealthSyncPlanner.plan(sessions: [session(id)], links: links)
        let second = HealthSyncPlanner.plan(sessions: [session(id)], links: links)
        #expect(first == second)
        #expect(first.isEmpty)
    }

    @Test("Une séance supprimée retire son entraînement Santé")
    func deletedSessionRemovesItsWorkout() {
        let id = UUID()
        let plan = HealthSyncPlanner.plan(
            sessions: [session(id, deleted: true)],
            links: [HealthSyncLink(completedSessionId: id, workoutIdentifier: "hk-1")]
        )
        #expect(plan.toDelete == ["hk-1"])
        #expect(plan.toWrite.isEmpty)
    }

    @Test("Une séance supprimée sans lien ne déclenche rien")
    func deletedSessionWithoutLinkDoesNothing() {
        let plan = HealthSyncPlanner.plan(sessions: [session(deleted: true)], links: [])
        #expect(plan.isEmpty)
    }

    @Test("Un lien orphelin est nettoyé")
    func orphanLinkIsCleanedUp() {
        let plan = HealthSyncPlanner.plan(
            sessions: [],
            links: [HealthSyncLink(completedSessionId: UUID(), workoutIdentifier: "hk-orphelin")]
        )
        #expect(plan.toDelete == ["hk-orphelin"])
    }

    @Test("Un lien déjà supprimé ne bloque pas une nouvelle écriture")
    func deletedLinkAllowsRewriting() {
        let id = UUID()
        let plan = HealthSyncPlanner.plan(
            sessions: [session(id)],
            links: [HealthSyncLink(completedSessionId: id, workoutIdentifier: "hk-1", isDeleted: true)]
        )
        #expect(plan.toWrite.count == 1)
    }

    @Test("Une séance trop courte n'est pas écrite")
    func tooShortSessionIsSkipped() {
        let plan = HealthSyncPlanner.plan(sessions: [session(duration: 30)], links: [])
        #expect(plan.toWrite.isEmpty)
        #expect(plan.toDelete.isEmpty)
    }

    @Test("Les écritures sont ordonnées dans le temps")
    func writesAreChronological() {
        let plan = HealthSyncPlanner.plan(
            sessions: [session(offsetDays: 3), session(offsetDays: 1), session(offsetDays: 2)],
            links: []
        )
        let dates = plan.toWrite.map(\.startDate)
        #expect(dates == dates.sorted())
    }
}

@Suite("Import du poids depuis Santé")
struct HealthBodyweightImporterTests {
    private let reference = Date(timeIntervalSince1970: 1_772_000_000)

    @Test("Un échantillon écrit par Muscu n'est jamais réimporté")
    func ownSamplesAreIgnored() {
        let samples = [HealthBodyweightSample(kilograms: 78, date: reference, isFromThisApp: true)]
        #expect(HealthBodyweightImporter.newSamples(samples, existing: []).isEmpty)
    }

    @Test("Une mesure déjà connue n'est pas dupliquée")
    func knownMeasurementIsNotDuplicated() {
        let samples = [HealthBodyweightSample(kilograms: 78.02, date: reference, isFromThisApp: false)]
        let existing = [(kilograms: 78.0, date: reference.addingTimeInterval(600))]
        #expect(HealthBodyweightImporter.newSamples(samples, existing: existing).isEmpty)
    }

    @Test("Une pesée différente le même jour reste importée")
    func differentWeightSameDayIsImported() {
        let samples = [HealthBodyweightSample(kilograms: 80, date: reference, isFromThisApp: false)]
        let existing = [(kilograms: 78.0, date: reference)]
        #expect(HealthBodyweightImporter.newSamples(samples, existing: existing).count == 1)
    }

    @Test("Une même valeur à plusieurs jours d'écart est une nouvelle mesure")
    func sameWeightOtherDayIsNew() {
        let samples = [HealthBodyweightSample(kilograms: 78, date: reference, isFromThisApp: false)]
        let existing = [(kilograms: 78.0, date: reference.addingTimeInterval(-3 * 86_400))]
        #expect(HealthBodyweightImporter.newSamples(samples, existing: existing).count == 1)
    }
}

@Suite("Transfert depuis la montre")
struct WatchTransferReconcilerTests {
    private func decide(
        id: UUID = UUID(),
        version: Int = 1,
        setCount: Int = 3,
        existing: Set<UUID> = []
    ) -> WatchTransferDecision {
        WatchTransferReconciler.decide(
            incomingId: id,
            version: version,
            setCount: setCount,
            currentVersion: 1,
            existingSessionIds: existing
        )
    }

    @Test("Une séance inconnue est acceptée")
    func unknownSessionIsAccepted() {
        #expect(decide() == .accept)
    }

    @Test("Un transfert rejoué n'ajoute rien")
    func replayedTransferIsADuplicate() {
        let id = UUID()
        #expect(decide(id: id, existing: [id]) == .duplicate)
    }

    @Test("Rejouer dix fois ne change rien")
    func repeatedReplaysStayDuplicates() {
        let id = UUID()
        for _ in 0..<10 {
            #expect(decide(id: id, existing: [id]).writesAnything == false)
        }
    }

    @Test("Un format plus récent est refusé, pas deviné")
    func newerVersionIsRefused() {
        #expect(decide(version: 2) == .unsupportedVersion(2))
    }

    @Test("Une séance sans série n'est pas enregistrée")
    func emptySessionIsRefused() {
        #expect(decide(setCount: 0) == .empty)
    }

    @Test("Chaque décision s'explique")
    func everyDecisionExplainsItself() {
        let decisions: [WatchTransferDecision] = [.accept, .duplicate, .unsupportedVersion(9), .empty]
        #expect(decisions.allSatisfy { !$0.explanation.isEmpty })
    }
}
