import XCTest
import SwiftData
import MuscuEngine
@testable import Muscu

@MainActor
final class TemplateServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUpWithError() throws {
        container = try TestStore.makeContainer()
    }

    override func tearDownWithError() throws {
        container = nil
    }

    @discardableResult
    private func makeProgram() -> Program {
        let program = Program(name: "Programme", isActive: true)
        context.insert(program)

        let session = ProgramSession(name: "Séance A", orderIndex: 0, warmupEnabled: true)
        session.program = program
        program.sessions.append(session)
        context.insert(session)

        let first = PrescribedExercise(
            exerciseId: "bench",
            displayName: "Développé couché",
            orderIndex: 0,
            sets: 4,
            repsLower: 6,
            repsUpper: 8,
            restSeconds: 120,
            targetWeight: 80
        )
        first.session = session
        session.exercises.append(first)
        context.insert(first)

        let second = PrescribedExercise(
            exerciseId: "row",
            displayName: "Rowing",
            orderIndex: 1,
            sets: 3,
            repsLower: 10,
            repsUpper: 12,
            restSeconds: 90
        )
        second.session = session
        session.exercises.append(second)
        context.insert(second)

        let group = ExerciseGroup(kindRaw: ExerciseGroupKind.superset.rawValue, orderIndex: 0, rounds: 3)
        group.session = session
        session.groups.append(group)
        context.insert(group)
        first.group = group
        second.group = group

        try? context.save()
        return program
    }

    func testTemplateFromSessionKeepsPrescriptionAndGroups() throws {
        let program = makeProgram()
        let session = try XCTUnwrap(program.orderedSessions.first)

        let template = TemplateService.makeTemplate(from: session, in: context)
        let payload = try XCTUnwrap(TemplateService.payload(of: template))

        XCTAssertEqual(payload.sessions.count, 1)
        XCTAssertEqual(payload.sessions[0].exercises.count, 2)
        XCTAssertEqual(payload.sessions[0].exercises[0].sets, 4)
        XCTAssertEqual(payload.sessions[0].exercises[0].targetWeight, 80)
        XCTAssertEqual(payload.sessions[0].groups.count, 1)
        XCTAssertEqual(payload.sessions[0].exercises[0].groupIndex, 0)
    }

    func testTemplateFromCompletedSessionDropsPerformances() throws {
        let completed = CompletedSession(programName: "P", sessionName: "Séance A", durationSeconds: 3_600)
        context.insert(completed)
        for index in 0..<3 {
            let set = CompletedSet(
                exerciseId: "bench",
                displayName: "Développé couché",
                orderIndex: 0,
                setIndex: index,
                weight: 92.5,
                reps: 7,
                loadTypeRaw: ExerciseLoadType.external.rawValue,
                roleRaw: SetRole.working.rawValue,
                sequenceIndex: index
            )
            set.session = completed
            completed.sets.append(set)
            context.insert(set)
        }
        let warmup = CompletedSet(
            exerciseId: "bench",
            displayName: "Développé couché",
            orderIndex: 0,
            setIndex: 0,
            weight: 40,
            reps: 10,
            isWarmup: true,
            roleRaw: SetRole.warmup.rawValue,
            sequenceIndex: 3
        )
        warmup.session = completed
        completed.sets.append(warmup)
        context.insert(warmup)
        try context.save()

        let template = TemplateService.makeTemplate(fromCompleted: completed, in: context)
        let payload = try XCTUnwrap(TemplateService.payload(of: template))
        let exercise = try XCTUnwrap(payload.sessions.first?.exercises.first)

        XCTAssertEqual(exercise.sets, 3, "Seules les séries de travail comptent")
        XCTAssertNil(exercise.targetWeight, "Aucune charge réalisée ne doit être recopiée")
        XCTAssertEqual(exercise.repsLower, 0)
        XCTAssertEqual(exercise.repsUpper, 0)
        XCTAssertTrue(template.notes.contains("ne sont pas reprises"))
    }

    func testApplyingATemplateAddsSessionsWithoutReplacing() throws {
        let program = makeProgram()
        let session = try XCTUnwrap(program.orderedSessions.first)
        let template = TemplateService.makeTemplate(from: session, in: context)

        let created = TemplateService.apply(template, to: program, in: context)

        XCTAssertEqual(created.count, 1)
        XCTAssertEqual(program.orderedSessions.count, 2)
        XCTAssertEqual(program.orderedSessions[0].name, "Séance A")
        let applied = program.orderedSessions[1]
        XCTAssertEqual(applied.orderedExercises.count, 2)
        XCTAssertEqual(applied.orderedGroups.count, 1)
        XCTAssertEqual(applied.orderedExercises[0].group?.id, applied.orderedGroups[0].id)
        XCTAssertNotNil(template.lastUsedAt)
    }

    func testSavingUnderTheSameNameCreatesANewVersion() throws {
        let program = makeProgram()
        let session = try XCTUnwrap(program.orderedSessions.first)

        let first = TemplateService.makeTemplate(from: session, in: context)
        let second = TemplateService.makeTemplate(from: session, in: context)

        XCTAssertEqual(first.version, 1)
        XCTAssertEqual(second.version, 2)
        XCTAssertEqual(TemplateService.templates(in: context).count, 2)
    }

    func testSharedFileRoundTripCarriesNoPersonalData() throws {
        let program = makeProgram()
        let session = try XCTUnwrap(program.orderedSessions.first)
        let template = TemplateService.makeTemplate(from: session, in: context)

        let data = try TemplateService.exportData(template)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(text.contains("token"))
        XCTAssertFalse(text.contains("iCloud"))
        XCTAssertFalse(text.contains(program.id.uuidString))

        let imported = try TemplateService.importTemplate(from: data, in: context)
        let payload = try XCTUnwrap(TemplateService.payload(of: imported))
        XCTAssertEqual(payload.sessions.first?.exercises.count, 2)
    }

    func testImportingAMalformedFileChangesNothing() throws {
        let before = TemplateService.templates(in: context).count
        XCTAssertThrowsError(try TemplateService.importTemplate(from: Data("pas du json".utf8), in: context))
        XCTAssertEqual(TemplateService.templates(in: context).count, before)
    }

    func testArchivedTemplatesAreHiddenByDefault() throws {
        let program = makeProgram()
        let session = try XCTUnwrap(program.orderedSessions.first)
        let template = TemplateService.makeTemplate(from: session, in: context)

        TemplateService.setArchived(template, true, in: context)

        XCTAssertTrue(TemplateService.templates(in: context).isEmpty)
        XCTAssertEqual(TemplateService.templates(in: context, includeArchived: true).count, 1)
    }
}

