import XCTest
import SwiftData
import MuscuEngine
@testable import Muscu

// MARK: - Plateaux

@MainActor
final class PlateauReviewTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let reference = Date(timeIntervalSince1970: 1_772_000_000)

    override func setUpWithError() throws {
        container = try TestStore.makeContainer()
    }

    override func tearDownWithError() throws {
        container = nil
    }

    @discardableResult
    private func makeProgram(targetWeight: Double? = 100) -> PrescribedExercise {
        let program = Program(name: "Programme", isActive: true)
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
            repsLower: 5,
            repsUpper: 5,
            targetWeight: targetWeight
        )
        exercise.session = session
        session.exercises.append(exercise)
        context.insert(exercise)
        try? context.save()
        return exercise
    }

    private func addSession(daysAgo: Int, weight: Double) {
        let session = CompletedSession(
            date: reference.addingTimeInterval(-Double(daysAgo) * 86_400),
            programName: "Programme",
            sessionName: "Séance A"
        )
        context.insert(session)
        for index in 0..<3 {
            let set = CompletedSet(
                exerciseId: "bench",
                displayName: "Développé couché",
                orderIndex: 0,
                setIndex: index,
                weight: weight,
                reps: 5,
                loadTypeRaw: ExerciseLoadType.external.rawValue,
                roleRaw: SetRole.working.rawValue,
                sequenceIndex: index
            )
            set.session = session
            session.sets.append(set)
            context.insert(set)
        }
        try? context.save()
    }

    func testStagnationIsDetectedAndExplained() throws {
        makeProgram()
        addSession(daysAgo: 21, weight: 100)
        addSession(daysAgo: 14, weight: 100)
        addSession(daysAgo: 7, weight: 100)

        let items = PlateauReview.findings(in: context)

        XCTAssertEqual(items.count, 1)
        let item = try XCTUnwrap(items.first)
        XCTAssertTrue(item.finding.isPlateau)
        XCTAssertFalse(item.finding.factors.isEmpty, "La détection doit dire sur quoi elle repose")
        XCTAssertTrue(item.finding.factors.joined().contains("seuil"))
    }

    func testRealProgressIsNotFlagged() throws {
        makeProgram()
        addSession(daysAgo: 21, weight: 100)
        addSession(daysAgo: 14, weight: 105)
        addSession(daysAgo: 7, weight: 112.5)

        XCTAssertTrue(PlateauReview.findings(in: context).isEmpty)
    }

    func testTooFewSessionsNeverCountAsAPlateau() throws {
        makeProgram()
        addSession(daysAgo: 14, weight: 100)
        addSession(daysAgo: 7, weight: 100)

        XCTAssertTrue(PlateauReview.findings(in: context).isEmpty)
    }

    func testDeloadReallyReducesAndStaysOnAvailableIncrements() {
        XCTAssertEqual(PlateauReview.deloadTarget(from: 100, increment: 2.5), 90)
        // L'arrondi vers le bas ne doit jamais rendre la décharge nulle.
        XCTAssertEqual(PlateauReview.deloadTarget(from: 20, increment: 5), 15)
        XCTAssertNil(PlateauReview.deloadTarget(from: nil, increment: 2.5))
        XCTAssertNil(PlateauReview.deloadTarget(from: 0, increment: 2.5))
    }

    func testAcceptingADeloadIsJournalledAndRevertible() throws {
        let prescription = makeProgram(targetWeight: 100)
        addSession(daysAgo: 21, weight: 100)
        addSession(daysAgo: 14, weight: 100)
        addSession(daysAgo: 7, weight: 100)

        let item = try XCTUnwrap(PlateauReview.findings(in: context).first)
        let entry = try XCTUnwrap(PlateauReview.acceptDeload(item, in: context))

        XCTAssertEqual(prescription.targetWeight, 90)
        XCTAssertEqual(entry.source, .plateau)
        XCTAssertEqual(entry.decision, .accepted)
        XCTAssertTrue(entry.canRevert)

        XCTAssertTrue(ProgressionReview.revert(entry, context: context))
        XCTAssertEqual(prescription.targetWeight, 100)
    }

    func testDecliningIsRememberedSoItIsNotProposedAgain() throws {
        makeProgram()
        addSession(daysAgo: 21, weight: 100)
        addSession(daysAgo: 14, weight: 100)
        addSession(daysAgo: 7, weight: 100)

        let item = try XCTUnwrap(PlateauReview.findings(in: context).first)
        PlateauReview.decline(item, in: context)

        XCTAssertTrue(PlateauReview.hasRecentDecision(exerciseId: "bench", in: context))
    }

    func testVariantChangesTheProgramButNotTheHistory() throws {
        let prescription = makeProgram()
        addSession(daysAgo: 21, weight: 100)
        addSession(daysAgo: 14, weight: 100)
        addSession(daysAgo: 7, weight: 100)

        let item = try XCTUnwrap(PlateauReview.findings(in: context).first)
        let replacement = CatalogExercise(id: "db-press", name: "DB Press", nameFr: "Développé haltères")
        let entry = try XCTUnwrap(PlateauReview.acceptVariant(item, replacement: replacement, in: context))

        XCTAssertEqual(prescription.exerciseId, "db-press")
        XCTAssertEqual(entry.source, .plateau)
        let sets = try context.fetch(FetchDescriptor<CompletedSet>())
        XCTAssertTrue(sets.allSatisfy { $0.exerciseId == "bench" }, "L’historique n’est jamais réécrit")
    }
}

