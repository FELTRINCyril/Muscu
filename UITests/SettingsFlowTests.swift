import XCTest

final class SettingsFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTogglesStepperAIConfigAndAbout() {
        let app = XCUIApplication()
        app.launchEmpty()
        tapWhenReady(app.tabBars.buttons["Réglages"])
        waitAndAssert(app.navigationBars["Réglages"])

        // Sons : off puis on.
        let soundToggle = app.switches["Sons"]
        waitAndAssert(soundToggle)
        soundToggle.tap()
        soundToggle.tap()

        // Repos par défaut : le Stepper expose 2 boutons (décrément, incrément).
        let stepper = app.steppers.firstMatch
        waitAndAssert(stepper, "Le stepper de repos par défaut devrait être présent")
        let stepperButtons = stepper.buttons
        if stepperButtons.count >= 2 {
            stepperButtons.element(boundBy: 1).tap() // incrément
            stepperButtons.element(boundBy: 0).tap() // décrément
        }

        // Génération IA (avancé) : ouvrir puis revenir.
        tapWhenReady(app.firstDescendant(labelContains: "Génération IA (avancé)"))
        waitAndAssert(app.navigationBars["Génération IA"])
        app.navigationBars["Génération IA"].buttons.element(boundBy: 0).tap()
        waitAndAssert(app.navigationBars["Réglages"])

        // À propos : présent. Section tout en bas de la List : les lignes
        // non encore affichees n'existent pas dans l'arbre d'accessibilite
        // (rendu lazy), il faut scroller jusqu'a elle.
        for _ in 0..<6 where !app.staticTexts["Version"].exists {
            app.swipeUp()
        }
        waitAndAssert(app.staticTexts["Version"], "La section À propos devrait afficher la version")
    }

    func testExportDataCancelsSystemSheetIfShown() {
        let app = XCUIApplication()
        app.launchEmpty()
        tapWhenReady(app.tabBars.buttons["Réglages"])
        waitAndAssert(app.navigationBars["Réglages"])

        tapWhenReady(app.firstDescendant(labelContains: "Exporter mes données"))

        // Le fileExporter est une UI système : on tente juste de l'annuler si
        // elle apparaît, sans vérifier son contenu (hors périmètre). Le
        // libellé du bouton suit la langue du simulateur ("Cancel"/"Annuler").
        let cancelButton = app.buttons.matching(NSPredicate(format: "label == 'Annuler' OR label == 'Cancel'")).firstMatch
        if cancelButton.waitForExistence(timeout: 5) {
            cancelButton.tap()
        }

        waitAndAssert(app.navigationBars["Réglages"], timeout: 5)
    }
}
