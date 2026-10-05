import XCTest
import MuscuEngine
@testable import Muscu

/// Invariants des formats, cote app : ils pilotent ce que l'editeur propose
/// et ce que le runner sait executer.
final class SetFormatTests: XCTestCase {
    /// Un repos de zero seconde n'est propose que la ou il a un sens.
    func testZeroRestIsOnlyAllowedWhereItIsMeaningful() {
        XCTAssertFalse(SetFormat.classic.allowsZeroRest)
        XCTAssertFalse(SetFormat.pyramid.allowsZeroRest)
        for format in [SetFormat.dropset, .restPause, .myoReps, .intervals, .emom, .amrap, .forTime] {
            XCTAssertTrue(format.allowsZeroRest, "\(format) doit autoriser un repos nul")
        }

        XCTAssertFalse(ExerciseGroupKind.single.allowsZeroRestBetweenExercises)
        for kind in [ExerciseGroupKind.superset, .triset, .giantSet, .circuit] {
            XCTAssertTrue(kind.allowsZeroRestBetweenExercises, "\(kind) doit autoriser un enchaînement sans repos")
        }
    }

    /// Chaque format propose dans l'editeur doit avoir un equivalent moteur :
    /// sinon le runner ne saurait pas le derouler.
    func testEveryEditableFormatHasAnEngineCounterpart() {
        for format in SetFormat.allCases {
            XCTAssertNotNil(
                WorkoutFormat(rawValue: format.rawValue),
                "Le format \(format.rawValue) n'a pas d'équivalent dans MuscuEngine"
            )
        }
        for format in WorkoutFormat.allCases {
            XCTAssertNotNil(
                SetFormat(rawValue: format.rawValue),
                "Le format moteur \(format.rawValue) n'est pas exposé par l'app"
            )
        }
    }

    func testTimedFormatsAgreeBetweenAppAndEngine() {
        for format in SetFormat.allCases {
            let engineFormat = WorkoutFormat(rawValue: format.rawValue)
            XCTAssertEqual(format.isTimed, engineFormat?.isTimed, "\(format.rawValue)")
        }
    }

    /// Les records des formats chronometres portent leur configuration :
    /// deux AMRAP de durees differentes ne sont jamais compares.
    func testRecordConfigurationKeyDependsOnConfiguration() {
        let short = PrescribedExercise(exerciseId: "a", displayName: "A", orderIndex: 0, amrapSeconds: 480)
        let long = PrescribedExercise(exerciseId: "a", displayName: "A", orderIndex: 0, amrapSeconds: 720)
        XCTAssertNotEqual(
            SetFormat.amrap.recordConfigurationKey(for: short),
            SetFormat.amrap.recordConfigurationKey(for: long)
        )
        XCTAssertEqual(SetFormat.classic.recordConfigurationKey(for: short), "")
    }

    /// Une prescription ne doit jamais perdre son format a l'aller-retour
    /// dans le stockage brut.
    func testFormatRoundTripsThroughRawValue() {
        for format in SetFormat.allCases {
            let exercise = PrescribedExercise(
                exerciseId: "a",
                displayName: "A",
                orderIndex: 0,
                formatRaw: format.rawValue
            )
            XCTAssertEqual(exercise.format, format)
        }
    }
}