// MARK: - Recalcul des semaines

@MainActor
final class PlanRecalculationServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        calendar.firstWeekday = 2
        return calendar
    }()

    override func setUpWithError() throws {
        container = try TestStore.makeContainer()
    }

    override func tearDownWithError() throws {
        container = nil
    }

    private func date(_ string: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)!
    }

    @discardableResult
    private func makePlan(settledWeeks: Int = 0, weekCount: Int = 4) -> TrainingPlan {
        let plan = TrainingPlan(
            name: "Plan",
            startDate: date("2026-01-05"),
            periodizationStyleRaw: PeriodizationStyle.linear.rawValue,
            deloadEveryWeeks: 4
        )
        context.insert(plan)

        let block = TrainingBlock(orderIndex: 0, name: "Accumulation")
        block.plan = plan
        plan.blocks.append(block)
        context.insert(block)

        for number in 1...weekCount {
            let week = TrainingWeek(
                weekNumber: number,
                startDate: date("2026-01-05").addingTimeInterval(Double(number - 1) * 7 * 86_400)
            )
            week.block = block
            block.weeks.append(week)
            context.insert(week)

            let workout = ScheduledWorkout(
                plannedDate: week.startDate.addingTimeInterval(18 * 3_600),
                displayName: "Séance \(number)"
            )
            workout.week = week
            week.scheduledWorkouts.append(workout)
            if number <= settledWeeks { workout.state = .completed }
            context.insert(workout)
        }
        try? context.save()
        return plan
    }

    func testSettledWeeksAreNeverMoved() throws {
        let plan = makePlan(settledWeeks: 2)
        let settledDates = plan.allWeeks.prefix(2).map(\.startDate)

        let preview = PlanRecalculationService.preview(
            for: plan,
            in: context,
            firstFutureWeekStart: date("2026-03-02"),
            calendar: calendar
        )
        PlanRecalculationService.apply(preview, to: plan, in: context, calendar: calendar)

        XCTAssertEqual(Array(plan.allWeeks.prefix(2).map(\.startDate)), Array(settledDates))
        XCTAssertEqual(preview.settledWeekNumbers, [1, 2])
    }

    func testFutureWorkoutsFollowTheirWeek() throws {
        let plan = makePlan(settledWeeks: 1)
        let futureWorkout = try XCTUnwrap(plan.allWeeks.first { $0.weekNumber == 2 }?.orderedWorkouts.first)
        let before = futureWorkout.plannedDate

        let preview = PlanRecalculationService.preview(
            for: plan,
            in: context,
            firstFutureWeekStart: date("2026-01-19"),
            calendar: calendar
        )
        let moved = PlanRecalculationService.apply(preview, to: plan, in: context, calendar: calendar)

        XCTAssertGreaterThan(moved, 0)
        XCTAssertNotEqual(futureWorkout.plannedDate, before)
        // L'heure locale de la séance est conservée : seul le jour bouge.
        XCTAssertEqual(
            calendar.component(.hour, from: futureWorkout.plannedDate),
            calendar.component(.hour, from: before)
        )
    }

    func testCompletedHistoryIsNeverTouched() throws {
        let plan = makePlan(settledWeeks: 1)
        let history = CompletedSession(date: date("2026-01-06"), programName: "Plan", sessionName: "Séance 1")
        context.insert(history)
        try context.save()

        let preview = PlanRecalculationService.preview(
            for: plan,
            in: context,
            firstFutureWeekStart: date("2026-02-02"),
            calendar: calendar
        )
        PlanRecalculationService.apply(preview, to: plan, in: context, calendar: calendar)

        XCTAssertEqual(history.date, date("2026-01-06"))
        XCTAssertEqual(history.revision, 1)
    }

    func testApplyingBumpsThePlanVersion() throws {
        let plan = makePlan()
        let version = plan.version

        let preview = PlanRecalculationService.preview(
            for: plan,
            in: context,
            firstFutureWeekStart: date("2026-02-02"),
            calendar: calendar
        )
        PlanRecalculationService.apply(preview, to: plan, in: context, calendar: calendar)

        XCTAssertEqual(plan.version, version + 1)
    }

    func testAWeekWithAStartedWorkoutIsConsideredSettled() throws {
        let plan = makePlan()
        let week = try XCTUnwrap(plan.allWeeks.first)
        week.orderedWorkouts.first?.state = .started
        try context.save()

        XCTAssertTrue(PlanRecalculationService.isSettled(week))
    }
}

