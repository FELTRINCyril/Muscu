import XCTest
import SwiftData
import MuscuEngine
@testable import Muscu

/// La semaine de décharge doit RÉELLEMENT alléger la séance.
///
/// `Periodization` calculait ses multiplicateurs, `TrainingPlanView` les
/// affichait, et personne ne les appliquait : une semaine de décharge était
/// une étiquette. Ces tests protègent le chaînon manquant.
@MainActor
final class WeekScalingResolverTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        container = try TestStore.makeContainer()
        context = ModelContext(container)
    }

    override func tearDown() async throws {
        container = nil
        context = nil
        try await super.tearDown()
    }

    /// Monte un plan dont la semaine porte les multiplicateurs donnés, et
    /// renvoie la séance de programme qui lui est rattachée.
    @discardableResult
    private func makePlan(volume: Double, intensity: Double) -> ProgramSession {
        let exercise = PrescribedExercise(
            exerciseId: "squat",
            displayName: "Squat",
            orderIndex: 0,
            sets: 4,
            repsLower: 8,
            repsUpper: 10,
            restSeconds: 120
        )
        exercise.targetWeight = 100

        let session = ProgramSession(name: "Séance A", orderIndex: 0, exercises: [exercise])
        let program = Program(name: "Programme")
        program.sessions = [session]
        context.insert(program)

        let scheduled = ScheduledWorkout(plannedDate: .now, programSessionId: session.id)
        let week = TrainingWeek(
            weekNumber: 1,
            volumeMultiplier: volume,
            intensityMultiplier: intensity,
            scheduledWorkouts: [scheduled]
        )
        let block = TrainingBlock(orderIndex: 0)
        block.weeks = [week]
        let plan = TrainingPlan(name: "Plan", programId: program.id)
        plan.blocks = [block]
        context.insert(plan)

        let profile = AthleteProfile()
        profile.availableIncrementsKilograms = [2.5, 5]
        context.insert(profile)

        try? context.save()
        return session
    }

    func testAnOrdinaryWeekScalesNothing() {
        let session = makePlan(volume: 1, intensity: 1)
        let scaling = WeekScalingResolver.scaling(for: session, context: context)
        XCTAssertTrue(scaling.isNeutral)
    }

    /// Le cœur du défaut corrigé : une semaine de décharge réduit vraiment
    /// les séries ET la charge de la séance exécutée.
    func testADeloadWeekReallyReducesTheSessionThatIsRun() {
        let session = makePlan(volume: 0.5, intensity: 0.9)
        let scaling = WeekScalingResolver.scaling(for: session, context: context)
        XCTAssertFalse(scaling.isNeutral, "La semaine de décharge doit être détectée")

        let plan = scaling.applied(
            to: WorkoutPlanBuilder.plan(for: session, catalogStore: nil, customExercises: [])
        )
        let scaled = try? XCTUnwrap(plan.allExercises.first)
        XCTAssertEqual(scaled?.setCount, 2, "4 séries à 50 % doivent devenir 2")
        XCTAssertEqual(scaled?.targetWeight, 90, "100 kg à 90 % doivent devenir 90")
    }

    /// Une séance hors plan ne doit jamais être allégée par accident.
    func testASessionOutsideAnyPlanIsNeverScaled() {
        let exercise = PrescribedExercise(exerciseId: "squat", displayName: "Squat", orderIndex: 0, sets: 4)
        let session = ProgramSession(name: "Libre", orderIndex: 0, exercises: [exercise])
        let program = Program(name: "Sans plan")
        program.sessions = [session]
        context.insert(program)
        try? context.save()

        XCTAssertTrue(WeekScalingResolver.scaling(for: session, context: context).isNeutral)
    }

    /// Une séance déjà terminée n'est plus une candidate : la décharge ne
    /// doit pas « suivre » une séance passée.
    func testACompletedScheduledWorkoutIsNotUsedToScaleANewSession() {
        let session = makePlan(volume: 0.5, intensity: 0.9)
        let workouts = (try? context.fetch(FetchDescriptor<ScheduledWorkout>())) ?? []
        for workout in workouts { workout.state = .completed }
        try? context.save()

        XCTAssertTrue(WeekScalingResolver.scaling(for: session, context: context).isNeutral)
    }

    /// La charge est arrondie au palier réellement disponible : personne ne
    /// charge 47,3 kg sur une barre.
    func testTheScaledLoadUsesTheAthletesOwnIncrements() {
        let session = makePlan(volume: 1, intensity: 0.93)
        let scaling = WeekScalingResolver.scaling(for: session, context: context)
        let plan = scaling.applied(
            to: WorkoutPlanBuilder.plan(for: session, catalogStore: nil, customExercises: [])
        )
        let weight = plan.allExercises.first?.targetWeight
        XCTAssertEqual(weight, 92.5, "93 kg doivent être ramenés au palier de 2,5 kg le plus proche")
    }
}
