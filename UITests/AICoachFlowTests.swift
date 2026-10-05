import XCTest

/// Coach IA : indisponibilité annoncée, consentement explicite, et aucune
/// fonction d'entraînement qui en dépende.
@MainActor
final class AICoachFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func openCoach(_ app: XCUIApplication) {
        selectTab(app, "Réglages", showing: "Réglages")
        tapUntilReveals(
            app.buttons["settings.aiCoach"],
            reveals: app.navigationBars["Coach IA"]
        )
    }

    func testCoachAnnouncesItIsUnavailableAndPointsToTheLocalGenerator() throws {
        let app = XCUIApplication()
        app.launchEmpty()
        openCoach(app)

        XCTAssertTrue(
            app.staticTexts["aiCoach.unavailable"].waitForExistence(timeout: 15),
            "Sans configuration, l’écran doit le dire au lieu de faire semblant"
        )
        XCTAssertTrue(
            app.firstDescendant(labelContains: "générateur local").exists,
            "L’écran doit renvoyer vers le générateur local"
        )
        XCTAssertFalse(app.buttons["aiCoach.send"].exists, "Aucune demande possible tant que rien n’est configuré")
    }

    func testDisclaimerIsAlwaysVisible() throws {
        let app = XCUIApplication()
        app.launchEmpty()
        openCoach(app)

        XCTAssertTrue(app.staticTexts["aiCoach.disclaimer"].waitForExistence(timeout: 15))
        let disclaimer = app.staticTexts["aiCoach.disclaimer"].label
        XCTAssertTrue(disclaimer.contains("peuvent contenir des erreurs"))
        XCTAssertTrue(disclaimer.contains("ne remplace pas un professionnel"))
    }

    func testSettingsShowAIDisabledAndNothingShared() throws {
        let app = XCUIApplication()
        app.launchEmpty()
        openCoach(app)

        tapUntilReveals(
            app.buttons["aiCoach.settings"],
            reveals: app.switches["ai.enabled"]
        )

        let toggle = app.switches["ai.enabled"]
        XCTAssertEqual(toggle.value as? String, "0", "Le coach IA doit être désactivé par défaut")
        XCTAssertTrue(
            app.staticTexts["ai.unavailable"].waitForExistence(timeout: 10),
            "La raison de l’indisponibilité doit être affichée"
        )
        XCTAssertFalse(
            app.switches["ai.consent.bodyMeasurements"].exists,
            "Les réglages de partage n’apparaissent pas tant que l’IA est désactivée"
        )
    }

    func testEnablingRevealsGranularConsentAllRefusedByDefault() throws {
        let app = XCUIApplication()
        app.launchEmpty()
        openCoach(app)

        tapUntilReveals(app.buttons["aiCoach.settings"], reveals: app.switches["ai.enabled"])
        app.switches["ai.enabled"].switches.firstMatch.tap()

        // Le formulaire rend ses lignes paresseusement. On LAISSE D'ABORD la
        // section apparaître : défiler trop vite décharge les lignes hors
        // écran de l'arbre d'accessibilité, et la cible disparaît juste avant
        // d'être trouvée.
        let measurements = app.switches["ai.consent.bodyMeasurements"]
        if !measurements.waitForExistence(timeout: 12) {
            for _ in 0..<4 where !measurements.exists {
                app.swipeUp()
                _ = measurements.waitForExistence(timeout: 3)
            }
        }
        XCTAssertTrue(measurements.exists, "Le consentement doit être détaillé par catégorie")
        XCTAssertEqual(measurements.value as? String, "0", "Une catégorie sensible est refusée par défaut")

        let summary = app.staticTexts["ai.consent.summary"]
        for _ in 0..<4 where !summary.exists {
            app.swipeUp()
            _ = summary.waitForExistence(timeout: 3)
        }
        XCTAssertTrue(
            summary.exists,
            "L’écran doit résumer ce qui partirait réellement"
        )
    }
}
