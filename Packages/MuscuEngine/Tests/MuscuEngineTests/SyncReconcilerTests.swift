import Foundation
import Testing
@testable import MuscuEngine

@Suite
struct SyncReconcilerTests {
    private let base = Date(timeIntervalSince1970: 1_750_000_000)

    private func record(
        _ kind: SyncEntityKind = .program,
        id: UUID,
        updated: TimeInterval,
        deleted: TimeInterval? = nil,
        payload: String = "a",
        schemaVersion: Int = SyncMetadata.currentSchemaVersion
    ) -> SyncRecord {
        SyncRecord(
            kind: kind,
            metadata: SyncMetadata(
                identifier: id,
                createdAt: base,
                updatedAt: base.addingTimeInterval(updated),
                deletedAt: deleted.map { base.addingTimeInterval($0) },
                schemaVersion: schemaVersion
            ),
            payload: Data(payload.utf8)
        )
    }

    // MARK: - Décisions unitaires

    @Test
    func testUnknownRecordIsApplied() {
        let remote = record(id: UUID(), updated: 10)
        #expect(SyncReconciler.decide(local: nil, remote: remote) == .applyRemote)
    }

    /// Une suppression faite sur un autre appareil doit se propager, même si
    /// l'entité n'a jamais été vue ici.
    @Test
    func testUnknownTombstoneIsStillApplied() {
        let remote = record(id: UUID(), updated: 10, deleted: 10)
        #expect(SyncReconciler.decide(local: nil, remote: remote) == .applyRemote)
    }

    @Test
    func testIdenticalRecordsProduceNoWrite() {
        let id = UUID()
        let local = record(id: id, updated: 10)
        #expect(SyncReconciler.decide(local: local, remote: local) == .noChange)
    }

    /// Une séance terminée est immuable : un autre appareil ne peut pas la
    /// réécrire.
    @Test
    func testCompletedHistoryIsNeverOverwritten() {
        let id = UUID()
        let local = record(.completedSession, id: id, updated: 0, payload: "fait")
        let remote = record(.completedSession, id: id, updated: 100, payload: "modifié")
        #expect(SyncReconciler.decide(local: local, remote: remote) == .noChange)
    }

    /// Mais elle peut être supprimée explicitement.
    @Test
    func testCompletedHistoryCanStillBeDeleted() {
        let id = UUID()
        let local = record(.completedSession, id: id, updated: 0)
        let remote = record(.completedSession, id: id, updated: 0, deleted: 50)
        #expect(SyncReconciler.decide(local: local, remote: remote) == .applyRemote)
    }

    /// Deux modifications concurrentes d'un programme produisent un conflit
    /// VISIBLE : aucune version n'est écrasée en silence.
    @Test
    func testConcurrentProgramEditsAreSurfacedAsAConflict() {
        let id = UUID()
        let local = record(.program, id: id, updated: 10, payload: "local")
        let remote = record(.program, id: id, updated: 20, payload: "distant")
        #expect(SyncReconciler.decide(local: local, remote: remote) == .conflict)
    }

    /// Même horodatage et même contenu : ce n'est pas un conflit, inutile de
    /// déranger l'utilisateur.
    @Test
    func testSameContentIsNeverAConflict() {
        let id = UUID()
        let local = record(.program, id: id, updated: 10, payload: "identique")
        let remote = record(.program, id: id, updated: 10, payload: "identique")
        #expect(SyncReconciler.decide(local: local, remote: remote) == .noChange)
    }

    /// Une donnée écrite par une version plus récente de l'app n'est pas
    /// appliquée à l'aveugle.
    @Test
    func testFutureSchemaIsRefusedRatherThanGuessed() {
        let id = UUID()
        let local = record(id: id, updated: 10)
        let remote = record(id: id, updated: 20, payload: "b", schemaVersion: SyncMetadata.currentSchemaVersion + 1)
        #expect(SyncReconciler.decide(local: local, remote: remote) == .keepLocal)
    }

    @Test
    func testDeletionWinsOnlyWhenNewerThanTheConcurrentEdit() {
        let id = UUID()
        let edited = record(.bodyMeasurement, id: id, updated: 50, payload: "modifié")
        let deletedEarlier = record(.bodyMeasurement, id: id, updated: 0, deleted: 10)
        #expect(SyncReconciler.decide(local: edited, remote: deletedEarlier) == .keepLocal)

        let deletedLater = record(.bodyMeasurement, id: id, updated: 0, deleted: 100)
        #expect(SyncReconciler.decide(local: edited, remote: deletedLater) == .applyRemote)
    }

    // MARK: - Salves

    @Test
    func testApplyingTheSameBatchTwiceChangesNothingTheSecondTime() {
        let id = UUID()
        let remote = [record(.bodyMeasurement, id: id, updated: 10)]
        let first = SyncReconciler.apply(remote: remote, to: [:], now: base)
        #expect(first.applied == 1)

        let second = SyncReconciler.apply(remote: remote, to: first.state, now: base)
        #expect(second.applied == 0)
        #expect(second.state == first.state)
    }

