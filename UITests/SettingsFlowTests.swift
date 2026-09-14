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
        // L'écran Réglages s'allonge au fil des versions : on défile jusqu'à
        // la ligne plutôt que de supposer qu'elle tient dans le premier écran.
        let stepper = app.steppers.firstMatch
        for _ in 0..<6 where !stepper.exists {
            app.swipeUp()
            _ = stepper.waitForExistence(timeout: 2)
        }
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
            _ = app.staticTexts["Version"].waitForExistence(timeout: 2)
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
            // Laisser la ligne se matérialiser : enchaîner les balayages la
            // ferait dépasser sans jamais la voir.
            _ = exportButton.waitForExistence(timeout: 2)
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
