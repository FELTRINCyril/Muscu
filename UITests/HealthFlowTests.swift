import XCTest

/// Santé : ce qui sera partagé est expliqué AVANT la demande système, et rien
/// n'est demandé tant que l'utilisateur n'a pas activé la fonction.
@MainActor
final class HealthFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func openHealth(_ app: XCUIApplication) {
        selectTab(app, "Réglages", showing: "Réglages")
        tapUntilReveals(
            app.buttons["settings.health"],
            reveals: app.navigationBars["Santé"]
        )
    }

    func testTheScreenExplainsWhatWillBeSharedBeforeAsking() throws {
        let app = XCUIApplication()
        app.launchEmpty()
        openHealth(app)

        XCTAssertTrue(
            app.firstDescendant(labelContains: "écrit vos séances terminées").waitForExistence(timeout: 15),
            "Ce que Muscu partagera doit être dit avant toute demande"
        )
        XCTAssertTrue(
            app.firstDescendant(labelContains: "ni fréquence cardiaque, ni sommeil").exists,
            "Ce qui n’est PAS lu doit être dit aussi"
        )
        XCTAssertTrue(
            app.staticTexts["health.notDetermined"].exists,
            "Aucune autorisation ne doit avoir été demandée à l’ouverture"
        )
    }

    func testSharingIsOffByDefaultAndItsOptionsAreHidden() throws {
        let app = XCUIApplication()
        app.launchEmpty()
        openHealth(app)

        let toggle = app.switches["health.enabled"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 15))
        XCTAssertEqual(toggle.value as? String, "0", "Le partage doit être désactivé par défaut")
        XCTAssertFalse(
            app.switches["health.workouts"].exists,
            "Les options de contenu n’apparaissent qu’une fois le partage activé"
        )
    }

    func testEnablingRevealsWhatIsSharedAndSaysItIsReversible() throws {
        let app = XCUIApplication()
        app.launchEmpty()
        openHealth(app)

        let toggle = app.switches["health.enabled"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 15))
        toggle.switches.firstMatch.tap()

        // L'activation passe par une demande d'autorisation asynchrone : on
        // laisse la section apparaître AVANT de penser à faire défiler.
        // Défiler trop vite décharge les lignes hors écran de l'arbre
        // d'accessibilité, et l'élément cherché disparaît juste avant d'être
        // trouvé.
        let workouts = app.switches["health.workouts"]
        if !workouts.waitForExistence(timeout: 15) {
            for _ in 0..<4 where !workouts.exists {
                app.swipeUp()
                _ = workouts.waitForExistence(timeout: 3)
            }
        }
        XCTAssertTrue(
            workouts.exists,
            "Le contenu partagé doit être détaillé. "
            + "Interrupteur : \(String(describing: toggle.value)), "
            + "autorisé : \(app.staticTexts["health.authorized"].exists), "
            + "refusé : \(app.staticTexts["health.denied"].exists), "
            + "non demandé : \(app.staticTexts["health.notDetermined"].exists), "
            + "indisponible : \(app.staticTexts["health.unavailable"].exists), "
            + "message : \(app.staticTexts["health.message"].exists ? app.staticTexts["health.message"].label : "aucun")"
        )
        XCTAssertEqual(workouts.value as? String, "1", "Écrire les séances est le partage attendu par défaut")
        XCTAssertEqual(
            app.switches["health.bodyweight"].value as? String,
            "0",
            "Le poids corporel n’est pas partagé sans demande explicite"
        )

        let reversibility = app.firstDescendant(labelContains: "n’efface pas ce qui a déjà été ajouté")
        for _ in 0..<4 where !reversibility.exists {
            app.swipeUp()
            _ = reversibility.waitForExistence(timeout: 3)
        }
        XCTAssertTrue(
            reversibility.exists,
            "L’écran doit dire ce que désactiver ne fait PAS"
        )
    }
}
