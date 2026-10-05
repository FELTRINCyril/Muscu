import XCTest
import SwiftData
import MuscuEngine
@testable import Muscu

/// Lot 4 : seance passee corrigee, refaite, partagee ; programme mis a jour
/// apres une seance modifiee ; import CSV vers programmes.
@MainActor
final class HistoryLot4Tests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let reference = Date(timeIntervalSince1970: 1_780_000_000)

    override func setUp() async throws {
        container = try TestStore.makeContainer()
        HealthSettings.reset()
        SyncOutboxFeeder.isEnabled = false
    }

    override func tearDown() async throws {
        HealthSettings.reset()
        SyncOutboxFeeder.isEnabled = false
        container = nil
    }

    // MARK: - Aides

    @discardableResult
    private func addSession(
        _ name: String = "Push",
        daysAgo: Int,
        sets: [(String, Double, Int)],
        duration: Int = 3_600
    ) -> CompletedSession {
        let session = CompletedSession(
            date: reference.addingTimeInterval(Double(-daysAgo) * 86_400),
            programName: "",
            sessionName: name,
            durationSeconds: duration
        )
        context.insert(session)
        var orderByExercise: [String: Int] = [:]
        for (sequence, value) in sets.enumerated() {
            let order = orderByExercise[value.0] ?? orderByExercise.count
            orderByExercise[value.0] = order
            let setIndex = session.sets.filter { $0.exerciseId == value.0 }.count
            let set = CompletedSet(
                exerciseId: value.0,
                displayName: value.0.capitalized,
                orderIndex: order,
                setIndex: setIndex,
                weight: value.1,
                reps: value.2,
                loadTypeRaw: ExerciseLoadType.external.rawValue,
                roleRaw: SetRole.working.rawValue,
                sequenceIndex: sequence,
                actualRestSeconds: sequence == 0 ? nil : 120
            )
            context.insert(set)
            set.session = session
            session.sets.append(set)
        }
        try? context.save()
        // Records comme a la fin d'une seance.
        PersonalBestUpdater.apply(
            candidates: PersonalBestUpdater.candidates(for: session),
            context: context,
            sourceSessionId: session.id,
            achievedAt: session.date
        )
        try? context.save()
        return session
    }

    private func liveBest(_ exerciseId: String, _ kind: PersonalBestKind) -> PersonalBest? {
        ((try? context.fetch(FetchDescriptor<PersonalBest>())) ?? []).first {
            $0.exerciseId == exerciseId && $0.kind == kind && $0.configurationKey.isEmpty && $0.deletedAt == nil
        }
    }

    private func edit(
        _ session: CompletedSession,
        now: Date? = nil,
        _ change: (inout PastSessionEditor.Draft) -> Void
    ) -> Bool {
        var draft = PastSessionEditor.draft(for: session)
        change(&draft)
        let changes = PastSessionEditor.recordChanges(for: session, draft: draft, in: context)
        return PastSessionEditor.apply(draft, to: session, recordChanges: changes, in: context, now: now ?? reference)
    }

    // MARK: - Correction et records

    func testLoweredSetRecomputesRecordFromHistory() throws {
        let older = addSession(daysAgo: 7, sets: [("squat", 100, 5)])
        let recent = addSession(daysAgo: 1, sets: [("squat", 120, 5)])
        XCTAssertEqual(liveBest("squat", .maxWeight)?.value, 120)

        XCTAssertTrue(edit(recent) { $0.exercises[0].sets[0].weight = 90 })

        let best = try XCTUnwrap(liveBest("squat", .maxWeight))
        XCTAssertEqual(best.value, 100, "Le record redescend à la meilleure valeur encore justifiée")
        XCTAssertEqual(best.sourceSessionId, older.id)
        XCTAssertEqual(recent.editedAt, reference)
        XCTAssertEqual(recent.revision, 2)
    }

    func testDeletedSetWithoutHistoryRemovesRecord() throws {
        let session = addSession(daysAgo: 1, sets: [("squat", 120, 5), ("bench", 80, 8)])
        XCTAssertNotNil(liveBest("bench", .maxWeight))

        XCTAssertTrue(edit(session) { draft in
            draft.exercises.removeAll { $0.exerciseId == "bench" }
        })

        XCTAssertNil(liveBest("bench", .maxWeight), "Plus aucune séance ne justifie ce record")
        XCTAssertEqual(session.sets.count, 1)
        XCTAssertEqual(liveBest("squat", .maxWeight)?.value, 120, "Les autres records ne bougent pas")
    }

    func testForeignRecordNeverRegressesAndEditCanImprove() throws {
        let best = addSession(daysAgo: 7, sets: [("squat", 140, 3)])
        let other = addSession(daysAgo: 1, sets: [("squat", 100, 5)])

        XCTAssertTrue(edit(other) { $0.exercises[0].sets[0].weight = 90 })
        XCTAssertEqual(liveBest("squat", .maxWeight)?.value, 140)
        XCTAssertEqual(liveBest("squat", .maxWeight)?.sourceSessionId, best.id)

        XCTAssertTrue(edit(other) { $0.exercises[0].sets[0].weight = 150 })
        XCTAssertEqual(liveBest("squat", .maxWeight)?.value, 150)
        XCTAssertEqual(liveBest("squat", .maxWeight)?.sourceSessionId, other.id)
    }

    func testConfirmedOneRepMaxFollowsItsSessionButNeverRises() throws {
        addSession(daysAgo: 7, sets: [("squat", 100, 5)])
        let recent = addSession(daysAgo: 1, sets: [("squat", 120, 5)])
        let estimate = try XCTUnwrap(SetMetrics.estimatedOneRepMax(SetMetricsInput(weightKilograms: 120, reps: 5, loadKind: .external)))
        let olderEstimate = try XCTUnwrap(SetMetrics.estimatedOneRepMax(SetMetricsInput(weightKilograms: 100, reps: 5, loadKind: .external)))
        let record = ExerciseRecord(exerciseId: "squat", displayName: "Squat", oneRepMax: estimate)
        let manual = ExerciseRecord(exerciseId: "bench", displayName: "Bench", oneRepMax: 200)
        context.insert(record)
        context.insert(manual)
        try context.save()

        XCTAssertTrue(edit(recent) { $0.exercises[0].sets[0].weight = 80 })

        XCTAssertEqual(try XCTUnwrap(record.oneRepMax), olderEstimate, accuracy: 0.001)
        XCTAssertEqual(manual.oneRepMax, 200, "Un 1RM saisi à la main n'est pas touché")
    }

    func testAddedSetsAndExercisesHaveNoInventedRest() throws {
        let session = addSession(daysAgo: 1, sets: [("squat", 100, 5), ("squat", 100, 5)])
        XCTAssertNotNil(SessionReplayBuilder.timeBreakdown(for: session))

        XCTAssertTrue(edit(session) { draft in
            draft.exercises[0].sets.append(PastSessionEditor.newSet(for: draft.exercises[0]))
            draft.exercises.append(PastSessionEditor.newExercise(exerciseId: "row", displayName: "Rowing", loadKind: .external))
            draft.exercises[1].sets[0].weight = 60
            draft.exercises[1].sets[0].reps = 10
        })

        let added = session.sets.filter { $0.sequenceIndex >= 2 }
        XCTAssertEqual(added.count, 2)
        XCTAssertTrue(added.allSatisfy { $0.actualRestSeconds == nil })
        XCTAssertEqual(session.sets.first { $0.exerciseId == "row" }?.orderIndex, 1)
        XCTAssertEqual(session.sets.filter { $0.exerciseId == "squat" }.map(\.setIndex).sorted(), [0, 1, 2])
        XCTAssertNil(SessionReplayBuilder.timeBreakdown(for: session), "Un repos inconnu masque la répartition")
    }

    func testInvalidTimingIsRefusedAndNothingChanges() {
        let session = addSession(daysAgo: 1, sets: [("squat", 100, 5)])
        let originalDate = session.date

        XCTAssertFalse(edit(session) { draft in draft.end = draft.start.addingTimeInterval(-60) })
        XCTAssertEqual(session.date, originalDate)
        XCTAssertNil(session.editedAt)
    }

    func testTimingAndEffortAreSaved() {
        let session = addSession(daysAgo: 1, sets: [("squat", 100, 5)])
        let start = session.date.addingTimeInterval(-5_400)

        XCTAssertTrue(edit(session) { draft in
            draft.start = start
            draft.effortRating = 8
        })

        XCTAssertEqual(session.durationSeconds, 5_400)
        XCTAssertEqual(PastSessionEditor.interval(of: session).start, start)
        XCTAssertEqual(session.effortRating, 8)
    }

    func testDeletingASessionRecomputesItsRecords() {
        let older = addSession(daysAgo: 7, sets: [("squat", 100, 5)])
        let recent = addSession(daysAgo: 1, sets: [("squat", 120, 5)])

        XCTAssertTrue(PastSessionEditor.delete(recent, in: context))
        XCTAssertEqual(liveBest("squat", .maxWeight)?.value, 100)
        XCTAssertEqual(liveBest("squat", .maxWeight)?.sourceSessionId, older.id)
    }

    // MARK: - Synchronisation et Santé

    func testEditedSessionIsQueuedAndCarriesItsCorrectionDate() throws {
        let session = addSession(daysAgo: 1, sets: [("squat", 100, 5)])
        SyncOutboxFeeder.isEnabled = true

        XCTAssertTrue(edit(session, now: .now) { $0.exercises[0].sets[0].reps = 6 })

        let outbox = SyncService.state(in: context).outbox
        XCTAssertTrue(outbox.ready(at: .now.addingTimeInterval(3_600)).contains { $0.identifier == session.id })
        let record = try XCTUnwrap(SyncSerialization.localRecords(context: context)[session.id])
        XCTAssertNotNil(record.editedAt)
    }

    func testHealthWorkoutIsReplacedAfterACorrection() async throws {
        let session = addSession(daysAgo: 1, sets: [("squat", 100, 5)])
        HealthSettings.isEnabled = true
        let store = InMemoryHealthStore(status: .authorized)
        let first = await HealthSyncService.synchronize(in: context, store: store, now: reference.addingTimeInterval(-3_600))
        XCTAssertEqual(first.written, 1)
        let original = store.writtenWorkoutIdentifiers

        XCTAssertTrue(edit(session) { draft in draft.start = draft.start.addingTimeInterval(-600) })
        let second = await HealthSyncService.synchronize(in: context, store: store, now: reference.addingTimeInterval(60))

        XCTAssertEqual(second.written, 1)
        XCTAssertEqual(second.deleted, 1)
        XCTAssertEqual(store.writtenWorkoutIdentifiers.count, 1, "Jamais deux entraînements pour une séance")
        XCTAssertTrue(store.containsWorkout(for: session.id))
        XCTAssertEqual(original.count, 1)

        let third = await HealthSyncService.synchronize(in: context, store: store, now: reference.addingTimeInterval(120))
        XCTAssertEqual(third.written, 0)
        XCTAssertEqual(third.alreadyWritten, 1)
    }

    // MARK: - Refaire et partager

    func testReplayStartsAPrefilledFreeSession() throws {
        let session = addSession("Jambes", daysAgo: 1, sets: [("squat", 100, 5), ("squat", 100, 5), ("lunge", 20, 10)])

        let plan = SessionReplayBuilder.plan(for: session, mode: .withTargets, catalogStore: CatalogStore(), context: context)
        let state = WorkoutState(
            freeSessionWith: context,
            catalogStore: CatalogStore(),
            restTimer: RestTimer(),
            replaying: plan,
            title: session.sessionName
        )

        XCTAssertTrue(state.isFreeSession)
        XCTAssertEqual(state.sessionTitle, "Jambes")
        XCTAssertEqual(state.currentTarget?.exercise.exerciseId, "squat")
        XCTAssertEqual(state.currentTarget?.exercise.targetWeight, 100)
        XCTAssertEqual(state.currentTarget?.totalSets, 2)

        let empty = SessionReplayBuilder.plan(for: session, mode: .empty, catalogStore: CatalogStore(), context: context)
        XCTAssertNil(empty.allExercises[0].targetWeight)
        XCTAssertEqual(empty.allExercises.map(\.setCount), [2, 1])

        // Le titre survit a une reprise.
        let active = try XCTUnwrap(context.fetch(FetchDescriptor<ActiveWorkout>()).first)
        let resumed = try XCTUnwrap(WorkoutState.resume(from: active, modelContext: context, catalogStore: CatalogStore(), restTimer: RestTimer()))
        XCTAssertEqual(resumed.sessionTitle, "Jambes")
    }

    func testShareSummaryTellsOnlyWhatIsShown() {
        let session = addSession("Push", daysAgo: 1, sets: [("bench", 80, 8), ("bench", 80, 7)])
        session.notes = "note privée"
        session.avgHeartRate = 142
        let bests = (try? context.fetch(FetchDescriptor<PersonalBest>())) ?? []

        let summary = SessionShareSummary.make(for: session, records: bests, unit: .kilograms)
        let text = summary.text

        XCTAssertTrue(text.contains("Push"))
        XCTAssertTrue(text.contains("Bench"))
        XCTAssertEqual(summary.exercises.first?.sets.count, 2)
        XCTAssertFalse(summary.records.isEmpty)
        XCTAssertFalse(text.contains("note privée"))
        XCTAssertFalse(text.contains("142"))
    }

    // MARK: - Programme apres une seance modifiee

    private func makeProgramSession() throws -> ProgramSession {
        let exercises = ["squat", "bench", "row"].enumerated().map { index, name in
            PrescribedExercise(
                exerciseId: name,
                displayName: name.capitalized,
                orderIndex: index,
                sets: 3,
                repsLower: 8,
                repsUpper: 10,
                restSeconds: 90,
                targetWeight: 50,
                loadKindRaw: LoadKind.external.rawValue
            )
        }
        let session = ProgramSession(name: "Full", orderIndex: 0, exercises: exercises)
        context.insert(Program(name: "Prog", sessions: [session]))
        try context.save()
        return session
    }

    func testUnchangedSessionProposesNothing() throws {
        let programSession = try makeProgramSession()
        let state = WorkoutState(programSession: programSession, modelContext: context, catalogStore: CatalogStore(), restTimer: RestTimer())
        XCTAssertTrue(state.structureChanges.isEmpty)
    }

    func testStructureChangesUpdateTheProgramButNeverItsLoads() throws {
        let programSession = try makeProgramSession()
        let state = WorkoutState(programSession: programSession, modelContext: context, catalogStore: CatalogStore(), restTimer: RestTimer())
        state.finishWarmup()
        state.addSet()
        state.logSet(weight: 120, reps: 5)
        state.addExercise(exerciseId: "curl", displayName: "Curl")

        let changes = state.structureChanges
        XCTAssertEqual(changes.count, 2)
        let baseline = try XCTUnwrap(state.structureBaseline)

        XCTAssertTrue(ProgramEditing.applyStructure(of: state.plan, baseline: baseline, to: programSession, in: context))

        let ordered = programSession.orderedExercises
        XCTAssertEqual(ordered.map(\.exerciseId), ["squat", "bench", "row", "curl"])
        XCTAssertEqual(ordered[0].sets, 4)
        XCTAssertEqual(ordered[0].targetWeight, 50, "Une charge réalisée n'est jamais recopiée")
        XCTAssertEqual(ordered[3].sets, 3)
    }

    func testSetCountDeltaIgnoresDeloadScaling() {
        XCTAssertEqual(ProgramEditing.adjustedCount(prescribed: 4, baseline: 2, final: 3), 5)
        XCTAssertEqual(ProgramEditing.adjustedCount(prescribed: 4, baseline: 2, final: 2), 4)
        XCTAssertEqual(ProgramEditing.adjustedCount(prescribed: 1, baseline: 3, final: 1), 1)
        XCTAssertEqual(ProgramEditing.adjustedCount(prescribed: 4, baseline: nil, final: 2), 4)
    }

    func testModifiedSessionCanBecomeATemplate() throws {
        let programSession = try makeProgramSession()
        let state = WorkoutState(programSession: programSession, modelContext: context, catalogStore: CatalogStore(), restTimer: RestTimer())
        state.finishWarmup()
        state.replaceExercise(exerciseId: "dips", displayName: "Dips")
        let baseline = try XCTUnwrap(state.structureBaseline)

        let template = TemplateService.makeTemplate(fromPlan: state.plan, baseline: baseline, programSession: programSession, in: context)
        let payload = try XCTUnwrap(TemplateService.payload(of: template))
        XCTAssertEqual(payload.sessions.first?.exercises.map(\.exerciseId), ["dips", "bench", "row"])
        XCTAssertEqual(programSession.orderedExercises.first?.exerciseId, "squat", "Le programme reste inchangé")
    }

    // MARK: - Import CSV vers programmes

    func testEquipmentSuffixGuidesTheCatalogMatch() throws {
        let catalog = try ExerciseCatalog.load()
        let barbell = try XCTUnwrap(CSVImportService.resolveExercise(named: "Deadlift (Barbell)", catalog: catalog))
        XCTAssertEqual(barbell.equipment, "barbell")
        let cable = try XCTUnwrap(CSVImportService.resolveExercise(named: "Deadlift (Cable)", catalog: catalog))
        XCTAssertEqual(cable.equipment, "cable")
    }

    func testImportedTitlesBecomeTemplatesOrAProgram() throws {
        let csv = """
        Date,Workout Name,Exercise Name,Set Order,Weight,Reps,Notes
        2026-01-05 18:00:00,Jambes,Squat,1,100,5,
        2026-01-05 18:00:00,Jambes,Squat,2,100,5,
        2026-01-05 18:00:00,Jambes,Squat,3,100,5,
        2026-01-08 18:00:00,Jambes,Squat,1,100,5,
        2026-01-08 18:00:00,Jambes,Squat,2,100,5,
        2026-01-08 18:00:00,Jambes,Squat,3,100,5,
        2026-01-08 18:00:00,Jambes,Exercice inconnu xyz,1,10,10,
        """
        let catalog = try ExerciseCatalog.load()
        let rows = try CSVImportService.makeParser(for: csv).parse(csv)
        let header = rows[0]
        let preset = CSVImportPreset.detect(header: header)
        let plan = CSVImportPlanner.plan(
            rows: rows,
            mapping: ColumnMapping.suggested(header: header, preset: preset),
            existingSignatures: [],
            calendar: .current,
            timeZone: .current
        )
        let outcome = CSVImportService.apply(plan, policy: .skipDuplicates, sourceName: "Strong", catalog: catalog, in: context)
        XCTAssertTrue(outcome.didWrite)

        let candidates = CSVImportService.routineCandidates(for: outcome, in: context)
        let legs = try XCTUnwrap(candidates.first)
        XCTAssertEqual(legs.name, "Jambes")
        XCTAssertEqual(legs.sessionCount, 2)
        XCTAssertEqual(legs.exercises.count, 1, "Un exercice non reconnu n'est pas prescrit")
        XCTAssertEqual(legs.exercises.first?.workingSetCount, 3)

        XCTAssertEqual(CSVImportService.createRoutines([legs], destination: .templates, programName: "", in: context), 1)
        XCTAssertEqual(CSVImportService.createRoutines([legs], destination: .templates, programName: "", in: context), 1)
        let names = TemplateService.templates(in: context).map(\.name).sorted()
        XCTAssertEqual(names, ["Jambes", "Jambes (2)"], "Un nom existant n'est jamais écrasé")

        XCTAssertEqual(CSVImportService.createRoutines([legs], destination: .newProgram, programName: "Import", in: context), 1)
        let program = try XCTUnwrap(context.fetch(FetchDescriptor<Program>()).first { $0.name == "Import" })
        XCTAssertFalse(program.isActive)
        XCTAssertEqual(program.sessions.first?.exercises.first?.sets, 3)
        XCTAssertNil(program.sessions.first?.exercises.first?.targetWeight)
    }
}