@MainActor
final class LibraryStoreTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUpWithError() throws {
        container = try TestStore.makeContainer()
    }

    override func tearDownWithError() throws {
        container = nil
    }

    func testFavoriteTogglesAndIsRemovedWhenEmpty() throws {
        XCTAssertTrue(LibraryStore.toggleFavorite("bench", in: context))
        XCTAssertTrue(LibraryStore.metadata(in: context).isFavorite("bench"))

        XCTAssertFalse(LibraryStore.toggleFavorite("bench", in: context))
        XCTAssertFalse(LibraryStore.metadata(in: context).isFavorite("bench"))
        XCTAssertTrue(LibraryStore.entries(in: context).isEmpty, "Une annotation vide ne doit pas rester")
    }

    func testTagsAreNormalisedOnce() throws {
        LibraryStore.setTags(["Épaules", "epaules", "  Poussée "], for: "ohp", in: context)
        let tags = LibraryStore.metadata(in: context).tags(for: "ohp")
        XCTAssertEqual(tags, ["epaules", "poussee"])
    }

    func testRecentlyUsedIsOrderedFromMostRecent() throws {
        let now = Date(timeIntervalSince1970: 1_770_000_000)
        LibraryStore.markUsed("bench", in: context, now: now)
        LibraryStore.markUsed("squat", in: context, now: now.addingTimeInterval(60))

        XCTAssertEqual(LibraryStore.recentlyUsed(in: context), ["squat", "bench"])
    }

    func testCollectionsAddAndRemoveWithoutDuplicates() throws {
        let collection = LibraryStore.createCollection(named: "Voyage", in: context)
        LibraryStore.add("pushup", to: collection, in: context)
        LibraryStore.add("pushup", to: collection, in: context)
        XCTAssertEqual(collection.exerciseIds, ["pushup"])

        LibraryStore.remove("pushup", from: collection, in: context)
        XCTAssertTrue(collection.exerciseIds.isEmpty)
    }

    func testDeletedCollectionIsHiddenButNotDestroyed() throws {
        let collection = LibraryStore.createCollection(named: "Voyage", in: context)
        LibraryStore.delete(collection, in: context)

        XCTAssertTrue(LibraryStore.collections(in: context).isEmpty)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ExerciseCollection>()).count, 1)
    }
}

