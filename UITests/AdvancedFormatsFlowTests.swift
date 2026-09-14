import XCTest

// Parcours des formats avances livres en phase 2 : superset execute tour par
// tour, dropset avec ses paliers, et creation d'un groupe depuis l'editeur
// de seance. La seance C du seed est volontairement tres courte (repos de
// 2 s) pour rester rapide tout en exercant reellement les chronos.
@MainActor
final class AdvancedFormatsFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Superset complet (2 tours x 2 exercices) puis dropset (3 paliers),
    /// jusqu'au recapitulatif qui doit distinguer tours et paliers.
    func testSupersetThenDropsetRunToCompletion() {
        let app = XCUIApplication()
        app.launchSeeded()

        startSessionC(app)

        // --- Superset : A1 -> A2 -> tour 2 -> A1 -> A2 ---
        // Le bandeau de groupe doit annoncer le type et le tour courant.
        waitAndAssert(app.staticTexts["Superset"], timeout: 45, "Le bandeau de superset devrait être affiché")
        waitAndAssert(app.staticTexts["Tour 1/2"])
        waitForRunnerExercise(app, nameContains: "Pompes")

        tapWhenReady(app.buttons["Valider la série"], timeout: 30)

        // Pas de repos entre A1 et A2 (0 s configuré) : on doit arriver
        // directement sur le second exercice du même tour.
        waitForRunnerExercise(app, nameContains: "Rowing")
        waitAndAssert(app.staticTexts["Tour 1/2"])
        tapWhenReady(app.buttons["Valider la série"], timeout: 15)

        // Fin de tour : un repos court démarre puis expire de lui-même.
        waitForRestToFinish(app)
        waitAndAssert(app.staticTexts["Tour 2/2"], timeout: 20)
        tapWhenReady(app.buttons["Valider la série"], timeout: 15)
        waitForRunnerExercise(app, nameContains: "Rowing")
        tapWhenReady(app.buttons["Valider la série"], timeout: 15)
        waitForRestToFinish(app)

        // --- Dropset : série principale puis deux paliers ---
        waitForRunnerExercise(app, nameContains: "Curl biceps")
        tapWhenReady(app.buttons["Valider la série"], timeout: 15)
        waitAndAssert(app.staticTexts["Palier 1"], timeout: 15)
        tapWhenReady(app.buttons["Valider la série"], timeout: 15)
        waitAndAssert(app.staticTexts["Palier 2"], timeout: 15)
        tapWhenReady(app.buttons["Valider la série"], timeout: 15)

        // --- Récapitulatif ---
        waitAndAssert(app.staticTexts["Séance terminée"], timeout: 20)
        tapWhenReady(app.buttons["Terminer"])
        dismissAnyRecordSuggestions(app)
        tapWhenReady(app.buttons["workout.closeSummaryButton"], timeout: 20)

        // L'historique doit distinguer tours et paliers.
        selectTab(app, "Progression", showing: "Progression")
        tapWhenReady(app.buttons["Historique"])
        tapWhenReady(app.firstHittableDescendant(labelContains: "Séance C"), timeout: 15)
        waitAndAssert(app.firstDescendant(labelContains: "Tour 1"), timeout: 15, "L'historique devrait distinguer les tours")
        waitAndAssert(app.firstDescendant(labelContains: "palier 1"), timeout: 15, "L'historique devrait distinguer les paliers")
    }

    /// Création d'un superset depuis l'éditeur de séance, puis réglage du
    /// nombre de tours, puis dissociation.
    func testCreateAndEditGroupFromSessionEditor() {
        let app = XCUIApplication()
        app.launchSeeded()

        selectTab(app, "Programmes", showing: "Programmes")
        // Un tap de navigation peut se perdre : on re-tape jusqu'à voir
        // l'écran attendu plutôt que de supposer qu'il est arrivé.
        tapUntilReveals(
            app.firstHittableDescendant(labelContains: "Programme Test"),
            reveals: app.navigationBars["Programme Test"]
        )
        tapUntilReveals(
            app.firstHittableDescendant(labelContains: "Séance B"),
            reveals: app.navigationBars["Séance B"]
        )

        // Sélection des deux exercices de la séance B via le menu contextuel.
        selectExercises(app, labelsContaining: ["Grimpeur", "Pompes"])

        waitAndAssert(app.staticTexts["2 exercices sélectionnés"], timeout: 10)
        tapWhenReady(app.buttons["session.createGroup.superset"])

        // Le groupe apparaît avec ses exercices notés A1/A2.
        waitAndAssert(app.staticTexts["Superset"], timeout: 15)
        waitAndAssert(app.staticTexts["A1"])
        waitAndAssert(app.staticTexts["A2"])

        // Réglages du groupe : la séance B ne contient que des formats
        // chronométrés, qui n'utilisent pas de nombre de séries : le groupe
        // démarre donc sur la valeur par défaut de 3 tours.
        tapWhenReady(app.buttons["session.editGroup"])
        waitAndAssert(app.staticTexts["Tours : 3"], timeout: 15)
        let stepper = app.steppers.firstMatch
        waitAndAssert(stepper)
        stepper.buttons.element(boundBy: 1).tap()
        waitAndAssert(app.staticTexts["Tours : 4"])
        tapWhenReady(app.buttons["Terminé"])

        // Dissocier : les exercices redeviennent indépendants.
        waitAndAssert(app.buttons["session.editGroup"], timeout: 15)
        tapWhenReady(app.firstHittableButton(labelContains: "Dissocier le groupe"))
        waitForDisappearance(app.buttons["session.editGroup"], timeout: 15)
        waitAndAssert(app.firstDescendant(labelContains: "Grimpeur"))
    }

    // MARK: - Helpers

    private func startSessionC(_ app: XCUIApplication) {
        tapWhenReady(app.buttons["home.chooseSessionMenu"], timeout: 20)
        tapWhenReady(app.buttons["Séance C"], timeout: 10)
        startFromPreparation(app)
        tapWhenReady(app.buttons["Commencer directement la séance"], timeout: 20)
    }

    /// Les repos du seed durent 2 s : l'écran se ferme tout seul. On attend
    /// sa disparition plutôt que de taper « Passer », ce qui serait une
    /// course avec l'animation de fermeture.
    private func waitForRestToFinish(_ app: XCUIApplication) {
        let skip = app.buttons["Passer"]
        if skip.waitForExistence(timeout: 3) {
            waitForDisappearance(skip, timeout: 20)
        }
    }

    /// Sélectionne plusieurs exercices via leur menu contextuel.
    ///
    /// Le compteur affiché par l'écran est le SEUL signal fiable de ce qui a
    /// été pris en compte : il pilote donc les reprises. Trois pièges,
    /// rencontrés un par un sur cette suite :
    /// 1. l'appui long peut se perdre s'il arrive pendant une transition ;
    /// 2. un menu resté ouvert recouvre les lignes, et l'appui long suivant
    ///    échoue avec « Not hittable » ;
    /// 3. l'item du menu change de libellé selon l'état de la ligne : viser
    ///    « Sélectionner » revient à taper un élément dont le libellé peut
    ///    avoir changé entre la recherche et le tap. On vise donc son
    ///    IDENTIFIANT, stable, et on ne rouvre jamais le menu d'une ligne
    ///    déjà sélectionnée.
    private func selectExercises(
        _ app: XCUIApplication,
        labelsContaining labels: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for _ in 0..<3 {
            for (index, label) in labels.enumerated() {
                // Déjà compté : on ne retouche pas cette ligne.
                guard selectionCount(app) <= index else { continue }
                dismissAnyContextMenu(app)
                selectOne(app, labelContains: label, expectedCountAfter: index + 1)
            }
            dismissAnyContextMenu(app)
            if selectionCount(app) >= labels.count { return }
        }

        XCTFail(
            "Sélection jamais enregistrée pour \(labels.joined(separator: ", ")) "
            + "(compteur : \(selectionCount(app)), menu ouvert : \(isContextMenuOpen(app)))",
            file: file,
            line: line
        )
    }

    private func selectOne(_ app: XCUIApplication, labelContains text: String, expectedCountAfter expected: Int) {
        var row = app.firstHittableButton(labelContains: text, timeout: 10)
        if !(row.exists && row.isHittable) {
            // Une ligne non « hittable » signifie presque toujours qu'un menu
            // recouvre encore la liste.
            dismissAnyContextMenu(app)
            row = app.firstHittableButton(labelContains: text, timeout: 10)
        }
        guard row.exists, row.isHittable else { return }
        row.press(forDuration: 1.2)

        // On vise l'identifiant : le libellé, lui, bascule entre
        // « Sélectionner » et « Désélectionner ».
        let toggle = app.buttons["session.selectionToggle"]
        guard toggle.waitForExistence(timeout: 15), toggle.isHittable else {
            dismissAnyContextMenu(app)
            return
        }
        toggle.tap()

        // On attend que l'écran confirme, plutôt que de supposer.
        for _ in 0..<20 where selectionCount(app) < expected {
            usleep(300_000)
        }
    }

    /// Nombre d'exercices sélectionnés, lu sur le compteur de l'écran.
    private func selectionCount(_ app: XCUIApplication) -> Int {
        let counter = app.staticTexts["session.selectionCount"]
        guard counter.exists else { return 0 }
        let digits = counter.label.prefix { $0.isNumber }
        return Int(digits) ?? 0
    }

    private func isContextMenuOpen(_ app: XCUIApplication) -> Bool {
        app.buttons["session.selectionToggle"].isHittable
    }

    /// Referme un menu contextuel ouvert en tapant sur la barre de navigation,
    /// zone inerte : taper au centre de l'écran risquerait d'ouvrir la ligne
    /// qui se trouve dessous une fois le menu refermé.
    private func dismissAnyContextMenu(_ app: XCUIApplication) {
        for _ in 0..<8 {
            guard isContextMenuOpen(app) else { return }
            let navigationBar = app.navigationBars.firstMatch
            if navigationBar.exists {
                navigationBar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            } else {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.04)).tap()
            }
            usleep(500_000)
        }
    }

    private func dismissAnyRecordSuggestions(_ app: XCUIApplication) {
        for _ in 0..<6 {
            let ignore = app.buttons["Ignorer"]
            guard ignore.waitForExistence(timeout: 2), ignore.isHittable else { return }
            ignore.tap()
        }
    }
}
