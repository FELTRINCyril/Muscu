import Foundation
import Testing
@testable import MuscuEngine

@Suite
struct PlanGeneratorTests {
    private let catalog = try! ExerciseCatalog.load()
    private let startDate = Date(timeIntervalSince1970: 1_757_030_400) // mercredi 4 septembre 2025 UTC

    private func input(
        goal: Goal = .hypertrophy,
        experience: Experience = .intermediate,
        days: Int = 4,
        minutes: Int = 60,
        equipment: TrainingEquipment = .fullGym,
        priority: [String] = [],
        avoid: [String] = [],
        excluded: [String] = []
    ) -> GeneratorInput {
        GeneratorInput(
            goal: goal,
            experience: experience,
            daysPerWeek: days,
            sessionMinutes: minutes,
            equipment: equipment,
            splitPreference: .auto,
            priorityMuscles: priority,
            avoidAreas: avoid,
            excludedExerciseIds: excluded
        )
    }

    private func planInput(
        _ base: GeneratorInput? = nil,
        weeks: Int = 8,
        style: PeriodizationStyle = .linear,
        deloadEvery: Int? = 4,
        weekdays: [Int] = []
    ) -> PlanGeneratorInput {
        PlanGeneratorInput(
            base: base ?? input(),
            totalWeeks: weeks,
            style: style,
            deloadEveryWeeks: deloadEvery,
            startDate: startDate,
            availableWeekdays: weekdays
        )
    }

    // MARK: - Structure

    @Test
    func testPlanCoversEveryWeekWithDatedWorkouts() throws {
        let plan = try PlanGenerator(catalog: catalog).generate(planInput(weeks: 8))
        #expect(plan.weeks.map(\.number) == Array(1...8))
        #expect(plan.totalWorkouts == 8 * plan.program.sessions.count)
        for week in plan.weeks {
            #expect(week.workouts.isEmpty == false)
            #expect(week.rationale.isEmpty == false)
        }
    }

    @Test
    func testWeekLengthIsClampedToTheSupportedRange() throws {
        let generator = PlanGenerator(catalog: catalog)
        #expect(try generator.generate(planInput(weeks: 2)).weeks.count == Periodization.minimumWeeks)
        #expect(try generator.generate(planInput(weeks: 40)).weeks.count == Periodization.maximumWeeks)
    }

    // Critere de la roadmap : le meme profil donne toujours le meme plan.
    @Test
    func testSameProfileProducesTheSamePlan() throws {
        let generator = PlanGenerator(catalog: catalog)
        let reference = try generator.generate(planInput())
        for _ in 0..<5 {
            #expect(try generator.generate(planInput()) == reference)
        }
    }

    @Test
    func testDifferentProfilesProduceDifferentPlans() throws {
        let generator = PlanGenerator(catalog: catalog)
        let hypertrophy = try generator.generate(planInput(input(goal: .hypertrophy)))
        let strength = try generator.generate(planInput(input(goal: .strength)))
        #expect(hypertrophy.program != strength.program)
    }

    // MARK: - Dates