// MARK: - Photos de progression

@MainActor
final class ProgressPhotoTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUpWithError() throws {
        container = try TestStore.makeContainer()
        PhotoStore.deleteAll()
    }

    override func tearDownWithError() throws {
        PhotoStore.deleteAll()
        container = nil
    }

    /// Image minimale, générée au lieu d'être embarquée : un test ne doit pas
    /// dépendre d'un fichier binaire de plus.
    private func sampleImageData(side: CGFloat = 2_400) -> Data {
        // Echelle 1 : la taille demandee est bien celle des pixels produits,
        // sans quoi le test dependrait de l'ecran du simulateur.
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side / 2), format: format)
        let image = renderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side / 2))
        }
        return image.pngData()!
    }

    func testAddingAPhotoStoresItOutsideTheDatabase() throws {
        let photo = try ProgressPhotoStore.add(imageData: sampleImageData(), in: context)

        XCTAssertFalse(photo.assetName.isEmpty)
        XCTAssertGreaterThan(photo.byteCount, 0)
        XCTAssertNotNil(PhotoStore.data(for: photo.assetName))
        XCTAssertEqual(ProgressPhotoStore.photos(in: context).count, 1)
    }

    func testLargeImagesAreDownscaled() throws {
        let photo = try ProgressPhotoStore.add(imageData: sampleImageData(side: 4_000), in: context)
        let data = try XCTUnwrap(PhotoStore.data(for: photo.assetName))
        let image = try XCTUnwrap(UIImage(data: data))

        XCTAssertLessThanOrEqual(max(image.size.width, image.size.height), PhotoStore.maximumDimension)
        XCTAssertGreaterThan(max(image.size.width, image.size.height), PhotoStore.maximumDimension / 2, "Une image réduite à l’excès perdrait toute lisibilité")
    }

    func testUnreadableDataIsRefused() {
        XCTAssertThrowsError(try ProgressPhotoStore.add(imageData: Data("pas une image".utf8), in: context))
        XCTAssertTrue(ProgressPhotoStore.photos(in: context).isEmpty)
    }

    func testDeletingRemovesTheFileToo() throws {
        let photo = try ProgressPhotoStore.add(imageData: sampleImageData(), in: context)
        let name = photo.assetName

        ProgressPhotoStore.delete(photo, in: context)

        XCTAssertNil(PhotoStore.data(for: name))
        XCTAssertTrue(ProgressPhotoStore.photos(in: context).isEmpty)
        XCTAssertTrue(ProgressPhotoStore.orphanAssetNames(in: context).isEmpty)
    }

    /// La roadmap l'exige : les photos ne partent pas dans l'export par
    /// défaut.
    func testPhotosAreNotIncludedInTheExport() throws {
        try ProgressPhotoStore.add(imageData: sampleImageData(), note: "secret", in: context)

        let data = try ExportImport.exportAll(context: context)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertFalse(text.contains("secret"))
        XCTAssertFalse(text.contains(".jpg"))
        XCTAssertFalse(text.contains("progressPhotos"))
    }

    func testDeletingMeasurementsAlsoDeletesPhotoFiles() throws {
        let photo = try ProgressPhotoStore.add(imageData: sampleImageData(), in: context)
        let name = photo.assetName

        _ = try DataDeletion.delete(.measurements, context: context)

        XCTAssertNil(PhotoStore.data(for: name))
        XCTAssertTrue(ProgressPhotoStore.photos(in: context).isEmpty)
    }
}

