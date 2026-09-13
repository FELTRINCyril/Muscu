import XCTest
import SwiftData
import MuscuEngine
@testable import Muscu

@MainActor
final class ProgressionReviewTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let reference = Date(timeIntervalSince1970: 1_750_000_000)

    override func setUpWithError() throws {
        container = try TestStore.makeContainer()
    }

    override func tearDownWithError() throws {
        container = nil
    }

    // MARK: - Fabriques

    @discardableResult
    private func makeSession(rule: ProgressionRule? = nil, targetWeight: Double? = 60) throws -> ProgramSession {
        let exercise = PrescribedExercise(
            exerciseId: "bench",
            displayName: "Développé couché",
            orderIndex: 0,
            sets: 3,
            repsLower: 8,
            repsUpper: 12,
            restSeconds: 90,
            targetWeight: targetWeight,
            loadKindRaw: LoadKind.external.rawValue
        )
        exercise.progressionRule = rule
        let session = ProgramSession(name: "Push", orderIndex: 0, exercises: [exercise])
        let program = Program(name: "Programme", isActive: true, sessions: [session])
        session.program = program
        exercise.session = session
        context.insert(program)
        try context.save()
        return session
    }

    private func logHistory(reps: [Int], weight: Double = 60, daysAgo: Int) throws {
        let sets = reps.enumerated().map { index, value in
            CompletedSet(
                exerciseId: "bench",
                displayName: "Développé couché",
                orderIndex: 0,
                setIndex: index,
                weight: weight,
                reps: value,
                loadTypeRaw: ExerciseLoadType.external.rawValue,
                roleRaw: SetRole.working.rawValue
            )
        }
        let session = CompletedSession(
            date: reference.addingTimeInterval(TimeInterval(-daysAgo * 86_400)),
            programName: "Programme",
            sessionName: "Push",
            durationSeconds: 1_800,
            sets: sets
        )
        context.insert(session)
        try context.save()
    }

    // MARK: - Propositions

    func testNoHistoryProducesNoProposal() throws {
        let session = try makeSession()
        XCTAssertTrue(ProgressionReview.proposals(for: session, context: context).isEmpty)
    }

    func testTopOfRangeProposesALoadIncreaseWithItsReasons() throws {
        let session = try makeSession()
        try logHistory(reps: [12, 12, 12], daysAgo: 3)

        let items = ProgressionReview.proposals(for: session, context: context)
        XCTAssertEqual(items.count, 1)
        let item = try XCTUnwrap(items.first)
        XCTAssertEqual(item.proposal.outcome, .increaseLoad(from: 60, to: 62.5))
        XCTAssertFalse(item.factors.isEmpty, "Une proposition doit toujours être justifiée")
        XCTAssertTrue(item.factors.contains { $0.contains("12 répétitions") })
    }

    func testIncompleteSessionProducesNoProposal() throws {
        let session = try makeSession()
        try logHistory(reps: [10, 9, 8], daysAgo: 3)
        XCTAssertTrue(ProgressionReview.proposals(for: session, context: context).isEmpty)
    }

    // MARK: - Décision

    func testAcceptingAppliesTheChangeAndJournalsIt() throws {
        let session = try makeSession()
        try logHistory(reps: [12, 12, 12], daysAgo: 3)

        let item = try XCTUnwrap(ProgressionReview.proposals(for: session, context: context).first)
        let entry = ProgressionReview.accept(item, context: context, now: reference)
        try context.save()

        XCTAssertEqual(session.orderedExercises.first?.targetWeight, 62.5)
        XCTAssertEqual(entry.decision, .accepted)
        XCTAssertEqual(entry.previousWeightKilograms, 60)
        XCTAssertEqual(entry.newWeightKilograms, 62.5)
        XCTAssertFalse(entry.factors.isEmpty)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AdaptationEntry>()), 1)
    }

    func testDecliningLeavesThePrescriptionUntouched() throws {
        let session = try makeSession()
        try logHistory(reps: [12, 12, 12], daysAgo: 3)

        let item = try XCTUnwrap(ProgressionReview.proposals(for: session, context: context).first)
        let entry = ProgressionReview.decline(item, context: context, now: reference)
        try context.save()

        XCTAssertEqual(session.orderedExercises.first?.targetWeight, 60, "Un refus ne doit rien modifier")
        XCTAssertEqual(entry.decision, .declined)
    }

    /// Critere de la roadmap : l'utilisateur peut annuler une adaptation.
    func testRevertingRestoresTheExactPreviousValues() throws {
        let session = try makeSession()
        try logHistory(reps: [12, 12, 12], daysAgo: 3)

        let item = try XCTUnwrap(ProgressionReview.proposals(for: session, context: context).first)
        let entry = ProgressionReview.accept(item, context: context, now: reference)
        try context.save()
        XCTAssertEqual(session.orderedExercises.first?.targetWeight, 62.5)

        XCTAssertTrue(ProgressionReview.revert(entry, context: context, now: reference))
        try context.save()

        XCTAssertEqual(session.orderedExercises.first?.targetWeight, 60)
        XCTAssertEqual(entry.decision, .reverted)
        XCTAssertFalse(entry.canRevert, "Une adaptation annulée ne peut pas l'être deux fois")
    }

    func testRepsProposalIsAppliedAndRevertible() throws {
        let session = try makeSession(rule: .repsProgression(step: 2, maximumReps: 20))
        try logHistory(reps: [8, 8, 8], daysAgo: 3)

        let item = try XCTUnwrap(ProgressionReview.proposals(for: session, context: context).first)
        let entry = ProgressionReview.accept(item, context: context, now: reference)
        try context.save()
        XCTAssertEqual(session.orderedExercises.first?.repsUpper, 14)

        XCTAssertTrue(ProgressionReview.revert(entry, context: context, now: reference))
        try context.save()
        XCTAssertEqual(session.orderedExercises.first?.repsUpper, 12)
    }

    /// Le profil fournit la regle par defaut et l'increment reellement
    /// disponible : une salle sans disques de 1,25 kg ne doit pas se voir
    /// proposer 61,25 kg.
    func testProfileIncrementDrivesTheProposedLoad() throws {
        let profile = ProfileStore.ensureProfile(in: context)
        profile.availableIncrementsKilograms = [5]
        profile.defaultProgressionRule = .doubleProgression(incrementKilograms: 5, requiredSuccesses: 1)
        try context.save()

        let session = try makeSession(rule: nil)
        try logHistory(reps: [12, 12, 12], daysAgo: 3)

        let item = try XCTUnwrap(ProgressionReview.proposals(for: session, context: context).first)
        XCTAssertEqual(item.proposal.outcome, .increaseLoad(from: 60, to: 65))
    }

    // MARK: - Historique

    func testExposuresAreOrderedFromMostRecentAndExcludeWarmups() throws {
        try makeSession()
        try logHistory(reps: [10, 10, 10], weight: 55, daysAgo: 10)
        try logHistory(reps: [12, 12, 12], weight: 60, daysAgo: 3)

        let warmup = CompletedSet(
            exerciseId: "bench",
            displayName: "Développé couché",
            orderIndex: 0,
            setIndex: 0,
            weight: 20,
            reps: 10,
            isWarmup: true,
            roleRaw: SetRole.warmup.rawValue
        )
        let session = CompletedSession(
            date: reference.addingTimeInterval(-86_400),
            programName: "Programme",
            sessionName: "Push",
            sets: [warmup]
        )
        context.insert(session)
        try context.save()

        let history = try context.fetch(
            FetchDescriptor<CompletedSession>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        )
        let exposures = ProgressionReview.exposures(exerciseId: "bench", history: history, limit: 6)

        XCTAssertEqual(exposures.count, 3)
        XCTAssertTrue(exposures[0].workingSets.isEmpty, "La séance d'échauffement seul n'a aucune série de travail")
        XCTAssertEqual(exposures[1].workingSets.first?.weightKilograms, 60)
        XCTAssertEqual(exposures[2].workingSets.first?.weightKilograms, 55)
    }

    func testSummaryIsReadableForEveryOutcome() {
        XCTAssertTrue(ProgressionReview.summary(for: .increaseLoad(from: 60, to: 62.5)).contains("→"))
        XCTAssertTrue(ProgressionReview.summary(for: .increaseReps(from: 10, to: 12)).contains("Répétitions"))
        XCTAssertTrue(ProgressionReview.summary(for: .increaseSets(from: 3, to: 4)).contains("Séries"))
        XCTAssertTrue(ProgressionReview.summary(for: .increasePercent(from: 75, to: 80)).contains("%"))
        XCTAssertTrue(ProgressionReview.summary(for: .adjustTime(workDeltaSeconds: 5, restDeltaSeconds: -5)).contains("effort"))
        XCTAssertFalse(ProgressionReview.summary(for: .hold).isEmpty)
        XCTAssertFalse(ProgressionReview.summary(for: .notEnoughData).isEmpty)
    }
}
