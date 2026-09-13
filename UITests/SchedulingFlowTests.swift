import XCTest

/// Parcours du planning : ajouter une séance prévue, la déplacer, créer une
/// récurrence et remplir le planning.
@MainActor
final class SchedulingFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Fait defiler jusqu'a ce que l'element existe : une `Form` SwiftUI ne
    /// materialise pas les lignes restees hors ecran.
    private func scrollUntilExists(_ app: XCUIApplication, _ element: XCUIElement, swipes: Int = 6) {
        for _ in 0..<swipes {
            if element.exists { return }
            app.swipeUp()
        }
    }

    private func openPlanning(_ app: XCUIApplication) {
        selectTab(app, "Programmes", showing: "Programmes")
        tapUntilReveals(
            app.buttons["programs.planning"],
            reveals: app.navigationBars["Planning"]
        )
    }

    func testAddPlannedSessionThenPostponeIt() throws {
        let app = XCUIApplication()
        app.launchEmpty()
        openPlanning(app)

        // Vue JOUR : la liste ne contient alors que la journée courante,
        // donc la séance ajoutée est visible sans défilement.
        tapWhenReady(app.buttons["Jour"])

        // Ajout d'une séance prévue aujourd'hui.
        tapUntilReveals(
            app.buttons["planning.add"],
            reveals: app.navigationBars["Nouvelle séance prévue"]
        )
        focusAndType(app.textFields["addWorkout.name"], text: "Séance test")
        tapWhenReady(app.buttons["addWorkout.confirm"])

        let row = app.firstHittableDescendant(labelContains: "Séance test")
        XCTAssertTrue(row.waitForExistence(timeout: 15), "La séance ajoutée doit apparaître dans le planning")
        XCTAssertTrue(app.staticTexts["Prévue"].waitForExistence(timeout: 10))

        // Déplacement via l'action de balayage.
        row.swipeLeft()
        tapUntilReveals(
            app.buttons["Déplacer"].firstMatch,
            reveals: app.buttons["planning.move.confirm"]
        )
        tapWhenReady(app.buttons["planning.move.confirm"])

        XCTAssertTrue(
            app.firstDescendant(labelContains: "Reportée du").waitForExistence(timeout: 15),
            "Un report doit rester visible, avec sa date d’origine"
        )
    }

    func testRecurrenceFillsThePlanning() throws {
        let app = XCUIApplication()
        app.launchEmpty()
        openPlanning(app)

        tapUntilReveals(
            app.buttons["planning.schedules"],
            reveals: app.navigationBars["Récurrences"]
        )
        tapUntilReveals(
            app.buttons["schedules.add"],
            reveals: app.buttons["schedule.generate"]
        )

        tapWhenReady(app.buttons["schedule.generate"])

        let result = app.staticTexts["schedule.generate.result"]
        XCTAssertTrue(result.waitForExistence(timeout: 15), "Le remplissage doit rendre compte de ce qu’il a fait")
        XCTAssertTrue(
            result.label.contains("séance(s) ajoutée(s)"),
            "Compte rendu inattendu : \(result.label)"
        )

        // Relancer le remplissage ne doit rien ajouter de plus.
        tapWhenReady(app.buttons["schedule.generate"])
        XCTAssertTrue(
            app.staticTexts["schedule.generate.result"].label.hasPrefix("0 séance(s) ajoutée(s)"),
            "Un second remplissage ne doit créer aucun doublon"
        )
    }

    func testRemindersStayOffWhenNothingIsAuthorised() throws {
        let app = XCUIApplication()
        app.launchEmpty()
        openPlanning(app)

        tapUntilReveals(
            app.buttons["planning.schedules"],
            reveals: app.navigationBars["Récurrences"]
        )
        tapUntilReveals(
            app.buttons["schedules.add"],
            reveals: app.textFields["schedule.name"]
        )
        scrollUntilExists(app, app.switches["schedule.reminders"])
        XCTAssertTrue(app.switches["schedule.reminders"].exists, "Le réglage des rappels doit être atteignable")

        // L'écran annonce explicitement que l'application fonctionne sans
        // notifications : aucune fonctionnalité n'est bloquée derrière.
        XCTAssertTrue(
            app.firstDescendant(labelContains: "fonctionne entièrement sans notifications").exists,
            "L’écran doit dire que les rappels sont facultatifs"
        )
    }
}
