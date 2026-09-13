import XCTest

@MainActor
final class SettingsFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTogglesStepperAndAbout() {
        let app = XCUIApplication()
        app.launchEmpty()
        selectTab(app, "Réglages", showing: "Réglages")

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
        selectTab(app, "Réglages", showing: "Réglages")

        // La section Données est plus bas dans l'écran depuis l'ajout des
        // rappels : comme pour « À propos », il faut scroller jusqu'à elle,
        // les lignes non affichées n'existant pas dans l'arbre
        // d'accessibilité (rendu lazy).
        let exportButton = app.firstDescendant(labelContains: "Exporter mes données")
        for _ in 0..<6 where !exportButton.exists {
            app.swipeUp()
        }
        tapWhenReady(exportButton)

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
