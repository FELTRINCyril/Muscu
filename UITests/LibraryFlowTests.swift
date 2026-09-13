import XCTest

/// Bibliothèque : recherche tolérante aux fautes, favoris et collections.
@MainActor
final class LibraryFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTypoSearchFindsTheExerciseAndItCanBeFavorited() throws {
        let app = XCUIApplication()
        app.launchEmpty()
        selectTab(app, "Exercices", showing: "Exercices")

        let field = app.searchFields.firstMatch
        focusAndType(field, text: "develope couche")

        let result = app.firstHittableButton(labelContains: "Développé couché")
        XCTAssertTrue(result.waitForExistence(timeout: 20), "La recherche doit tolérer une faute de frappe")

        tapUntilReveals(result, reveals: app.navigationBars["Fiche exercice"])

        let favorite = app.buttons["exercise.favorite"]
        XCTAssertTrue(favorite.waitForExistence(timeout: 15))
        XCTAssertEqual(favorite.label, "Ajouter aux favoris")
        tapWhenReady(favorite)

        let predicate = NSPredicate(format: "label == %@", "Retirer des favoris")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: app.buttons["exercise.favorite"])
        XCTAssertEqual(
            XCTWaiter().wait(for: [expectation], timeout: 15),
            .completed,
            "Le favori doit être immédiatement reflété"
        )
    }

    func testCollectionCanBeCreatedAndListed() throws {
        let app = XCUIApplication()
        app.launchEmpty()
        selectTab(app, "Exercices", showing: "Exercices")

        tapUntilReveals(
            app.buttons["exercises.collections"],
            reveals: app.navigationBars["Collections"]
        )

        focusAndType(app.textFields["collections.name"], text: "Voyage")
        tapWhenReady(app.buttons["collections.create"])

        XCTAssertTrue(
            app.firstDescendant(labelContains: "Voyage").waitForExistence(timeout: 15),
            "La collection créée doit apparaître dans la liste"
        )
    }
}
