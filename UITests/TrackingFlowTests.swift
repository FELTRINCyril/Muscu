import XCTest

// Parcours de la phase 4 : mesures corporelles, objectifs, et gestion des
// données (export CSV et suppression par catégorie).
@MainActor
final class TrackingFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Ajouter une mesure : elle apparaît dans la liste, et l'alternative
    /// textuelle du graphique décrit bien la série.
    func testAddBodyMeasurement() {
        let app = XCUIApplication()
        app.launchEmpty()

        selectTab(app, "Progression", showing: "Progression")
        tapWhenReady(app.buttons["Mesures"])
        waitAndAssert(app.staticTexts["Aucune mesure"], timeout: 15)

        tapWhenReady(app.buttons["measurements.add"])
        let field = app.textFields["measurement.value"]
        waitAndAssert(field, timeout: 15)
        field.tap()
        app.typeText("78,5")
        tapWhenReady(app.buttons["measurement.save"])

        // La valeur est stockée en kilogrammes et affichée telle quelle.
        waitAndAssert(app.firstDescendant(labelContains: "78,5"), timeout: 15)
        waitAndAssert(app.firstDescendant(labelContains: "Saisie manuelle"), timeout: 10)
        waitAndAssert(app.firstDescendant(labelContains: "valeur(s)"), timeout: 10, "Le graphique doit avoir une alternative textuelle")
    }

    /// Créer un objectif de fréquence : il apparaît avec un avancement
    /// factuel, appuyé sur l'historique seedé.
    func testCreateFrequencyGoal() {
        let app = XCUIApplication()
        app.launchSeeded()

        selectTab(app, "Progression", showing: "Progression")
        tapWhenReady(app.buttons["progress.moreMenu"])
        tapWhenReady(app.buttons["Objectifs"], timeout: 10)
        waitAndAssert(app.navigationBars["Objectifs"], timeout: 15)
        waitAndAssert(app.staticTexts["Aucun objectif"], timeout: 10)

        tapWhenReady(app.buttons["goals.add"])
        waitAndAssert(app.navigationBars["Nouvel objectif"], timeout: 15)
        tapWhenReady(app.buttons["goal.save"])

        // L'objectif créé est listé, avec son état et une phrase factuelle.
        waitAndAssert(app.firstDescendant(labelContains: "séances par semaine"), timeout: 15)
        waitAndAssert(app.staticTexts["En cours"], timeout: 10)

        // L'archiver ne supprime rien : il change seulement d'état.
        tapWhenReady(app.buttons["goal.archive"])
        waitAndAssert(app.staticTexts["Archivé"], timeout: 10)
    }

    /// Supprimer une catégorie rend compte de ce qui a été supprimé et
    /// laisse les autres catégories intactes.
    func testDeleteMeasurementsCategoryOnly() {
        let app = XCUIApplication()
        app.launchSeeded()

        // Une mesure à supprimer.
        selectTab(app, "Progression", showing: "Progression")
        tapWhenReady(app.buttons["Mesures"])
        tapWhenReady(app.buttons["measurements.add"], timeout: 15)
        let field = app.textFields["measurement.value"]
        waitAndAssert(field, timeout: 15)
        field.tap()
        app.typeText("80")
        tapWhenReady(app.buttons["measurement.save"])
        waitAndAssert(app.firstDescendant(labelContains: "80"), timeout: 15)

        selectTab(app, "Réglages", showing: "Réglages")
        tapWhenReady(app.buttons["settings.data"])
        waitAndAssert(app.navigationBars["Mes données"], timeout: 15)

        tapWhenReady(app.buttons["delete.measurements"])
        tapWhenReady(app.buttons["Supprimer"], timeout: 10)
        waitAndAssert(app.staticTexts["Suppression effectuée"], timeout: 15)
        tapWhenReady(app.buttons["OK"])

        // L'historique seedé est toujours là.
        selectTab(app, "Progression", showing: "Progression")
        tapWhenReady(app.buttons["Historique"])
        waitAndAssert(app.firstDescendant(labelContains: "Séance A"), timeout: 15, "L'historique ne doit pas être touché")

        tapWhenReady(app.buttons["Mesures"])
        waitAndAssert(app.staticTexts["Aucune mesure"], timeout: 15)
    }
}
