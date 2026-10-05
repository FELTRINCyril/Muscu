import XCTest
import SwiftData
import MuscuEngine
@testable import Muscu

/// Repos par palier d'une pyramide (schema v8) : il voyage partout ou les
/// paliers voyagent (deroule, export, modele, duplication), et une valeur
/// invalide est refusee a l'import.
@MainActor
final class PyramidRestAppTests: XCTestCase {
    private func makeProgram(in context: ModelContext, rests: [Int]) -> (Program, ProgramSession, PrescribedExercise) {
        let program = Program(name: "Pyramides")
        let session = ProgramSession(name: "Tractions", orderIndex: 0)
        let pyramid = PrescribedExercise(
            exerciseId: "Pullups",
            displayName: "Tractions",
            orderIndex: 0,
            formatRaw: SetFormat.pyramid.rawValue,
            pyramidReps: [2, 4, 6, 4, 2],
            pyramidMinRest: 45,
            pyramidMaxRest: 150,
            pyramidRestSeconds: rests
        )
        pyramid.session = session
        session.exercises = [pyramid]
        session.program = program
        program.sessions = [session]
        context.insert(program)
        return (program, session, pyramid)
    }

    func testPlanCarriesPerStepRestsAndStateMachineUsesThem() throws {
        let container = try TestStore.makeContainer()
        let (_, _, pyramid) = makeProgram(in: container.mainContext, rests: [20, 40, 75, 0, 300])
        let plan = WorkoutPlanBuilder.plan(for: pyramid)
        XCTAssertEqual(plan.pyramidRestSeconds, [20, 40, 75, 0, 300])
        XCTAssertEqual(plan.pyramidRest(afterStep: 2, repsDone: 6), 75)
        XCTAssertNil(plan.pyramidRest(afterStep: 4, repsDone: 2), "Pas de repos après le dernier palier")
    }

    func testPlanNormalizesMisalignedRests() throws {
        let container = try TestStore.makeContainer()
        let (_, _, pyramid) = makeProgram(in: container.mainContext, rests: [20, 9_999])
        XCTAssertEqual(WorkoutPlanBuilder.plan(for: pyramid).pyramidRestSeconds, [20, 600, 600, 600, 600])
    }

    func testExportRoundTripKeepsPerStepRests() throws {
        let source = try TestStore.makeContainer()
        _ = makeProgram(in: source.mainContext, rests: [30, 60, 90, 120, 0])
        try source.mainContext.save()
        let data = try ExportImport.exportAll(context: source.mainContext)

        let destination = try TestStore.makeContainer()
        _ = try ExportImport.importAll(data: data, context: destination.mainContext)
        let restored = try XCTUnwrap(destination.mainContext.fetch(FetchDescriptor<PrescribedExercise>()).first)
        XCTAssertEqual(restored.pyramidReps, [2, 4, 6, 4, 2])
        XCTAssertEqual(restored.pyramidRestSeconds, [30, 60, 90, 120, 0])
    }

    func testImportRejectsMisalignedOrOutOfRangeRests() throws {
        for rests in [[30, 60], [30, 60, 90, 120, 601], [30, 60, -5, 120, 0]] {
            let exercise = ExportImport.ExerciseDTO(
                id: UUID(), exerciseId: "Pullups", displayName: "Tractions", orderIndex: 0,
                formatRaw: SetFormat.pyramid.rawValue, sets: 0, repsLower: 0, repsUpper: 0,
                restSeconds: 0, percentOneRepMax: nil, percentMaxReps: nil, targetWeight: nil,
                pyramidReps: [2, 4, 6, 4, 2], pyramidMinRest: 30, pyramidMaxRest: 180,
                intervalWork: 0, intervalRest: 0, intervalRounds: 0,
                amrapSeconds: 0, notes: "",
                pyramidRestSeconds: rests
            )
            let program = ExportImport.ProgramDTO(
                id: UUID(), name: "Invalide", notes: "", isActive: false, createdAt: .now,
                sessions: [ExportImport.SessionDTO(
                    id: UUID(), name: "Jour 1", orderIndex: 0, warmupEnabled: false,
                    exercises: [exercise], groups: nil
                )]
            )
            let envelope = try encodedEnvelope(payload: ExportImport.Payload(programs: [program]))
            let container = try TestStore.makeContainer()
            XCTAssertThrowsError(try ExportImport.importAll(data: envelope, context: container.mainContext), "\(rests)")
            XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Program>()), 0)
        }
    }

    func testTemplateKeepsRestBoundsAndPerStepRests() throws {
        let container = try TestStore.makeContainer()
        let context = container.mainContext
        let (program, session, _) = makeProgram(in: context, rests: [30, 60, 90, 120, 0])
        let template = TemplateService.makeTemplate(from: session, in: context)
        let created = TemplateService.apply(template, to: program, in: context)
        let applied = try XCTUnwrap(created.first?.orderedExercises.first)
        XCTAssertEqual(applied.pyramidMinRest, 45)
        XCTAssertEqual(applied.pyramidMaxRest, 150)
        XCTAssertEqual(applied.pyramidRestSeconds, [30, 60, 90, 120, 0])
    }

    func testDuplicationKeepsPerStepRests() throws {
        let container = try TestStore.makeContainer()
        let (_, _, pyramid) = makeProgram(in: container.mainContext, rests: [30, 60, 90, 120, 0])
        XCTAssertEqual(pyramid.duplicated().pyramidRestSeconds, [30, 60, 90, 120, 0])
    }

    /// Meme enveloppe que `ExportImportTests` : somme de controle valide,
    /// pour que ce soit bien la validation des repos qui refuse l'archive.
    private func encodedEnvelope(payload: ExportImport.Payload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let canonical = try encoder.encode(payload)
        let envelope = ExportImport.Envelope(
            version: ExportImport.currentVersion,
            exportedAt: .now,
            manifest: ExportImport.Manifest(
                schemaVersion: 3,
                appVersion: "test",
                counts: [:],
                checksum: ExportImport.checksum(of: canonical)
            ),
            payload: payload
        )
        return try encoder.encode(envelope)
    }
}
