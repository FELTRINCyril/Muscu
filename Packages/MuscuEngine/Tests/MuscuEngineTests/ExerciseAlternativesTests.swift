import Testing
@testable import MuscuEngine

struct ExerciseAlternativesTests {
    @Test func stapleExerciseGetsItsMovementGroupSortedByRank() throws {
        let catalog = try ExerciseCatalog.load()
        let alternatives = ExerciseAlternatives.alternatives(for: "Barbell_Squat", in: catalog)
        let ids = alternatives.map(\.id)
        #expect(!ids.contains("Barbell_Squat"), "l'exercice courant est exclu")
        #expect(ids.first == "Barbell_Full_Squat", "rang 2 du groupe squat en premier")
        #expect(ids.contains("Smith_Machine_Squat"))
        #expect(ids.contains("Goblet_Squat"))
    }

    @Test func nonStapleExerciseFallsBackToSameMuscleAndMechanic() throws {
        let catalog = try ExerciseCatalog.load()
        // Alternating_Floor_Press : chest / compound, hors liste blanche.
        let alternatives = ExerciseAlternatives.alternatives(for: "Alternating_Floor_Press", in: catalog)
        #expect(!alternatives.isEmpty)
        for exercise in alternatives {
            #expect(exercise.primaryMuscles.contains("chest"))
            #expect(exercise.mechanic == "compound")
        }
        // Les staples du meme muscle arrivent en premier dans le repli.
        #expect(StapleExercises.staple(for: alternatives[0].id) != nil)
    }

    @Test func unknownExerciseIdReturnsEmpty() throws {
        let catalog = try ExerciseCatalog.load()
        #expect(ExerciseAlternatives.alternatives(for: "Id_Bidon_Inexistant", in: catalog).isEmpty)
    }

    @Test func resultIsCappedAtTwelve() throws {
        let catalog = try ExerciseCatalog.load()
        // Squat : gros groupe + gros repli potentiel -> verifie le plafond.
        let alternatives = ExerciseAlternatives.alternatives(for: "Crunches", in: catalog)
        #expect(alternatives.count <= 12)
    }
}
