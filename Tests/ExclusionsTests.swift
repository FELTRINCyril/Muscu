import XCTest
import SwiftData
import MuscuEngine
@testable import Muscu

/// Les exercices exclus du profil.
///
/// Le champ existait, le moteur savait le respecter (`ProgramValidator` refuse
/// un exercice exclu en bloquant), mais **personne ne le transmettait** et
/// aucun écran ne permettait de le remplir. Le critère « chaque séance
/// respecte les exclusions » était donc inapplicable en pratique.
@MainActor
final class ExclusionsTests: XCTestCase {
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

    func testTheProfileExclusionsReachTheGenerator() throws {
        let profile = AthleteProfile()
        profile.excludedExerciseIds = ["barbell-bench-press"]
        context.insert(profile)
        try context.save()

        let stored = try XCTUnwrap(ProfileStore.currentProfile(in: context))
        XCTAssertEqual(stored.excludedExerciseIds, ["barbell-bench-press"])

        // C'est exactement ce que construit l'assistant de génération.
        let input = GeneratorInput(
            goal: .hypertrophy,
            experience: .intermediate,
            daysPerWeek: 3,
            sessionMinutes: 60,
            equipment: .fullGym,
            splitPreference: .auto,
            priorityMuscles: [],
            avoidAreas: [],
            excludedExerciseIds: stored.excludedExerciseIds
        )
        XCTAssertEqual(input.excludedExerciseIds, ["barbell-bench-press"])
    }

    /// Le refus lui-meme est deja couvert cote moteur
    /// (`PlanGeneratorTests.testExcludedExerciseIsBlocking`). Ce qui manquait
    /// est le CHAINON : que la valeur du profil parvienne jusqu'a lui.
    func testAnEmptyProfileExcludesNothing() throws {
        let profile = AthleteProfile()
        context.insert(profile)
        try context.save()

        let stored = try XCTUnwrap(ProfileStore.currentProfile(in: context))
        XCTAssertTrue(stored.excludedExerciseIds.isEmpty)
    }

    func testAnExclusionIsNeverAddedTwice() throws {
        let profile = AthleteProfile()
        context.insert(profile)
        // C'est la garde posee par l'ecran de profil : rajouter deux fois le
        // meme exercice ne doit pas produire deux lignes identiques.
        for _ in 0..<2 where !profile.excludedExerciseIds.contains("squat") {
            profile.excludedExerciseIds.append("squat")
        }
        try context.save()
        XCTAssertEqual(profile.excludedExerciseIds, ["squat"])
    }
}
