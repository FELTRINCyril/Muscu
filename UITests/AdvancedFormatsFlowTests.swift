import XCTest

// Parcours des formats avances livres en phase 2 : superset execute tour par
// tour, dropset avec ses paliers, et creation d'un groupe depuis l'editeur
// de seance. La seance C du seed est volontairement tres courte (repos de
// 2 s) pour rester rapide tout en exercant reellement les chronos.
@MainActor
final class AdvancedFormatsFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Superset complet (2 tours x 2 exercices) puis dropset (3 paliers),
    /// jusqu'au recapitulatif qui doit distinguer tours et paliers.
    func testSupersetThenDropsetRunToCompletion() {
        let app = XCUIApplication()
        app.launchSeeded()

        startSessionC(app)

        // --- Superset : A1 -> A2 -> tour 2 -> A1 -> A2 ---
        // Le bandeau de groupe doit annoncer le type et le tour courant.
        waitAndAssert(app.staticTexts["Superset"], timeout: 45, "Le bandeau de superset devrait être affiché")
        waitAndAssert(app.staticTexts["Tour 1/2"])
        waitAndAssert(app.firstDescendant(labelContains: "Pompes"))

        tapWhenReady(app.buttons["Valider la série"], timeout: 30)

        // Pas de repos entre A1 et A2 (0 s configuré) : on doit arriver
        // directement sur le second exercice du même tour.
        waitAndAssert(app.firstDescendant(labelContains: "Rowing"), timeout: 15)
        waitAndAssert(app.staticTexts["Tour 1/2"])
        tapWhenReady(app.buttons["Valider la série"], timeout: 15)

        // Fin de tour : un repos court démarre puis expire de lui-même.
        waitForRestToFinish(app)
        waitAndAssert(app.staticTexts["Tour 2/2"], timeout: 20)
        tapWhenReady(app.buttons["Valider la série"], timeout: 15)
        waitAndAssert(app.firstDescendant(labelContains: "Rowing"), timeout: 15)
        tapWhenReady(app.buttons["Valider la série"], timeout: 15)
        waitForRestToFinish(app)

        // --- Dropset : série principale puis deux paliers ---
        waitAndAssert(app.firstDescendant(labelContains: "Curl biceps"), timeout: 20)
        tapWhenReady(app.buttons["Valider la série"], timeout: 15)
        waitAndAssert(app.staticTexts["Palier 1"], timeout: 15)
        tapWhenReady(app.buttons["Valider la série"], timeout: 15)
        waitAndAssert(app.staticTexts["Palier 2"], timeout: 15)
        tapWhenReady(app.buttons["Valider la série"], timeout: 15)

        // --- Récapitulatif ---
        waitAndAssert(app.staticTexts["Séance terminée"], timeout: 20)
        tapWhenReady(app.buttons["Terminer"])
        dismissAnyRecordSuggestions(app)
        tapWhenReady(app.buttons["workout.closeSummaryButton"], timeout: 20)

        // L'historique doit distinguer tours et paliers.
        selectTab(app, "Progression", showing: "Progression")
        tapWhenReady(app.buttons["Historique"])
        tapWhenReady(app.firstHittableDescendant(labelContains: "Séance C"), timeout: 15)
        waitAndAssert(app.firstDescendant(labelContains: "Tour 1"), timeout: 15, "L'historique devrait distinguer les tours")
        waitAndAssert(app.firstDescendant(labelContains: "palier 1"), timeout: 15, "L'historique devrait distinguer les paliers")
    }

    /// Création d'un superset depuis l'éditeur de séance, puis réglage du
    /// nombre de tours, puis dissociation.
    func testCreateAndEditGroupFromSessionEditor() {
        let app = XCUIApplication()
        app.launchSeeded()

        selectTab(app, "Programmes", showing: "Programmes")
        // Un tap de navigation peut se perdre : on re-tape jusqu'à voir
        // l'écran attendu plutôt que de supposer qu'il est arrivé.
        tapUntilReveals(
            app.firstHittableDescendant(labelContains: "Programme Test"),
            reveals: app.navigationBars["Programme Test"]
        )
        tapUntilReveals(
            app.firstHittableDescendant(labelContains: "Séance B"),
            reveals: app.navigationBars["Séance B"]
        )

        // Sélection des deux exercices de la séance B via le menu contextuel.
        selectExercise(app, labelContains: "Grimpeur")
        selectExercise(app, labelContains: "Pompes")

        waitAndAssert(app.staticTexts["2 exercices sélectionnés"], timeout: 10)
        tapWhenReady(app.buttons["session.createGroup.superset"])

        // Le groupe apparaît avec ses exercices notés A1/A2.
        waitAndAssert(app.staticTexts["Superset"], timeout: 15)
        waitAndAssert(app.staticTexts["A1"])
        waitAndAssert(app.staticTexts["A2"])

        // Réglages du groupe : la séance B ne contient que des formats
        // chronométrés, qui n'utilisent pas de nombre de séries : le groupe
        // démarre donc sur la valeur par défaut de 3 tours.
        tapWhenReady(app.buttons["session.editGroup"])
        waitAndAssert(app.staticTexts["Tours : 3"], timeout: 15)
        let stepper = app.steppers.firstMatch
        waitAndAssert(stepper)
        stepper.buttons.element(boundBy: 1).tap()
        waitAndAssert(app.staticTexts["Tours : 4"])
        tapWhenReady(app.buttons["Terminé"])

        // Dissocier : les exercices redeviennent indépendants.
        waitAndAssert(app.buttons["session.editGroup"], timeout: 15)
        tapWhenReady(app.firstHittableButton(labelContains: "Dissocier le groupe"))
        waitForDisappearance(app.buttons["session.editGroup"], timeout: 15)
        waitAndAssert(app.firstDescendant(labelContains: "Grimpeur"))
    }

    // MARK: - Helpers

    private func startSessionC(_ app: XCUIApplication) {
        tapWhenReady(app.buttons["home.chooseSessionMenu"], timeout: 20)
        tapWhenReady(app.buttons["Séance C"], timeout: 10)
        startFromPreparation(app)
        tapWhenReady(app.buttons["Commencer directement la séance"], timeout: 20)
    }

    /// Les repos du seed durent 2 s : l'écran se ferme tout seul. On attend
    /// sa disparition plutôt que de taper « Passer », ce qui serait une
    /// course avec l'animation de fermeture.
    private func waitForRestToFinish(_ app: XCUIApplication) {
        let skip = app.buttons["Passer"]
        if skip.waitForExistence(timeout: 3) {
            waitForDisappearance(skip, timeout: 20)
        }
    }

    private func selectExercise(_ app: XCUIApplication, labelContains text: String) {
        // La cible du menu contextuel est le BOUTON de la ligne : un appui
        // long sur un texte qu'elle contient ne déclenche rien.
        let row = app.firstHittableButton(labelContains: text, timeout: 15)
        waitAndAssert(row, timeout: 15)
        row.press(forDuration: 1.2)
        let select = app.buttons["Sélectionner"]
        waitAndAssert(select, timeout: 10, "Le menu contextuel devrait proposer Sélectionner")
        select.tap()
    }

    private func dismissAnyRecordSuggestions(_ app: XCUIApplication) {
        for _ in 0..<6 {
            let ignore = app.buttons["Ignorer"]
            guard ignore.waitForExistence(timeout: 2), ignore.isHittable else { return }
            ignore.tap()
        }
    }
}
