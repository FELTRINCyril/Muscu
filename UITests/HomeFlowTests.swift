import XCTest

final class HomeFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testHeroCardAndWeekViewWithSeededProgram() {
        let app = XCUIApplication()
        app.launchSeeded()

        // Carte de lancement : nom du programme actif + prochaine séance.
        waitAndAssert(app.staticTexts["Programme Test"], "Le nom du programme actif devrait être affiché")
        waitAndAssert(app.staticTexts["Séance A"], "La prochaine séance devrait être affichée (aucun historique correspondant)")
        waitAndAssert(app.buttons["Lancer la séance"])

        // Vue de la semaine.
        waitAndAssert(app.staticTexts["Cette semaine"])
    }

    func testEmptyStateRedirectsToProgramsTab() {
        let app = XCUIApplication()
        app.launchEmpty()

        waitAndAssert(app.staticTexts["Aucun programme actif"])
        tapUntilReveals(app.buttons["Créer un programme"], reveals: app.navigationBars["Programmes"])
    }
}
