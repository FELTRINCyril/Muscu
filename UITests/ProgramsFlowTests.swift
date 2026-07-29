import XCTest

final class ProgramsFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // "De zéro" -> renommer -> ajouter séance -> ajouter exercice (picker) ->
    // ouvrir la prescription -> parcourir tous les formats -> enregistrer.
    func testCreateFromScratchEditSessionAndPrescription() {
        let app = XCUIApplication()
        app.launchEmpty()
        tapWhenReady(app.tabBars.buttons["Programmes"])
        waitAndAssert(app.navigationBars["Programmes"])

        tapWhenReady(app.buttons["programs.addButton"])
        waitAndAssert(app.buttons["De zéro"])
        tapWhenReady(app.buttons["De zéro"])

        // Editeur de programme.
        let nameField = app.textFields["Nom du programme"]
        waitAndAssert(nameField)
        nameField.tap()
        // Selectionne tout le texte existant puis remplace.
        if let currentValue = nameField.value as? String, !currentValue.isEmpty {
            nameField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentValue.count))
        }
        nameField.typeText("Mon Programme UI")

        tapWhenReady(app.buttons["Ajouter une séance"])
        // Le row de séance (NavigationLink) agrège nom + nb d'exercices dans
        // un seul élément d'accessibilité : on cherche par CONTAINS plutôt
        // qu'un match exact sur "Séance 1".
        let sessionRow = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", "Séance 1")).firstMatch
        waitAndAssert(sessionRow, "Une séance par défaut devrait être créée")
        tapWhenReady(sessionRow)
        waitAndAssert(app.navigationBars["Séance 1"])

        tapWhenReady(app.buttons["Ajouter un exercice"])
        waitAndAssert(app.navigationBars["Choisir un exercice"])

        let searchField = app.searchFields.firstMatch
        waitAndAssert(searchField)
        searchField.typeAndSettle("developpe")

        let firstResult = app.firstHittableButton(labelContains: "éveloppé")
        waitAndAssert(firstResult, "La recherche devrait remonter un résultat")
        firstResult.tap()

        // De retour dans la séance, l'exercice ajouté doit apparaître.
        waitAndAssert(app.navigationBars["Séance 1"])

        let exerciseRow = app.firstHittableDescendant(labelContains: "éveloppé")
        waitAndAssert(exerciseRow, "L'exercice ajouté devrait apparaître dans la séance")
        exerciseRow.tap()

        // Editeur de prescription : parcourir tous les formats.
        waitAndAssert(app.segmentedControls.firstMatch, "Le sélecteur de format devrait être présent")
        tapWhenReady(app.buttons["Pyramide"])
        waitAndAssert(app.staticTexts["Pyramide"])
        tapWhenReady(app.buttons["Intervalles"])
        waitAndAssert(app.staticTexts["Intervalles"])
        tapWhenReady(app.buttons["AMRAP"])
        waitAndAssert(app.staticTexts["AMRAP"])
        tapWhenReady(app.buttons["Classique"])
        waitAndAssert(app.staticTexts["Séries classiques"])

        tapWhenReady(app.buttons["Terminé"])
        waitAndAssert(app.navigationBars["Séance 1"])
    }

    // Dupliquer (menu contextuel, long press) -> activer -> supprimer (avec confirmation).
    func testDuplicateActivateAndDeleteProgram() {
        let app = XCUIApplication()
        app.launchSeeded()
        tapWhenReady(app.tabBars.buttons["Programmes"])
        waitAndAssert(app.navigationBars["Programmes"])

        // Le row de programme (NavigationLink) agrège nom + badge + nb de
        // séances dans un seul élément d'accessibilité : CONTAINS plutôt
        // qu'un match exact.
        func row(containing text: String) -> XCUIElement {
            app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
        }

        let originalRow = row(containing: "Programme Test")
        waitAndAssert(originalRow)

        originalRow.press(forDuration: 1.0)
        waitAndAssert(app.buttons["Dupliquer"], "Le menu contextuel devrait proposer Dupliquer")
        tapWhenReady(app.buttons["Dupliquer"])

        let copyRow = row(containing: "Programme Test (copie)")
        waitAndAssert(copyRow, "Le programme dupliqué devrait apparaître")

        // Active la copie (pas encore active) via son menu contextuel.
        copyRow.press(forDuration: 1.0)
        waitAndAssert(app.buttons["Activer"])
        tapWhenReady(app.buttons["Activer"])
        let activatedCopyRow = row(containing: "Programme Test (copie)")
        waitAndAssert(activatedCopyRow, "La copie devrait rester visible après activation")

        // Supprime la copie (swipe + confirmation).
        activatedCopyRow.swipeLeft()
        tapWhenReady(app.buttons["Supprimer"])
        waitAndAssert(app.staticTexts["Supprimer ce programme ?"], "La confirmation de suppression devrait s'afficher")
        tapWhenReady(app.buttons["Supprimer"])

        let stillThere = row(containing: "Programme Test (copie)").waitForExistence(timeout: 3)
        XCTAssertFalse(stillThere, "Le programme dupliqué supprimé ne devrait plus apparaître")
    }

    // "Depuis un modèle" : 3 jours -> carte Push/Pull/Legs -> aperçu (3 séances) -> Enregistrer.
    func testCreateFromTemplate() {
        let app = XCUIApplication()
        app.launchEmpty()
        tapWhenReady(app.tabBars.buttons["Programmes"])
        waitAndAssert(app.navigationBars["Programmes"])

        tapWhenReady(app.buttons["programs.addButton"])
        tapWhenReady(app.buttons["Depuis un modèle"])
        waitAndAssert(app.navigationBars["Depuis un modèle"])

        // 3 séances/semaine est la valeur par défaut du stepper. La carte est
        // un Button englobant plusieurs Text (nom + liste de séances) : son
        // accessibilityLabel agrège les deux, d'où le CONTAINS.
        let pplCard = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Push/Pull/Legs")).firstMatch
        tapWhenReady(pplCard)

        waitAndAssert(app.navigationBars["Aperçu"])
        // L'aperçu du split Push/Pull/Legs doit afficher les 3 séances. La
        // liste (DisclosureGroup par séance, dépliés par défaut) peut
        // dépasser l'écran : "Legs" (3e section) peut nécessiter un scroll
        // pour être matérialisée par le List SwiftUI (même limitation que
        // la liste des muscles, cf. scrollUntilHittableButton).
        for sessionName in ["Push", "Pull", "Legs"] {
            var header = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", sessionName)).firstMatch
            var attempts = 0
            while !header.exists, attempts < 8 {
                app.swipeUp()
                usleep(300_000)
                header = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", sessionName)).firstMatch
                attempts += 1
            }
            waitAndAssert(header, "La séance '\(sessionName)' devrait apparaître dans l'aperçu")
        }

        tapWhenReady(app.buttons["Enregistrer"])
        waitAndAssert(app.navigationBars["Programmes"])
        waitAndAssert(app.staticTexts["3 séances"], "Le nouveau programme devrait apparaître dans la liste avec 3 séances")
    }

    // Générateur : parcourt les 8 étapes en tapant la première option de
    // chaque écran (les étapes 7/8 sont optionnelles, on avance directement).
    func testGeneratorWizardAllSteps() {
        let app = XCUIApplication()
        app.launchEmpty()
        tapWhenReady(app.tabBars.buttons["Programmes"])
        waitAndAssert(app.navigationBars["Programmes"])

        tapWhenReady(app.buttons["programs.addButton"])
        tapWhenReady(app.buttons["Générateur"])
        waitAndAssert(app.navigationBars["Générateur"])

        tapWhenReady(app.buttons["Prise de masse"]) // 1. objectif
        tapWhenReady(app.buttons["Débutant (moins d'un an)"]) // 2. niveau
        tapWhenReady(app.buttons["2 séances par semaine"]) // 3. jours/semaine
        tapWhenReady(app.buttons["45 min"]) // 4. durée
        tapWhenReady(app.buttons["Salle complète"]) // 5. matériel
        tapWhenReady(app.buttons["Choisis pour moi"]) // 6. split
        tapWhenReady(app.buttons["Suivant"]) // 7. points faibles (optionnel)
        tapWhenReady(app.buttons["Générer"]) // 8. zones à ménager (optionnel) -> génère

        waitAndAssert(app.navigationBars["Aperçu"], timeout: 10)
        tapWhenReady(app.buttons["Enregistrer"])
        waitAndAssert(app.navigationBars["Programmes"])
    }
}