    @Test
    func testWorkoutsFallOnDeclaredWeekdays() throws {
        // Lundi (2), mercredi (4), vendredi (6).
        let weekdays = [2, 4, 6]
        let plan = try PlanGenerator(catalog: catalog).generate(
            planInput(input(days: 3), weekdays: weekdays)
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt

        for week in plan.weeks {
            for workout in week.workouts {
                let weekday = calendar.component(.weekday, from: workout.date)
                #expect(weekdays.contains(weekday), "séance placée un jour non disponible")
            }
        }
    }

    // Declarer moins de jours que de seances ne doit jamais faire inventer un
    // jour que l'athlete a exclu.
    @Test
    func testFewerAvailableDaysThanSessionsNeverInventsADay() throws {
        let plan = try PlanGenerator(catalog: catalog).generate(
            planInput(input(days: 4), weekdays: [2, 4])
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        for week in plan.weeks {
            for workout in week.workouts {
                #expect([2, 4].contains(calendar.component(.weekday, from: workout.date)))
            }
        }
    }

    @Test
    func testWeeksAreSevenDaysApart() throws {
        let plan = try PlanGenerator(catalog: catalog).generate(planInput(weeks: 6))
        let starts = plan.weeks.map(\.startDate)
        for index in 1..<starts.count {
            let delta = starts[index].timeIntervalSince(starts[index - 1])
            #expect(delta == 7 * 86_400, "semaines non consécutives")
        }
    }

    @Test
    func testDefaultWeekdaysAreSpreadAcrossTheWeek() {
        #expect(PlanGenerator.spreadWeekdays(count: 0).isEmpty)
        #expect(PlanGenerator.spreadWeekdays(count: 3).count == 3)
        #expect(Set(PlanGenerator.spreadWeekdays(count: 3)).count == 3)
        #expect(PlanGenerator.spreadWeekdays(count: 7).count == 7)
    }

    // MARK: - Volume et explications

    @Test
    func testWeeklyVolumeIsReportedPerMuscle() throws {
        let plan = try PlanGenerator(catalog: catalog).generate(planInput())
        #expect(plan.weeklySetsByMuscle.isEmpty == false)
        #expect(plan.weeklySetsByMuscle.values.allSatisfy { $0 > 0 })
    }

    @Test
    func testPlanExplainsItsChoices() throws {
        let plan = try PlanGenerator(catalog: catalog).generate(
            planInput(input(priority: ["chest"], avoid: ["knees"]))
        )
        #expect(plan.rationale.contains { $0.contains("séances par semaine") })
        #expect(plan.rationale.contains { $0.contains("Décharge") })
        #expect(plan.rationale.contains { $0.contains("prioritaires") })
        // Le filtrage des zones a menager doit etre presente comme tel, et
        // jamais comme un avis medical.
        #expect(plan.rationale.contains { $0.contains("pas un avis médical") })
    }

    @Test
    func testDeloadWeeksReduceVolumeInThePlan() throws {
        let plan = try PlanGenerator(catalog: catalog).generate(planInput(weeks: 8, deloadEvery: 4))
        let deloads = plan.weeks.filter(\.isDeload)
        #expect(deloads.isEmpty == false)
        for week in deloads { #expect(week.volumeMultiplier < 1) }
    }
}

@Suite
struct ProgramValidatorTests {
    private let catalog = try! ExerciseCatalog.load()

    private func input(
        goal: Goal = .hypertrophy,
        experience: Experience = .intermediate,
        days: Int = 4,
        minutes: Int = 60,
        equipment: TrainingEquipment = .fullGym,
        priority: [String] = [],
        avoid: [String] = [],
        excluded: [String] = []
    ) -> GeneratorInput {
        GeneratorInput(
            goal: goal,
            experience: experience,
            daysPerWeek: days,
            sessionMinutes: minutes,
            equipment: equipment,
            splitPreference: .auto,
            priorityMuscles: priority,
            avoidAreas: avoid,
            excludedExerciseIds: excluded
        )
    }

    /// Le generateur local doit produire un programme que son propre
    /// validateur accepte : c'est la garantie du repli hors ligne.
    @Test(arguments: [2, 3, 4, 5, 6])
    func testGeneratedProgramsPassTheirOwnValidation(days: Int) throws {
        let profile = input(days: days)
        let program = try RuleBasedGenerator(catalog: catalog).generate(profile)
        let report = ProgramValidator(catalog: catalog).validate(program: program, input: profile)
        #expect(report.isAcceptable, "\(report.blockingIssues.map(\.message))")
    }

    @Test(arguments: Goal.allCases)
    func testEveryGoalProducesAnAcceptableProgram(goal: Goal) throws {
        let profile = input(goal: goal)
        let program = try RuleBasedGenerator(catalog: catalog).generate(profile)
        let report = ProgramValidator(catalog: catalog).validate(program: program, input: profile)
        #expect(report.isAcceptable, "\(report.blockingIssues.map(\.message))")
    }

    @Test
    func testEmptyProgramIsRefused() {
        let report = ProgramValidator(catalog: catalog).validate(
            program: DraftProgram(name: "Vide", notes: "", sessions: []),
            input: input()
        )
        #expect(report.isAcceptable == false)
        #expect(report.blockingIssues.contains { $0.code == "program.empty" })
    }

    @Test
    func testExcludedExerciseIsBlocking() throws {
        let excludedId = try #require(catalog.all.first { $0.primaryMuscles.contains("chest") }?.id)
        let program = DraftProgram(
            name: "Test",
            notes: "",
            sessions: [
                DraftSession(
                    name: "Push",
                    warmupEnabled: true,
                    exercises: [
                        DraftExercise(
                            exerciseId: excludedId,
                            displayName: "Exercice exclu",
                            sets: 3,
                            repsLower: 8,
                            repsUpper: 12,
                            restSeconds: 90
                        )
                    ]
                )
            ]
        )
        let report = ProgramValidator(catalog: catalog).validate(
            program: program,
            input: input(excluded: [excludedId])
        )
        #expect(report.isAcceptable == false)
        #expect(report.blockingIssues.contains { $0.code == "exercise.excluded" })
    }

    @Test
    func testEquipmentBeyondWhatIsAvailableIsBlocking() throws {
        let barbell = try #require(catalog.all.first { $0.equipment == "barbell" }?.id)
        let program = DraftProgram(
            name: "Test",
            notes: "",
            sessions: [
                DraftSession(
                    name: "Full",
                    warmupEnabled: true,
                    exercises: [
                        DraftExercise(exerciseId: barbell, displayName: "Barre", sets: 3, repsLower: 8, repsUpper: 12, restSeconds: 90)
                    ]
                )
            ]
        )
        let report = ProgramValidator(catalog: catalog).validate(
            program: program,
            input: input(days: 1, equipment: .bodyweight)
        )
        #expect(report.blockingIssues.contains { $0.code == "exercise.equipment" })
    }

    @Test
    func testAvoidedAreaIsBlocking() throws {
        let squat = try #require(catalog.all.first { $0.primaryMuscles.contains("quadriceps") }?.id)
        let program = DraftProgram(
            name: "Test",
            notes: "",
            sessions: [
                DraftSession(
                    name: "Jambes",
                    warmupEnabled: true,
                    exercises: [
                        DraftExercise(exerciseId: squat, displayName: "Squat", sets: 3, repsLower: 8, repsUpper: 12, restSeconds: 90)
                    ]
                )
            ]
        )
        let report = ProgramValidator(catalog: catalog).validate(
            program: program,
            input: input(days: 1, avoid: ["knees"])
        )
        #expect(report.blockingIssues.contains { $0.code == "exercise.avoidArea" })
    }

    @Test
    func testIncoherentPrescriptionIsBlocking() throws {
        let anyExercise = try #require(catalog.all.first?.id)
        let program = DraftProgram(
            name: "Test",
            notes: "",
            sessions: [
                DraftSession(
                    name: "Séance",
                    warmupEnabled: true,
                    exercises: [
                        DraftExercise(exerciseId: anyExercise, displayName: "X", sets: 0, repsLower: 12, repsUpper: 8, restSeconds: 90)
                    ]
                )
            ]
        )
        let report = ProgramValidator(catalog: catalog).validate(program: program, input: input(days: 1))
        #expect(report.blockingIssues.contains { $0.code == "exercise.prescription" })
    }

    @Test
    func testOverlongSessionIsAWarningNotABlocker() throws {
        let anyExercise = try #require(catalog.all.first { $0.equipment == "body only" }?.id)
        let exercises = (0..<12).map { index in
            DraftExercise(
                exerciseId: anyExercise,
                displayName: "Exercice \(index)",
                sets: 5,
                repsLower: 8,
                repsUpper: 12,
                restSeconds: 180
            )
        }
        let program = DraftProgram(
            name: "Test",
            notes: "",
            sessions: [DraftSession(name: "Trop longue", warmupEnabled: true, exercises: exercises)]
        )
        let report = ProgramValidator(catalog: catalog).validate(
            program: program,
            input: input(days: 1, minutes: 45, equipment: .bodyweight)
        )
        #expect(report.warnings.contains { $0.code == "session.duration" })
    }

    @Test
    func testUnknownExerciseIsReportedWithoutBlocking() {
        let program = DraftProgram(
            name: "Test",
            notes: "",
            sessions: [
                DraftSession(
                    name: "Perso",
                    warmupEnabled: true,
                    exercises: [
                        DraftExercise(exerciseId: "mon-exercice-perso", displayName: "Perso", sets: 3, repsLower: 8, repsUpper: 12, restSeconds: 90)
                    ]
                )
            ]
        )
        let report = ProgramValidator(catalog: catalog).validate(program: program, input: input(days: 1))
        #expect(report.warnings.contains { $0.code == "exercise.unknown" })
        #expect(report.isAcceptable)
    }

    /// Le generateur ne doit jamais proposer un exercice explicitement exclu.
    @Test
    func testGeneratorHonoursExclusions() throws {
        let profile = input(days: 3)
        let first = try RuleBasedGenerator(catalog: catalog).generate(profile)
        let excluded = try #require(first.sessions.first?.exercises.first?.exerciseId)

        let filtered = try RuleBasedGenerator(catalog: catalog).generate(input(days: 3, excluded: [excluded]))
        let allIds = filtered.sessions.flatMap { $0.exercises.map(\.exerciseId) }
        #expect(allIds.contains(excluded) == false)
    }
}
