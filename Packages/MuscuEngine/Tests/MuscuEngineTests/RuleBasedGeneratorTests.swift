import Foundation
import Testing
@testable import MuscuEngine

@Suite
struct RuleBasedGeneratorTests {
    private func makeInput(
        goal: Goal = .hypertrophy,
        experience: Experience = .intermediate,
        daysPerWeek: Int = 4,
        sessionMinutes: Int = 60,
        equipment: TrainingEquipment = .fullGym,
        splitPreference: SplitPreference = .auto,
        priorityMuscles: [String] = [],
        avoidAreas: [String] = []
    ) -> GeneratorInput {
        GeneratorInput(
            goal: goal,
            experience: experience,
            daysPerWeek: daysPerWeek,
            sessionMinutes: sessionMinutes,
            equipment: equipment,
            splitPreference: splitPreference,
            priorityMuscles: priorityMuscles,
            avoidAreas: avoidAreas
        )
    }

    @Test
    func testFourDaysHypertrophyIntermediateFullGymAuto() throws {
        let catalog = try ExerciseCatalog.load()
        let generator = RuleBasedGenerator(catalog: catalog)
        let program = try generator.generate(makeInput())

        #expect(program.sessions.count == 4)
        for session in program.sessions {
            #expect(session.exercises.count >= 4 && session.exercises.count <= 7)
            for exercise in session.exercises {
                #expect(exercise.repsLower >= 6 && exercise.repsUpper <= 12)
                #expect(exercise.restSeconds >= 60 && exercise.restSeconds <= 120)
            }
        }
    }

    @Test
    func testStrengthGoalUsesLowRepsHighRestAndPercentOneRepMaxOnCompounds() throws {
        let catalog = try ExerciseCatalog.load()
        let generator = RuleBasedGenerator(catalog: catalog)
        let program = try generator.generate(makeInput(goal: .strength))

        var foundCompoundWithPercent = false
        for session in program.sessions {
            for exercise in session.exercises {
                #expect(exercise.repsUpper <= 6)
                #expect(exercise.restSeconds >= 150)
                let catalogExercise = catalog.all.first { $0.id == exercise.exerciseId }
                if catalogExercise?.mechanic == "compound" {
                    #expect(exercise.percentOneRepMax != nil)
                    if let percent = exercise.percentOneRepMax {
                        #expect(percent >= 75)
                        foundCompoundWithPercent = true
                    }
                }
            }
        }
        #expect(foundCompoundWithPercent)
    }

    @Test
    func testEnduranceGoalUsesHighRepsAndShortRest() throws {
        let catalog = try ExerciseCatalog.load()
        let generator = RuleBasedGenerator(catalog: catalog)
        let program = try generator.generate(makeInput(goal: .endurance))

        for session in program.sessions {
            for exercise in session.exercises {
                #expect(exercise.repsLower >= 12)
                #expect(exercise.restSeconds <= 60)
            }
        }
    }

    @Test
    func testBodyweightEquipmentExcludesGymOnlyEquipment() throws {
        let catalog = try ExerciseCatalog.load()
        let generator = RuleBasedGenerator(catalog: catalog)
        let program = try generator.generate(makeInput(equipment: .bodyweight))

        let excluded: Set<String> = ["barbell", "machine", "cable", "dumbbell"]
        for session in program.sessions {
            for exercise in session.exercises {
                let catalogExercise = catalog.all.first { $0.id == exercise.exerciseId }
                if let equipment = catalogExercise?.equipment {
                    #expect(!excluded.contains(equipment))
                }
            }
        }
    }

    @Test
    func testPriorityMusclesAddAtLeastOneMoreExerciseForThatMuscle() throws {
        let catalog = try ExerciseCatalog.load()
        let generator = RuleBasedGenerator(catalog: catalog)

        let autoProgram = try generator.generate(makeInput())
        let priorityProgram = try generator.generate(makeInput(priorityMuscles: ["biceps"]))

        func bicepsCount(_ program: DraftProgram) -> Int {
            program.sessions.reduce(0) { total, session in
                total + session.exercises.filter { exercise in
                    catalog.all.first { $0.id == exercise.exerciseId }?.primaryMuscles.contains("biceps") ?? false
                }.count
            }
        }

        #expect(bicepsCount(priorityProgram) > bicepsCount(autoProgram))
    }

    @Test
    func testAvoidAreasExcludesLowerBackExercises() throws {
        let catalog = try ExerciseCatalog.load()
        let generator = RuleBasedGenerator(catalog: catalog)
        let program = try generator.generate(makeInput(avoidAreas: ["lower back"]))

        for session in program.sessions {
            for exercise in session.exercises {
                let catalogExercise = catalog.all.first { $0.id == exercise.exerciseId }
                #expect(catalogExercise?.primaryMuscles.contains("lower back") != true)
            }
        }
    }

    @Test
    func testBeginnerExperienceLimitsExercisesAndSets() throws {
        let catalog = try ExerciseCatalog.load()
        let generator = RuleBasedGenerator(catalog: catalog)
        let program = try generator.generate(makeInput(experience: .beginner))

        for session in program.sessions {
            #expect(session.exercises.count <= 5)
            for exercise in session.exercises {
                #expect(exercise.sets <= 3)
            }
        }
    }

    @Test
    func testPullUpProgressGoalIncludesTractionInSessionsWithLatsSlot() throws {
        let catalog = try ExerciseCatalog.load()
        let generator = RuleBasedGenerator(catalog: catalog)
        let program = try generator.generate(makeInput(goal: .pullUpProgress))

        let blueprints = SplitTemplates.recommended(daysPerWeek: 4).first!.sessions
        for (index, session) in program.sessions.enumerated() {
            let blueprint = blueprints[index]
            guard blueprint.slots.contains(where: { $0.muscle == "lats" }) else { continue }
            let hasTraction = session.exercises.contains { exercise in
                let normalized = exercise.displayName.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
                return normalized.contains("traction") || normalized.contains("pull-up") || normalized.contains("pullup")
            }
            #expect(hasTraction, "Session \(session.name) devrait contenir une traction")
        }
    }

    @Test
    func testDeterministicGenerationProducesIdenticalResults() throws {
        let catalog = try ExerciseCatalog.load()
        let generator = RuleBasedGenerator(catalog: catalog)
        let program1 = try generator.generate(makeInput())
        let program2 = try generator.generate(makeInput())
        #expect(program1 == program2)
    }
}
