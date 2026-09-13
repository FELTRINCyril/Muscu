import XCTest

@MainActor
final class ProgressionFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testRecordsShowsSeedAndManualAddEdit() {
        let app = XCUIApplication()
        app.launchSeeded()
        selectTab(app, "Progression", showing: "Progression")

        // Segment "Records" est celui par défaut.
        waitAndAssert(app.firstDescendant(labelContains: "Tractions"), "Le record seedé (max reps Tractions) devrait apparaître")

        // Ajout manuel d'un record via le picker.
        tapUntilReveals(app.buttons["records.addButton"], reveals: app.navigationBars["Choisir un exercice"])

        let searchField = app.searchFields.firstMatch
        waitAndAssert(searchField)
        searchField.typeAndSettle("developpe")
        // Le picker recouvre RecordsView, qui affiche déjà (seed) une ligne
        // pour ce même exercice : firstHittableButton évite de matcher la
        // ligne recouverte (non tappable) au lieu de celle du picker.
        let firstResult = app.firstHittableButton(labelContains: "éveloppé")
        waitAndAssert(firstResult)
        tapUntilReveals(firstResult, reveals: app.navigationBars["Nouveau record"])
        // Premier TextField du formulaire = "1RM estimé (kg)" (la section
        // "Exercice" qui précède n'affiche qu'un Text, pas de champ).
        let oneRepMaxField = app.textFields.element(boundBy: 0)
        focusAndType(oneRepMaxField, text: "120")
        tapWhenReady(app.buttons["Enregistrer"])

        // Edition : rouvrir le même exercice (déjà existant maintenant) et modifier.
        let recordRow = app.firstHittableDescendant(labelContains: "éveloppé")
        waitAndAssert(recordRow, "Le nouveau record devrait apparaître dans la liste")
        tapUntilReveals(recordRow, reveals: app.navigationBars["Modifier le record"])

        let editField = app.textFields.firstMatch
        focusAndType(editField, text: "")
        editField.clearAndTypeText("130")
        tapWhenReady(app.buttons["Enregistrer"])
    }

    func testHistoryShowsSessionsAndDetail() {
        let app = XCUIApplication()
        app.launchSeeded()
        selectTab(app, "Progression", showing: "Progression")

        tapWhenReady(app.buttons["Historique"])
        let firstSession = app.firstHittableDescendant(labelContains: "Séance A")
        waitAndAssert(firstSession, "La séance seedée devrait apparaître dans l'historique")
        firstSession.tap()

        // Le detail liste les series par exercice.
        waitAndAssert(app.firstDescendant(labelContains: "reps"), timeout: 8)
    }

    func testChartsPickerSelectsExercise() {
        let app = XCUIApplication()
        app.launchSeeded()
        selectTab(app, "Progression", showing: "Progression")

        tapWhenReady(app.buttons["Graphiques"])

        let picker = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'éveloppé'")).firstMatch
        waitAndAssert(picker, "Le picker d'exercice devrait proposer l'exercice seedé (présent dans l'historique)")
    }
}

private extension XCUIElement {
    func clearAndTypeText(_ text: String) {
        guard let value = self.value as? String, !value.isEmpty else {
            typeText(text)
            return
        }
        typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
        typeText(text)
    }
}
