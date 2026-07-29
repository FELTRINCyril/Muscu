import Testing
@testable import MuscuEngine

struct AIPromptBuilderTests {
    @Test func promptContainsWhitelistUserNotesAndSchema() throws {
        let catalog = try ExerciseCatalog.load()
        let input = GeneratorInput(
            goal: .strength, experience: .advanced, daysPerWeek: 4,
            sessionMinutes: 90, equipment: .fullGym, splitPreference: .upperLower,
            priorityMuscles: ["chest"], avoidAreas: ["lower back"]
        )
        let prompt = AIPromptBuilder.prompt(input: input, userNotes: "Je veux du volume epaules", catalog: catalog)
        #expect(prompt.contains("Barbell_Bench_Press_-_Medium_Grip"), "liste blanche presente")
        #expect(prompt.contains("Je veux du volume epaules"), "notes utilisateur presentes")
        #expect(prompt.contains("exerciseId"), "schema JSON DraftProgram decrit")
        #expect(prompt.contains("JSON"), "consigne de sortie JSON presente")
        #expect(prompt.contains("4"), "jours par semaine presents")
        #expect(!prompt.contains("Alternating_Floor_Press"), "les exos hors liste ne sont pas proposes")
    }

    @Test func bodyweightEquipmentFiltersWhitelist() throws {
        let catalog = try ExerciseCatalog.load()
        let input = GeneratorInput(
            goal: .calisthenics, experience: .beginner, daysPerWeek: 3,
            sessionMinutes: 45, equipment: .bodyweight, splitPreference: .auto,
            priorityMuscles: [], avoidAreas: []
        )
        let prompt = AIPromptBuilder.prompt(input: input, userNotes: "", catalog: catalog)
        #expect(prompt.contains("Pushups"))
        #expect(!prompt.contains("Leg_Press"), "exo machine exclu en poids du corps")
    }
}