// MARK: - Test de 1RM

@MainActor
final class OneRepMaxTestReferenceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUpWithError() throws {
        container = try TestStore.makeContainer()
    }

    override func tearDownWithError() throws {
        container = nil
    }

    func testWithoutAnyRecordThereIsNoReference() {
        XCTAssertNil(OneRepMaxTestReference.value(exerciseId: "bench", in: context))
    }

    func testKnownRecordIsUsedAsReference() throws {
        context.insert(ExerciseRecord(exerciseId: "bench", displayName: "Développé", oneRepMax: 120))
        try context.save()

        XCTAssertEqual(OneRepMaxTestReference.value(exerciseId: "bench", in: context), 120)
    }

    func testTestedResultReplacesTheEstimate() throws {
        context.insert(ExerciseRecord(exerciseId: "bench", displayName: "Développé", oneRepMax: 120))
        try context.save()

        OneRepMaxTestReference.record(
            testedOneRepMax: 115,
            exerciseId: "bench",
            displayName: "Développé",
            in: context
        )

        let record = try XCTUnwrap(try context.fetch(FetchDescriptor<ExerciseRecord>()).first)
        XCTAssertEqual(record.oneRepMax, 115, "Une valeur mesurée l’emporte sur une extrapolation")
    }

    func testTestedResultCreatesAMeasuredPersonalBest() throws {
        OneRepMaxTestReference.record(
            testedOneRepMax: 140,
            exerciseId: "squat",
            displayName: "Squat",
            in: context
        )

        let bests = try context.fetch(FetchDescriptor<PersonalBest>())
        XCTAssertEqual(bests.count, 1)
        XCTAssertEqual(bests.first?.kind, .maxWeight)
        XCTAssertEqual(bests.first?.reps, 1)
        XCTAssertEqual(bests.first?.value, 140)
    }

    func testASecondLowerTestDoesNotLowerThePersonalBest() throws {
        OneRepMaxTestReference.record(testedOneRepMax: 140, exerciseId: "squat", displayName: "Squat", in: context)
        OneRepMaxTestReference.record(testedOneRepMax: 130, exerciseId: "squat", displayName: "Squat", in: context)

        let bests = try context.fetch(FetchDescriptor<PersonalBest>())
        XCTAssertEqual(bests.count, 1)
        XCTAssertEqual(bests.first?.value, 140, "Un record maximal ne redescend pas")
        // Le record d'exercice, lui, suit la dernière mesure : c'est lui qui
        // alimente les pourcentages du runner.
        XCTAssertEqual(try context.fetch(FetchDescriptor<ExerciseRecord>()).first?.oneRepMax, 130)
    }
}
