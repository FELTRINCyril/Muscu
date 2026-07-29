import XCTest

final class TabsTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAllFiveTabsOpenWithExpectedTitle() {
        let app = XCUIApplication()
        app.launchEmpty()

        let tabBar = app.tabBars.firstMatch
        waitAndAssert(tabBar, "La barre d'onglets devrait être visible au lancement")

        tapWhenReady(tabBar.buttons["Programmes"])
        waitAndAssert(app.navigationBars["Programmes"], "L'onglet Programmes devrait afficher son titre")

        tapWhenReady(tabBar.buttons["Exercices"])
        waitAndAssert(app.navigationBars["Exercices"], "L'onglet Exercices devrait afficher son titre")

        tapWhenReady(tabBar.buttons["Progression"])
        waitAndAssert(app.navigationBars["Progression"], "L'onglet Progression devrait afficher son titre")

        tapWhenReady(tabBar.buttons["Réglages"])
        waitAndAssert(app.navigationBars["Réglages"], "L'onglet Réglages devrait afficher son titre")

        tapWhenReady(tabBar.buttons["Accueil"])
        // HomeView n'a pas de NavigationStack racine (pas de navigationTitle) :
        // on verifie l'etat vide a la place.
        waitAndAssert(app.staticTexts["Aucun programme actif"], "L'onglet Accueil devrait afficher l'état vide sans programme")
    }
}
