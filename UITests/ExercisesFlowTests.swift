import XCTest

@MainActor
final class ExercisesFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSearchOpenDetail() {
        let app = XCUIApplication()
        app.launchEmpty()
        selectTab(app, "Exercices", showing: "Exercices")

        let searchField = app.searchFields.firstMatch
        waitAndAssert(searchField)
        searchField.typeAndSettle("developpe")

        // La recherche (CatalogSearch, insensible aux accents) doit remonter
        // au moins un "Développé ...".
        let firstResult = app.firstHittableButton(labelContains: "éveloppé")
        waitAndAssert(firstResult, "La recherche 'developpe' devrait remonter au moins un résultat")
        firstResult.tap()

        waitAndAssert(app.navigationBars["Fiche exercice"], "La fiche exercice devrait s'ouvrir")
        waitAndAssert(app.staticTexts["Voir en vidéo"], "Le bouton vidéo devrait être présent")
    }

    func testCreateAndDeleteCustomExercise() {
        let app = XCUIApplication()
        app.launchEmpty()
        selectTab(app, "Exercices", showing: "Exercices")

        tapWhenReady(app.buttons["exercises.addButton"])
        waitAndAssert(app.navigationBars["Nouvel exercice"])

        let nameField = app.textFields["Nom de l'exercice"]
        waitAndAssert(nameField)
        nameField.tap()
        nameField.typeText("Exo Test UI")

        // "Pectoraux" est loin dans la liste alphabétique des muscles (pas
        // encore matérialisé par le List SwiftUI tant qu'il n'a pas été
        // scrollé en vue) - et un match CONTAINS collisionnerait avec le
        // label composite d'une ligne de catalogue du fond (recouverte par
        // la sheet). D'où scroll + match exact.
        tapWhenReady(app.scrollUntilHittableButton(exactLabel: "Pectoraux"))
        tapWhenReady(app.buttons["Enregistrer"])

        waitAndAssert(app.firstDescendant(labelContains: "Exo Test UI"), "L'exercice perso créé devrait apparaître dans la liste")
        waitAndAssert(app.firstDescendant(labelContains: "Perso"), "Le badge Perso devrait être visible")

        // Suppression par balayage : swiper la Cell englobante (pas
        // seulement le Button agrégé qu'expose l'accessibilité) pour que le
        // geste couvre bien toute la largeur de la ligne et révèle l'action.
        let row = app.cells.containing(NSPredicate(format: "label CONTAINS[c] %@", "Exo Test UI")).firstMatch
        waitAndAssert(row, "La ligne de l'exercice perso devrait être trouvable comme Cell")
        row.swipeLeft()
        // Ce swipe utilise .onDelete(perform:) (bouton système, pas notre
        // Label français custom comme dans ProgramsView/HistoryView) : son
        // libellé suit la langue du simulateur ("Delete" en anglais,
        // "Supprimer" en français), d'où l'acceptation des deux.
        let deleteButton = app.buttons.matching(NSPredicate(format: "label == 'Supprimer' OR label == 'Delete'")).firstMatch
        tapWhenReady(deleteButton)
        tapWhenReady(app.buttons["Supprimer"])

        let stillThere = app.firstDescendant(labelContains: "Exo Test UI").waitForExistence(timeout: 3)
        XCTAssertFalse(stillThere, "L'exercice perso devrait avoir disparu après suppression")
    }
}
