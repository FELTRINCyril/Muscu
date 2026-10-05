import XCTest
import SwiftData
import MuscuEngine
@testable import Muscu

/// Décodage des instantanés persistés d'une séance en cours.
///
/// `WorkoutRuntimeState` est écrit en JSON sur `ActiveWorkout` : c'est un
/// **format de données**, qui gagne des champs au fil des versions. Le
/// décodeur synthétisé par Swift n'applique pas les valeurs par défaut sur
/// une clé absente, donc un état écrit par une version antérieure échouait à
/// se décoder — et l'échec était avalé par un `try?`. L'utilisateur perdait
/// son chrono de repos et son AMRAP en cours, sans aucune trace.
///
/// Ces tests figent les formats anciens tels qu'ils étaient réellement
/// écrits. Ils ne doivent jamais être « mis à jour » pour suivre le code :
/// c'est le code qui doit continuer à les lire.
final class RuntimeStateDecodingTests: XCTestCase {
    private func decode(_ json: String) throws -> WorkoutRuntimeState {
        let data = try XCTUnwrap(json.data(using: .utf8))
        return try JSONDecoder().decode(WorkoutRuntimeState.self, from: data)
    }

    /// Format d'origine : ni `restTotalSeconds`, ni `warmup`, ni `version`.
    func testTheOldestFormatStillDecodes() throws {
        let state = try decode("""
        {"restEndDate": 779068800.0}
        """)
        XCTAssertNotNil(state.restEndDate, "Le chrono de repos en cours doit survivre à la mise à jour")
        XCTAssertEqual(state.restTotalSeconds, 0)
        XCTAssertEqual(state.warmup.stepRaw, "choice")
        XCTAssertEqual(state.version, 1)
    }

    /// Format intermédiaire : `restTotalSeconds` est arrivé, pas `warmup`.
    func testTheIntermediateFormatStillDecodes() throws {
        let state = try decode("""
        {"restEndDate": 779068800.0, "restTotalSeconds": 90}
        """)
        XCTAssertEqual(state.restTotalSeconds, 90, "La durée de repos doit être conservée")
        XCTAssertEqual(state.warmup.cardioMinutes, Warmup.cardioMinutes)
    }

    /// Le cas qui faisait réellement perdre des données : un AMRAP en cours
    /// dans un état écrit avant l'ajout de `warmup`.
    func testAnAmrapInProgressSurvivesAnOldFormat() throws {
        let state = try decode("""
        {"amrap": {"exerciseId": "burpees", "isFinished": false, "counter": 7}}
        """)
        let amrap = try XCTUnwrap(state.amrap, "L'AMRAP en cours ne doit pas disparaître")
        XCTAssertEqual(amrap.counter, 7)
    }

    /// Un échauffement partiellement écrit ne doit pas emporter tout l'état.
    func testAPartialWarmupDoesNotBreakTheWholeState() throws {
        let state = try decode("""
        {"restTotalSeconds": 60, "warmup": {"stepRaw": "cardio"}}
        """)
        XCTAssertEqual(state.warmup.stepRaw, "cardio")
        XCTAssertEqual(state.warmup.cardioMinutes, Warmup.cardioMinutes, "La valeur par défaut doit s'appliquer")
        XCTAssertEqual(state.restTotalSeconds, 60)
    }

    func testARoundTripKeepsEverything() throws {
        var state = WorkoutRuntimeState()
        state.restEndDate = Date(timeIntervalSince1970: 1_760_000_000)
        state.restTotalSeconds = 120
        state.amrap = AmrapRuntimeState(exerciseId: "burpees", endDate: nil, isFinished: false, counter: 3)
        state.warmup = WarmupRuntimeState(stepRaw: "cardio", cardioMinutes: 7)

        let data = try JSONEncoder().encode(state)
        XCTAssertEqual(try JSONDecoder().decode(WorkoutRuntimeState.self, from: data), state)
    }

    /// Un état écrit par une version PLUS RÉCENTE ne doit pas être
    /// interprété à moitié.
    func testAStateFromANewerVersionIsRefusedRatherThanGuessed() throws {
        let state = try decode("""
        {"version": 99, "restTotalSeconds": 120}
        """)
        XCTAssertFalse(state.isReadable, "Un format inconnu doit être signalé, pas deviné")
    }
}

/// L'ancien format de déroulé (`runExercisesData`), antérieur au déroulé
/// unifié. `LegacyRunExercise.plan(from:)` n'était exercé par AUCUN test :
/// le test qui prétendait le couvrir construisait un `ActiveWorkout` sans
/// aucun blob.
final class LegacyRunExerciseDecodingTests: XCTestCase {
    func testALegacySnapshotStillProducesAUsablePlan() throws {
        // Forme REELLE de l'ancien format : `id`, `format` et `orderIndex`
        // y sont obligatoires, les champs de format specialise facultatifs.
        let json = """
        [
          {"id": "6B2F1E3C-9A44-4C1D-8E55-11AA22BB33CC", "exerciseId": "bench",
           "displayName": "Développé couché", "format": "classic", "sets": 3,
           "repsLower": 8, "repsUpper": 10, "restSeconds": 90,
           "targetWeight": 60, "notes": "", "orderIndex": 0},
          {"id": "7C3F2E4D-0B55-4D2E-9F66-22BB33CC44DD", "exerciseId": "squat",
           "displayName": "Squat", "format": "classic", "sets": 4,
           "repsLower": 5, "repsUpper": 5, "restSeconds": 120,
           "notes": "", "orderIndex": 1}
        ]
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let plan = try XCTUnwrap(
            LegacyRunExercise.plan(from: data),
            "Une séance commencée avant le déroulé unifié doit rester reprenable"
        )
        XCTAssertEqual(plan.allExercises.count, 2)
        XCTAssertEqual(plan.allExercises.first?.displayName, "Développé couché")
        XCTAssertEqual(plan.allExercises.first?.setCount, 3)
        XCTAssertEqual(plan.allExercises.last?.setCount, 4)
    }

    func testAnUnreadableLegacySnapshotIsRefusedWithoutCrashing() throws {
        let data = try XCTUnwrap("{\"pas\": \"une liste\"}".data(using: .utf8))
        XCTAssertNil(LegacyRunExercise.plan(from: data))
    }
}
