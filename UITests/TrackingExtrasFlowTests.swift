import XCTest

/// Écarts fermés après la phase 6 : plateaux, photos de progression et test
/// de 1RM guidé.
@MainActor
final class TrackingExtrasFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func openProgressMenu(_ app: XCUIApplication, entry: String, title: String) {
        selectTab(app, "Progression", showing: "Progression")
        tapUntilReveals(app.buttons["progress.moreMenu"], reveals: app.buttons[entry])
        tapUntilReveals(app.buttons[entry], reveals: app.navigationBars[title])
    }

    func testPlateauScreenExplainsItsThresholdAndStaysEmptyWithoutHistory() throws {
        let app = XCUIApplication()
        app.launchEmpty()
        openProgressMenu(app, entry: "Plateaux", title: "Plateaux")

        XCTAssertTrue(
            app.staticTexts["plateau.empty"].waitForExistence(timeout: 15),
            "Sans historique, l’écran doit le dire au lieu d’inventer une détection"
        )
        XCTAssertTrue(
            app.firstDescendant(labelContains: "Rien n’est appliqué sans votre accord").exists,
            "L’écran doit annoncer qu’aucune adaptation n’est automatique"
        )
    }

    func testProgressPhotosAnnounceThatTheyStayOnTheDevice() throws {
        let app = XCUIApplication()
        app.launchEmpty()
        selectTab(app, "Progression", showing: "Progression")

        tapWhenReady(app.buttons["Mesures"])
        tapUntilReveals(
            app.buttons["measurements.photos"],
            reveals: app.navigationBars["Photos de progression"]
        )

        XCTAssertTrue(app.staticTexts["photos.empty"].waitForExistence(timeout: 15))
        XCTAssertTrue(
            app.firstDescendant(labelContains: "restent sur cet appareil").exists,
            "La confidentialité des photos doit être annoncée sur l’écran lui-même"
        )
        XCTAssertTrue(app.buttons["photos.add"].exists)
    }

    func testOneRepMaxTestWarnsBeforeShowingAnyProtocol() throws {
        let app = XCUIApplication()
        app.launchSeeded()
        selectTab(app, "Progression", showing: "Progression")

        // Le seed contient un record de 1RM à 100 kg pour le développé couché.
        let record = app.firstHittableButton(labelContains: "Développé couché")
        XCTAssertTrue(record.waitForExistence(timeout: 20))
        record.press(forDuration: 1.2)

        tapUntilReveals(
            app.firstHittableButton(exactLabel: "Tester mon 1RM"),
            reveals: app.navigationBars["Test de 1RM"]
        )

        XCTAssertTrue(app.staticTexts["oneRepMaxTest.warning"].waitForExistence(timeout: 15))
        XCTAssertFalse(
            app.buttons["oneRepMaxTest.save"].exists,
            "Aucun protocole ni enregistrement tant que l’avertissement n’est pas accepté"
        )

        let acknowledge = app.switches["oneRepMaxTest.acknowledge"]
        XCTAssertTrue(acknowledge.waitForExistence(timeout: 10))
        acknowledge.switches.firstMatch.tap()

        XCTAssertTrue(
            app.firstDescendant(labelContains: "Montée en charge").waitForExistence(timeout: 15),
            "Le protocole n’apparaît qu’après acceptation de l’avertissement"
        )
    }
}
