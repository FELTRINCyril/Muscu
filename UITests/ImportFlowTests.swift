import XCTest

/// Import CSV : l'écran est accessible, explique ce qu'il accepte et ne
/// promet rien tant qu'aucun fichier n'est choisi.
@MainActor
final class ImportFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testImportScreenExplainsSupportedFormatsAndEmptyQuarantine() throws {
        let app = XCUIApplication()
        app.launchEmpty()
        selectTab(app, "Réglages", showing: "Réglages")

        tapUntilReveals(
            app.buttons["settings.csvImport"],
            reveals: app.navigationBars["Importer un CSV"]
        )

        XCTAssertTrue(app.buttons["csv.pick"].waitForExistence(timeout: 15))
        XCTAssertTrue(
            app.firstDescendant(labelContains: "Strong").exists,
            "Les formats reconnus doivent être annoncés"
        )
        XCTAssertTrue(
            app.firstDescendant(labelContains: "Aucune ligne en quarantaine").exists,
            "La quarantaine doit être visible même vide"
        )
        XCTAssertFalse(
            app.buttons["csv.import"].exists,
            "Aucun import n’est proposé tant qu’aucun fichier n’a été analysé"
        )
    }

    func testPlacesScreenIsReachableAndExplainsEmptyInventory() throws {
        let app = XCUIApplication()
        app.launchEmpty()
        selectTab(app, "Réglages", showing: "Réglages")

        tapUntilReveals(
            app.buttons["settings.places"],
            reveals: app.navigationBars["Lieux et matériel"]
        )

        XCTAssertTrue(
            app.firstDescendant(labelContains: "aucun exercice n’est masqué").waitForExistence(timeout: 15),
            "L’absence de lieu ne doit rien filtrer, et l’écran doit le dire"
        )

        tapUntilReveals(app.buttons["places.add"], reveals: app.textFields["place.name"])
        XCTAssertTrue(app.switches["place.default"].exists, "Le premier lieu devient le lieu par défaut")
    }
}