    /// Propriété : l'ordre d'arrivée ne change pas l'état final.
    @Test
    func testOutOfOrderDeliveryConvergesToTheSameState() {
        let id = UUID()
        let older = record(.bodyMeasurement, id: id, updated: 10, payload: "v1")
        let newer = record(.bodyMeasurement, id: id, updated: 20, payload: "v2")

        let inOrder = SyncReconciler.apply(remote: [older, newer], to: [:], now: base)
        let reversed = SyncReconciler.apply(remote: [newer, older], to: [:], now: base)
        #expect(inOrder.state == reversed.state)
        #expect(inOrder.state[id]?.payload == Data("v2".utf8))
    }

    /// Un conflit conserve les DEUX versions : l'état local n'est pas écrasé
    /// et le conflit est signalé.
    @Test
    func testConflictKeepsLocalAndReportsIt() {
        let id = UUID()
        let local = [id: record(.program, id: id, updated: 10, payload: "local")]
        let remote = [record(.program, id: id, updated: 20, payload: "distant")]

        let result = SyncReconciler.apply(remote: remote, to: local, now: base)
        #expect(result.conflicts.count == 1)
        #expect(result.state[id]?.payload == Data("local".utf8), "La version locale ne doit pas être écrasée")
        #expect(result.conflicts[0].identifier == id)
    }

    @Test
    func testPendingListsOnlyWhatChangedSinceLastPush() {
        let pushed = UUID()
        let modified = UUID()
        let fresh = UUID()
        let local: [UUID: SyncRecord] = [
            pushed: record(id: pushed, updated: 10),
            modified: record(id: modified, updated: 30),
            fresh: record(id: fresh, updated: 5),
        ]
        let lastPushed: [UUID: Date] = [
            pushed: base.addingTimeInterval(10),
            modified: base.addingTimeInterval(20),
        ]
        let pending = SyncReconciler.pending(local: local, lastPushed: lastPushed)
        #expect(Set(pending.map(\.identifier)) == [modified, fresh])
    }

    // MARK: - Stratégies

    @Test
    func testEveryEntityKindHasAStrategy() {
        for kind in SyncEntityKind.allCases {
            #expect(MergeStrategy.allCases.contains(kind.mergeStrategy), "\(kind) sans stratégie")
        }
        #expect(SyncEntityKind.completedSession.isImmutableOnceCreated)
        #expect(SyncEntityKind.program.isImmutableOnceCreated == false)
    }
}

@Suite
struct SyncOutboxTests {
    private let base = Date(timeIntervalSince1970: 1_750_000_000)

    @Test
    func testEnqueueKeepsOnlyTheLatestVersionOfAnEntity() {
        var outbox = SyncOutbox()
        let id = UUID()
        outbox.enqueue(kind: .program, identifier: id, updatedAt: base)
        outbox.enqueue(kind: .program, identifier: id, updatedAt: base.addingTimeInterval(60))
        #expect(outbox.count == 1)
        #expect(outbox.entries[id]?.updatedAt == base.addingTimeInterval(60))
    }

    @Test
    func testOlderVersionNeverReplacesANewerPendingOne() {
        var outbox = SyncOutbox()
        let id = UUID()
        outbox.enqueue(kind: .program, identifier: id, updatedAt: base.addingTimeInterval(60))
        outbox.enqueue(kind: .program, identifier: id, updatedAt: base)
        #expect(outbox.entries[id]?.updatedAt == base.addingTimeInterval(60))
    }

    /// Une entrée n'est retirée qu'après un envoi réussi.
    @Test
    func testAcknowledgeRemovesTheEntry() {
        var outbox = SyncOutbox()
        let id = UUID()
        outbox.enqueue(kind: .program, identifier: id, updatedAt: base)
        outbox.acknowledge(identifier: id, pushedUpdatedAt: base)
        #expect(outbox.isEmpty)
    }

    /// Une modification survenue PENDANT l'envoi ne doit pas être perdue.
    @Test
    func testModificationDuringPushIsNotLost() {
        var outbox = SyncOutbox()
        let id = UUID()
        outbox.enqueue(kind: .program, identifier: id, updatedAt: base)
        // L'utilisateur modifie encore pendant que l'envoi est en vol.
        outbox.enqueue(kind: .program, identifier: id, updatedAt: base.addingTimeInterval(30))
        outbox.acknowledge(identifier: id, pushedUpdatedAt: base)
        #expect(outbox.count == 1, "La modification plus récente reste à envoyer")
    }

    @Test
    func testRetryableFailureSchedulesABackoff() {
        var outbox = SyncOutbox()
        let id = UUID()
        outbox.enqueue(kind: .program, identifier: id, updatedAt: base)
        outbox.registerFailure(identifier: id, failure: .network, now: base)

        let entry = outbox.entries[id]
        #expect(entry?.attemptCount == 1)
        #expect(entry?.nextAttemptAt == base.addingTimeInterval(SyncBackoff.base))
        #expect(outbox.ready(at: base).isEmpty)
        #expect(outbox.ready(at: base.addingTimeInterval(SyncBackoff.base)).count == 1)
    }

