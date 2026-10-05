import Foundation
import Testing
@testable import MuscuEngine

@Suite
struct MergePolicyTests {
    private let identifier = UUID()
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func metadata(updated: TimeInterval, deleted: TimeInterval? = nil) -> SyncMetadata {
        SyncMetadata(
            identifier: identifier,
            createdAt: base,
            updatedAt: base.addingTimeInterval(updated),
            deletedAt: deleted.map { base.addingTimeInterval($0) }
        )
    }

    @Test
    func testCompletedHistoryIsImmutable() {
        let local = metadata(updated: 0)
        let remote = metadata(updated: 100)
        #expect(MergePolicy.resolve(strategy: .immutableByIdentifier, local: local, remote: remote) == .keepLocal(local))
    }

    // Une suppression ne gagne que si elle est plus recente que la
    // modification concurrente ; sinon la donnee vivante est conservee.
    @Test
    func testDeletionWinsOnlyWhenNewer() {
        let modifiedLater = metadata(updated: 50)
        let deletedEarlier = metadata(updated: 0, deleted: 10)
        #expect(MergePolicy.resolve(strategy: .identifierOnly, local: deletedEarlier, remote: modifiedLater) == .takeRemote(modifiedLater))

        let deletedLater = metadata(updated: 0, deleted: 100)
        #expect(MergePolicy.resolve(strategy: .identifierOnly, local: deletedLater, remote: modifiedLater) == .keepLocal(deletedLater))
    }

    @Test
    func testTwoDeletionsKeepTheNewestTombstone() {
        let localDeleted = metadata(updated: 0, deleted: 10)
        let remoteDeleted = metadata(updated: 0, deleted: 20)
        #expect(MergePolicy.resolve(strategy: .identifierOnly, local: localDeleted, remote: remoteDeleted) == .takeRemote(remoteDeleted))
    }

    @Test
    func testProgramConflictIsSurfacedNeverDropped() {
        let local = metadata(updated: 10)
        let remote = metadata(updated: 20)
        #expect(
            MergePolicy.resolve(strategy: .lastWriteWinsWithConflictFlag, local: local, remote: remote)
                == .conflict(local: local, remote: remote)
        )
    }

    @Test
    func testIdenticalTimestampsDoNotConflict() {
        let local = metadata(updated: 10)
        let remote = metadata(updated: 10)
        #expect(MergePolicy.resolve(strategy: .lastWriteWinsWithConflictFlag, local: local, remote: remote) == .keepLocal(local))
    }

    @Test
    func testRecordMergeKeepsMaximum() {
        #expect(MergePolicy.maximum(120.0, 100.0) == 120)
        #expect(MergePolicy.maximum(nil, 100.0) == 100)
        #expect(MergePolicy.maximum(Double?.none, nil) == nil)
    }

    @Test
    func testTombstonePurgeRespectsRetention() {
        let tombstone = metadata(updated: 0, deleted: 0)
        #expect(MergePolicy.canPurge(tombstone, now: base.addingTimeInterval(60)) == false)
        #expect(MergePolicy.canPurge(tombstone, now: base.addingTimeInterval(MergePolicy.tombstoneRetention + 1)))
        #expect(MergePolicy.canPurge(metadata(updated: 0), now: base) == false)
    }
}
