import XCTest
import SwiftData
import MuscuEngine
@testable import Muscu

@MainActor
final class PlanImporterTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let catalog = try! ExerciseCatalog.load()
    private let startDate = Date(timeIntervalSince1970: 1_757_030_400)

    override func setUpWithError() throws {
        container = try TestStore.makeContainer()
    }

    override func tearDownWithError() throws {
        container = nil
    }

    private func makeDraft(weeks: Int = 8, deloadEvery: Int? = 4) throws -> DraftPlan {
        let base = GeneratorInput(
            goal: .hypertrophy,
            experience: .intermediate,
            daysPerWeek: 3,
            sessionMinutes: 60,
            equipment: .fullGym,
            splitPreference: .auto,
            priorityMuscles: [],
            avoidAreas: []
        )
        return try PlanGenerator(catalog: catalog).generate(
            PlanGeneratorInput(
                base: base,
                totalWeeks: weeks,
                style: .linear,
                deloadEveryWeeks: deloadEvery,
                startDate: startDate,
                availableWeekdays: [2, 4, 6]
            )
        )
    }

    func testImportCreatesProgramPlanBlocksWeeksAndWorkouts() throws {
        let draft = try makeDraft()
        let result = PlanImporter.insert(draft: draft, into: context, activateProgram: true)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Program>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TrainingPlan>()), 1)
        XCTAssertEqual(result.plan.allWeeks.count, draft.weeks.count)
        XCTAssertEqual(
            result.plan.allWeeks.reduce(0) { $0 + $1.scheduledWorkouts.count },
            draft.totalWorkouts
        )
        XCTAssertTrue(result.program.isActive)
        XCTAssertEqual(result.plan.programId, result.program.id)
    }

    /// Chaque séance planifiée doit pointer vers une vraie séance du
    /// programme : un planning qui ne mène nulle part serait inutilisable.
    func testEveryScheduledWorkoutPointsAtARealSession() throws {
        let draft = try makeDraft()
        let result = PlanImporter.insert(draft: draft, into: context, activateProgram: true)
        try context.save()

        let sessionIds = Set(result.program.orderedSessions.map(\.id))
        for week in result.plan.allWeeks {
            for workout in week.scheduledWorkouts {
                let id = try XCTUnwrap(workout.programSessionId)
                XCTAssertTrue(sessionIds.contains(id))
            }
        }
    }

    func testDeloadWeeksKeepTheirMultipliers() throws {
        let draft = try makeDraft(weeks: 8, deloadEvery: 4)
        let result = PlanImporter.insert(draft: draft, into: context, activateProgram: true)
        try context.save()

        let deloads = result.plan.allWeeks.filter(\.isDeload)
        XCTAssertFalse(deloads.isEmpty)
        for week in deloads {
            XCTAssertLessThan(week.volumeMultiplier, 1)
            XCTAssertEqual(week.block?.kind, .deload)
        }
    }

    /// Deux phases d'accumulation séparées par une décharge forment deux
    /// blocs distincts, pas un seul bloc à trous.
    func testConsecutiveWeeksOfTheSameKindShareABlockAcrossDeloads() throws {
        let draft = try makeDraft(weeks: 12, deloadEvery: 4)
        let result = PlanImporter.insert(draft: draft, into: context, activateProgram: true)
        try context.save()

        let blocks = result.plan.orderedBlocks
        XCTAssertGreaterThan(blocks.count, 2)
        for block in blocks {
            let numbers = block.orderedWeeks.map(\.weekNumber)
            XCTAssertEqual(numbers, Array(numbers.min()!...numbers.max()!), "Un bloc doit couvrir des semaines consécutives")
            XCTAssertEqual(Set(block.orderedWeeks.map(\.stateRaw)).count <= 2, true)
        }
    }

    func testFirstWeekBecomesCurrent() throws {
        let draft = try makeDraft()
        let result = PlanImporter.insert(draft: draft, into: context, activateProgram: true)
        try context.save()
        XCTAssertEqual(result.plan.allWeeks.first?.state, .current)
    }

    func testImportingASecondPlanDeactivatesThePreviousProgram() throws {
        let first = PlanImporter.insert(draft: try makeDraft(), into: context, activateProgram: true)
        try context.save()
        let second = PlanImporter.insert(draft: try makeDraft(), into: context, activateProgram: true)
        try context.save()

        XCTAssertFalse(first.program.isActive)
        XCTAssertTrue(second.program.isActive)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Program>()).filter(\.isActive).count, 1)
    }

    /// Critère de la roadmap : modifier le planning ne touche jamais
    /// l'historique déjà enregistré.
    func testChangingThePlanNeverAltersCompletedHistory() throws {
        let result = PlanImporter.insert(draft: try makeDraft(), into: context, activateProgram: true)
        let session = try XCTUnwrap(result.program.orderedSessions.first)

        let completed = CompletedSession(
            date: startDate,
            programId: result.program.id,
            programSessionId: session.id,
            programName: result.program.name,
            sessionName: session.name,
            durationSeconds: 3_600,
            sets: [
                CompletedSet(
                    exerciseId: "bench",
                    displayName: "Développé",
                    orderIndex: 0,
                    setIndex: 0,
                    weight: 80,
                    reps: 8
                )
            ]
        )
        context.insert(completed)
        try context.save()

        // Déplacer et marquer des séances planifiées.
        for week in result.plan.allWeeks {
            for workout in week.scheduledWorkouts {
                workout.plannedDate = workout.plannedDate.addingTimeInterval(86_400)
                workout.state = .skipped
            }
        }
        try context.save()

        let stored = try XCTUnwrap(context.fetch(FetchDescriptor<CompletedSession>()).first)
        XCTAssertEqual(stored.date, startDate)
        XCTAssertEqual(stored.sets.count, 1)
        XCTAssertEqual(stored.sets.first?.weight, 80)
    }

    /// Le plan exporté puis réimporté doit revenir à l'identique.
    func testPlanSurvivesExportAndImport() throws {
        let result = PlanImporter.insert(draft: try makeDraft(weeks: 4, deloadEvery: nil), into: context, activateProgram: true)
        try context.save()

        let data = try ExportImport.exportAll(context: context)
        let destination = try TestStore.makeContainer()
        try ExportImport.importAll(data: data, context: destination.mainContext)

        let restored = try XCTUnwrap(destination.mainContext.fetch(FetchDescriptor<TrainingPlan>()).first)
        XCTAssertEqual(restored.allWeeks.count, result.plan.allWeeks.count)
        XCTAssertEqual(
            restored.allWeeks.reduce(0) { $0 + $1.scheduledWorkouts.count },
            result.plan.allWeeks.reduce(0) { $0 + $1.scheduledWorkouts.count }
        )
    }
}
