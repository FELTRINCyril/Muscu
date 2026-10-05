import XCTest
import SwiftData
@testable import Muscu

/// Le harnais de tests UI doit repartir d'un etat REELLEMENT vide : un type
/// oublie dans la purge survit d'un test a l'autre et rend la suite
/// dependante de son ordre d'execution.
@MainActor
final class UITestHarnessTests: XCTestCase {
    func testWipeListCoversEveryModelOfTheCurrentSchema() {
        let wiped = Set(UITestSupport.wipedModelNames)
        let schema = Set(MuscuCurrentSchema.models.map { String(describing: $0) })
        let missing = schema.subtracting(wiped)
        XCTAssertTrue(
            missing.isEmpty,
            "Ces modèles ne sont pas purgés par --uitest-reset : \(missing.sorted().joined(separator: ", "))"
        )
    }
}
