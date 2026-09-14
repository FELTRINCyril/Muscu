import XCTest

/// Localisation : le français est la langue source, l'anglais est réellement
/// livré dans l'application — pas seulement présent dans le catalogue.
@MainActor
final class LocalizationFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTheAppIsInFrenchOnAFrenchDevice() throws {
        let app = XCUIApplication()
        app.launchEmpty(language: "fr", locale: "fr_FR")

        XCTAssertTrue(
            app.buttons["Réglages"].waitForExistence(timeout: 20),
            "Sur un appareil français, l’onglet doit s’appeler « Réglages »"
        )
        XCTAssertFalse(app.buttons["Settings"].exists, "L’anglais ne doit pas déborder sur le français")
    }

    func testTheAppIsInEnglishOnAnEnglishDevice() throws {
        let app = XCUIApplication()
        app.launchEmpty(language: "en", locale: "en_US")

        let settings = app.buttons["Settings"]
        XCTAssertTrue(
            settings.waitForExistence(timeout: 20),
            "Sur un appareil anglais, l’onglet doit s’appeler « Settings »"
        )
        XCTAssertTrue(app.buttons["Programs"].exists, "Les onglets doivent tous être traduits")
        XCTAssertFalse(app.buttons["Réglages"].exists, "Aucun libellé français ne doit subsister dans les onglets")
    }

    /// Un écran entier, pas seulement la barre d'onglets : c'est là que les
    /// chaînes oubliées se voient.
    func testASettingsScreenIsFullyTranslated() throws {
        let app = XCUIApplication()
        app.launchEmpty(language: "en", locale: "en_US")

        app.buttons["Settings"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["settings.profile"].exists)
        XCTAssertTrue(
            app.firstDescendant(labelContains: "My data").waitForExistence(timeout: 10),
            "« Mes données » doit apparaître traduit"
        )
        XCTAssertTrue(
            app.firstDescendant(labelContains: "Places and equipment").exists,
            "« Lieux et matériel » doit apparaître traduit"
        )
    }
}
