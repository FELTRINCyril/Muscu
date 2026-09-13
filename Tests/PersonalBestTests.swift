import XCTest
import SwiftData
import MuscuEngine
@testable import Muscu

@MainActor
final class PersonalBestTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUpWithError() throws {
        container = try TestStore.makeContainer()
    }

    override func tearDownWithError() throws {
        container = nil
    }

    private func set(
        _ exerciseId: String,
        name: String,
        weight: Double,
        reps: Int,
        load: ExerciseLoadType = .external,
        format: SetFormat = .classic,
        duration: Int? = nil,
        setIndex: Int = 0
    ) -> CompletedSet {
        CompletedSet(
            exerciseId: exerciseId,
            displayName: name,
            orderIndex: 0,
            setIndex: setIndex,
            weight: weight,
            reps: reps,
            loadTypeRaw: load.rawValue,
            roleRaw: SetRole.working.rawValue,
            durationSeconds: duration,
            formatRaw: format.rawValue
        )
    }

    func testClassicSessionProducesLoadVolumeAndOneRepMaxRecords() throws {
        let session = CompletedSession(
            programName: "P",
            sessionName: "S",
            bodyweightKilograms: 80,
            sets: [
                set("bench", name: "Développé", weight: 80, reps: 5),
                set("bench", name: "Développé", weight: 85, reps: 3, setIndex: 1),
            ]
        )
        let candidates = PersonalBestUpdater.candidates(for: session)
        let kinds = Set(candidates.map(\.kind))

        XCTAssertTrue(kinds.contains(.maxWeight))
        XCTAssertTrue(kinds.contains(.estimatedOneRepMax))
        XCTAssertTrue(kinds.contains(.maxSessionVolume))
        XCTAssertEqual(candidates.first { $0.kind == .maxWeight }?.value, 85)
        XCTAssertEqual(candidates.first { $0.kind == .maxSessionVolume }?.value, 80 * 5 + 85 * 3)
    }

    /// Une traction assistee ne cree jamais de record de charge, et son
    /// record de repetitions porte l'assistance dans sa configuration.
    func testAssistedSetProducesOnlyAConfiguredRepsRecord() throws {
        let session = CompletedSession(
            programName: "P",
            sessionName: "S",
            bodyweightKilograms: 80,
            sets: [set("pullup", name: "Tractions", weight: 30, reps: 8, load: .assisted)]
        )
        let candidates = PersonalBestUpdater.candidates(for: session)

        XCTAssertFalse(candidates.contains { $0.kind == .maxWeight })
        XCTAssertFalse(candidates.contains { $0.kind == .estimatedOneRepMax })
        let repsRecord = try XCTUnwrap(candidates.first { $0.kind == .maxReps })
        XCTAssertEqual(repsRecord.configurationKey, "assisted:30.0")
    }

    func testAmrapRecordIsSpecificToItsDuration() throws {
        let eightMinutes = CompletedSession(
            programName: "P",
            sessionName: "S",
            sets: [set("burpees", name: "Burpees", weight: 0, reps: 90, load: .bodyweight, format: .amrap, duration: 480)]
        )
        let twelveMinutes = CompletedSession(
            programName: "P",
            sessionName: "S",
            sets: [set("burpees", name: "Burpees", weight: 0, reps: 120, load: .bodyweight, format: .amrap, duration: 720)]
        )

        let first = PersonalBestUpdater.candidates(for: eightMinutes)
        let second = PersonalBestUpdater.candidates(for: twelveMinutes)

        let firstKey = try XCTUnwrap(first.first { $0.kind == .maxRounds }?.configurationKey)
        let secondKey = try XCTUnwrap(second.first { $0.kind == .maxRounds }?.configurationKey)
        XCTAssertNotEqual(firstKey, secondKey, "Deux AMRAP de durées différentes ne sont pas comparables")

        PersonalBestUpdater.apply(candidates: first, context: context, sourceSessionId: nil, achievedAt: .now)
        PersonalBestUpdater.apply(candidates: second, context: context, sourceSessionId: nil, achievedAt: .now)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PersonalBest>()), 2)
    }

    /// Un For Time s'ameliore en DIMINUANT : un temps plus lent ne doit pas
    /// ecraser le record.
    func testForTimeRecordImprovesWhenFaster() throws {
        let slow = CompletedSession(
            programName: "P",
            sessionName: "S",
            sets: [set("wod", name: "WOD", weight: 0, reps: 50, load: .bodyweight, format: .forTime, duration: 600)]
        )
        let fast = CompletedSession(
            programName: "P",
            sessionName: "S",
            sets: [set("wod", name: "WOD", weight: 0, reps: 50, load: .bodyweight, format: .forTime, duration: 540)]
        )

        PersonalBestUpdater.apply(
            candidates: PersonalBestUpdater.candidates(for: slow),
            context: context,
            sourceSessionId: nil,
            achievedAt: .now
        )
        try context.save()
        PersonalBestUpdater.apply(
            candidates: PersonalBestUpdater.candidates(for: fast),
            context: context,
            sourceSessionId: nil,
            achievedAt: .now
        )
        try context.save()

        let records = try context.fetch(FetchDescriptor<PersonalBest>())
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.kind, .bestTime)
        XCTAssertEqual(records.first?.value, 540)

        // Une contre-performance ne doit rien ecraser.
        let slower = CompletedSession(
            programName: "P",
            sessionName: "S",
            sets: [set("wod", name: "WOD", weight: 0, reps: 50, load: .bodyweight, format: .forTime, duration: 700)]
        )
        PersonalBestUpdater.apply(
            candidates: PersonalBestUpdater.candidates(for: slower),
            context: context,
            sourceSessionId: nil,
            achievedAt: .now
        )
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<PersonalBest>()).first?.value, 540)
    }

    func testApplyingTheSameSessionTwiceCreatesNoDuplicate() throws {
        let session = CompletedSession(
            programName: "P",
            sessionName: "S",
            bodyweightKilograms: 80,
            sets: [set("bench", name: "Développé", weight: 80, reps: 5)]
        )
        let candidates = PersonalBestUpdater.candidates(for: session)
        PersonalBestUpdater.apply(candidates: candidates, context: context, sourceSessionId: session.id, achievedAt: .now)
        try context.save()
        let firstCount = try context.fetchCount(FetchDescriptor<PersonalBest>())

        PersonalBestUpdater.apply(candidates: candidates, context: context, sourceSessionId: session.id, achievedAt: .now)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PersonalBest>()), firstCount)
    }

    /// Sans poids de corps connu, un exercice au poids du corps ne produit
    /// pas de tonnage invente.
    func testUnknownBodyweightProducesNoVolumeRecord() throws {
        let session = CompletedSession(
            programName: "P",
            sessionName: "S",
            sets: [set("pushup", name: "Pompes", weight: 0, reps: 30, load: .bodyweight)]
        )
        let candidates = PersonalBestUpdater.candidates(for: session)
        XCTAssertFalse(candidates.contains { $0.kind == .maxSessionVolume })
        XCTAssertTrue(candidates.contains { $0.kind == .maxReps })
    }
}