    /// Une erreur non retentable ne programme aucune nouvelle tentative,
    /// mais ne supprime rien non plus.
    @Test
    func testNonRetryableFailureKeepsTheEntryWithoutRetrying() {
        var outbox = SyncOutbox()
        let id = UUID()
        outbox.enqueue(kind: .program, identifier: id, updatedAt: base)
        outbox.registerFailure(identifier: id, failure: .accountUnavailable, now: base)
        #expect(outbox.count == 1)
        #expect(outbox.entries[id]?.nextAttemptAt == nil)
    }

    @Test
    func testBackoffGrowsThenIsCapped() {
        #expect(SyncBackoff.delay(forAttempt: 0) == 0)
        #expect(SyncBackoff.delay(forAttempt: 1) == 5)
        #expect(SyncBackoff.delay(forAttempt: 2) == 10)
        #expect(SyncBackoff.delay(forAttempt: 3) == 20)
        #expect(SyncBackoff.delay(forAttempt: 50) == SyncBackoff.maximum)
    }

    @Test
    func testFailureKindsDistinguishRetryableFromBlocking() {
        #expect(SyncFailureKind.network.isRetryable)
        #expect(SyncFailureKind.serviceUnavailable.isRetryable)
        #expect(SyncFailureKind.quotaExceeded.isRetryable == false)
        #expect(SyncFailureKind.accountUnavailable.isRetryable == false)
        for kind in SyncFailureKind.allCases {
            #expect(kind.userMessage.isEmpty == false)
        }
    }

    /// Le message d'état doit toujours rassurer sur le fait que les données
    /// locales sont intactes, et ne jamais parler de perte.
    @Test
    func testStatusSummaryNeverSuggestsDataLoss() {
        let disabled = SyncStatus(isEnabled: false)
        #expect(disabled.summary.contains("restent sur cet appareil"))

        let pending = SyncStatus(isEnabled: true, pendingCount: 3)
        #expect(pending.summary.contains("3"))

        let synced = SyncStatus(isEnabled: true, lastSuccessAt: base, pendingCount: 0)
        #expect(synced.summary == "À jour.")

        let blocked = SyncStatus(isEnabled: true, lastFailure: .accountUnavailable)
        #expect(blocked.summary.contains("hors ligne"))
    }
}

@Suite("Fusion des records au maximum")
struct RecordMergeTests {
    private let identifier = UUID()
    private let base = Date(timeIntervalSince1970: 1_760_000_000)

    private func record(value: Double, updatedAt: TimeInterval) -> SyncRecord {
        SyncRecord(
            kind: .personalBest,
            metadata: SyncMetadata(
                identifier: identifier,
                createdAt: base,
                updatedAt: base.addingTimeInterval(updatedAt)
            ),
            payload: Data("\(value)".utf8),
            comparableValue: value
        )
    }

    /// Le défaut corrigé : un record distant PLUS RÉCENT mais INFÉRIEUR
    /// écrasait un meilleur record local. Un record ne doit jamais régresser.
    @Test("Un record inférieur n'écrase pas un meilleur record, même plus récent")
    func aWeakerRecordNeverWins() {
        let local = record(value: 120, updatedAt: 0)
        let remote = record(value: 100, updatedAt: 3600)
        #expect(SyncReconciler.decide(local: local, remote: remote) == .keepLocal)
    }

    @Test("Un record supérieur gagne, même plus ancien")
    func aStrongerRecordAlwaysWins() {
        let local = record(value: 100, updatedAt: 3600)
        let remote = record(value: 120, updatedAt: 0)
        #expect(SyncReconciler.decide(local: local, remote: remote) == .applyRemote)
    }

    /// À valeur égale, on retombe sur la règle de date : c'est le « puis date
    /// la plus récente » de la spécification.
    @Test("À performance égale, la date tranche")
    func equalValuesFallBackToTheDate() {
        let local = record(value: 100, updatedAt: 0)
        let remote = record(value: 100, updatedAt: 3600)
        #expect(SyncReconciler.decide(local: local, remote: remote) == .applyRemote)
    }

    /// Une suppression doit rester gouvernée par les dates : comparer des
    /// performances quand l'une des deux entités est supprimée n'aurait
    /// aucun sens.
    @Test("Une suppression n'est pas arbitrée par la performance")
    func deletionIsNotDecidedByValue() {
        var remote = record(value: 10, updatedAt: 3600)
        remote.metadata.deletedAt = base.addingTimeInterval(3600)
        let local = record(value: 200, updatedAt: 0)
        #expect(SyncReconciler.decide(local: local, remote: remote) == .applyRemote)
    }

    /// Une entité sans performance comparable garde exactement l'ancien
    /// comportement.
    @Test("Sans valeur comparable, la date décide comme avant")
    func withoutAComparableValueNothingChanges() {
        var local = record(value: 120, updatedAt: 0)
        var remote = record(value: 100, updatedAt: 3600)
        local.comparableValue = nil
        remote.comparableValue = nil
        #expect(SyncReconciler.decide(local: local, remote: remote) == .applyRemote)
    }
}