@MainActor
final class PlaceStoreTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUpWithError() throws {
        container = try TestStore.makeContainer()
    }

    override func tearDownWithError() throws {
        container = nil
    }

    func testFirstPlaceBecomesDefault() throws {
        let home = PlaceStore.create(name: "Domicile", kind: .home, in: context)
        XCTAssertTrue(home.isDefault)

        let gym = PlaceStore.create(name: "Salle", kind: .gym, in: context)
        XCTAssertFalse(gym.isDefault)
        XCTAssertEqual(PlaceStore.defaultPlace(in: context)?.id, home.id)
    }

    func testOnlyOneDefaultPlaceAtATime() throws {
        let home = PlaceStore.create(name: "Domicile", kind: .home, in: context)
        let gym = PlaceStore.create(name: "Salle", kind: .gym, in: context)

        PlaceStore.makeDefault(gym, in: context)

        XCTAssertFalse(home.isDefault)
        XCTAssertTrue(gym.isDefault)
    }

    func testInventoryRoundTripsThroughStorage() throws {
        let place = PlaceStore.create(name: "Domicile", kind: .home, in: context)
        place.inventory = EquipmentInventory(items: [
            EquipmentAvailability(equipmentId: "dumbbell", minimumLoad: 2, maximumLoad: 24, increment: 2),
        ])
        try context.save()

        let reloaded = try XCTUnwrap(PlaceStore.place(id: place.id, in: context))
        XCTAssertEqual(reloaded.inventory.practicableLoad(17, equipmentId: "dumbbell"), 18)
        XCTAssertFalse(reloaded.inventory.allows(equipment: "barbell"))
    }

    func testUnknownPlaceYieldsAPermissiveInventory() throws {
        let inventory = PlaceStore.inventory(for: nil, in: context)
        XCTAssertTrue(inventory.isEmpty)
        XCTAssertTrue(inventory.allows(equipment: "machine"))
    }
}

/// Une substitution confirmée modifie le programme ; sans confirmation, rien
/// n'est écrit. L'historique n'est jamais touché dans un cas comme dans
/// l'autre.
@MainActor
final class ProgramEditingTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUpWithError() throws {
        container = try TestStore.makeContainer()
    }

    override func tearDownWithError() throws {
        container = nil
    }

    private func makePrescription() throws -> PrescribedExercise {
        let program = Program(name: "Programme")
        context.insert(program)
        let session = ProgramSession(name: "Séance A", orderIndex: 0)
        session.program = program
        program.sessions.append(session)
        context.insert(session)
        let exercise = PrescribedExercise(
            exerciseId: "bench",
            displayName: "Développé couché",
            orderIndex: 0,
            sets: 3,
            repsLower: 8,
            repsUpper: 10
        )
        exercise.session = session
        session.exercises.append(exercise)
        context.insert(exercise)
        try context.save()
        return exercise
    }

    func testConfirmedSubstitutionRewritesThePrescriptionOnly() throws {
        let prescription = try makePrescription()

        let history = CompletedSession(programName: "Programme", sessionName: "Séance A")
        context.insert(history)
        let set = CompletedSet(
            exerciseId: "bench",
            displayName: "Développé couché",
            orderIndex: 0,
            setIndex: 0,
            weight: 60,
            reps: 8,
            plannedExerciseId: "bench"
        )
        set.session = history
        history.sets.append(set)
        context.insert(set)
        try context.save()

        XCTAssertTrue(ProgramEditing.applySubstitution(
            prescriptionId: prescription.id,
            exerciseId: "db-press",
            displayName: "Développé haltères",
            in: context
        ))

        XCTAssertEqual(prescription.exerciseId, "db-press")
        XCTAssertEqual(prescription.displayName, "Développé haltères")
        XCTAssertEqual(set.exerciseId, "bench", "L’historique n’est jamais réécrit")
        XCTAssertEqual(set.plannedExerciseId, "bench")
    }

    func testSubstitutingAnUnknownPrescriptionChangesNothing() throws {
        let prescription = try makePrescription()

        XCTAssertFalse(ProgramEditing.applySubstitution(
            prescriptionId: UUID(),
            exerciseId: "db-press",
            displayName: "Développé haltères",
            in: context
        ))
        XCTAssertEqual(prescription.exerciseId, "bench")
    }
}
