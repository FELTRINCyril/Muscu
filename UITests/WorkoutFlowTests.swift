import XCTest

// Deroule complet d'une seance seedee (cf. App/Sources/UITestSupport.swift).
// Les valeurs de repos/intervalles/AMRAP sont volontairement tres courtes
// (2-15 s) pour que ces tests restent rapides tout en exercant reellement
// les chronos (pas seulement "Passer" immediatement).
@MainActor
final class WorkoutFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // Séance A (classique + pyramide) puis, dans la foulée (le programme
    // tourne automatiquement vers la séance suivante), Séance B (intervalles
    // + AMRAP). Un seul test enchaîné : re-seeder entre les deux repartirait
    // toujours sur Séance A (cf. HomeView.nextSession, qui se base sur le
    // dernier historique correspondant au programme actif).
    func testFullSessionAThenSessionB() {
        let app = XCUIApplication()
        app.launchSeeded()

        tapWhenReady(app.buttons["Lancer la séance"])
        startFromPreparation(app)

        // Echauffement systematique : la seance demarre toujours sur
        // WarmupView. On exerce ici le flux "Echauffement libre" complet
        // (chrono compte-up -> Terminer -> Commencer la seance) ; les autres
        // lancements de seance de la suite passent par le raccourci
        // "Commencer directement la séance".
        tapWhenReady(app.buttons["Échauffement libre"], timeout: 15)
        tapWhenReady(app.buttons["Terminer"], timeout: 10)
        tapWhenReady(app.buttons["Commencer la séance"], timeout: 10)

        // La 1re présentation du runner peut être lente : ExerciseImageView
        // tente de récupérer l'image de l'exercice classique sur le réseau
        // (URLSession sans réseau dans cet environnement de test), et
        // XCUITest attend que l'app soit "idle" avant de continuer -
        // d'où un délai bien plus généreux ici que sur le reste de la suite.
        tapWhenReady(app.buttons["Valider la série"], timeout: 45)
        tapWhenReady(app.buttons["Passer"], timeout: 10)

        // --- Séance A : exercice classique (2e série, repos 15 s) ---
        tapWhenReady(app.buttons["Valider la série"])
        tapWhenReady(app.buttons["Passer"], timeout: 10) // repos entre séries/exercices

        // --- Séance A : pyramide (2-4-6-4-2), repos courts entre paliers ---
        // Repos de 2-3 s seulement entre paliers : le chrono expire de
        // lui-meme (RestTimer.handleExpiry ferme l'ecran de repos), et
        // l'ecran a souvent deja disparu quand le test reprend la main -
        // taper "Passer" ici serait a la fois inutile et race. Double
        // synchronisation avant chaque "Valider" : le palier attendu est
        // affiche ("N reps") ET l'ecran de repos est referme (sinon le tap
        // peut partir pendant l'animation de fermeture et se perdre).
        for target in [2, 4, 6, 4, 2] {
            // Compteur du palier (identifiant stable) portant « N reps ».
            let counter = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier == 'pyramid.reps' AND label == %@", "\(target) reps"))
                .firstMatch
            waitAndAssert(counter, timeout: 15)
            waitForDisappearance(app.buttons["Passer"], timeout: 10)
            tapWhenReady(app.buttons["Valider"], timeout: 15)
        }

        // Récap de fin de séance A.
        waitAndAssert(app.staticTexts["Séance terminée"], timeout: 10)
        tapWhenReady(app.buttons["Terminer"])
        dismissAnyRecordSuggestions(app)
        waitAndAssert(app.buttons["workout.closeSummaryButton"])
        tapWhenReady(app.buttons["workout.closeSummaryButton"])

        // De retour à l'Accueil : le programme tourne vers la Séance B.
        waitAndAssert(app.buttons["Lancer la séance"], timeout: 10)
        tapWhenReady(app.buttons["Lancer la séance"])
        startFromPreparation(app)
        tapWhenReady(app.buttons["Commencer directement la séance"], timeout: 15)

        // --- Séance B : intervalles (3 s / 2 s x 2), déroule automatique ---
        waitAndAssert(app.staticTexts["EFFORT"], timeout: 8)
        waitAndAssert(app.staticTexts["Bloc terminé"], timeout: 20)
        tapWhenReady(app.buttons["Valider"])

        // --- Séance B : AMRAP (5 s), tap du compteur pendant le décompte ---
        waitAndAssert(app.staticTexts["répétitions"], timeout: 8)
        let counter = app.otherElements["amrap.counterTapArea"]
        for _ in 0..<3 {
            if counter.waitForExistence(timeout: 3) {
                counter.tap()
            }
        }
        tapWhenReady(app.buttons["Valider"], timeout: 12) // apparaît à l'échéance du décompte

        // Récap de fin de séance B.
        waitAndAssert(app.staticTexts["Séance terminée"], timeout: 10)
        tapWhenReady(app.buttons["Terminer"])
        dismissAnyRecordSuggestions(app)
        waitAndAssert(app.buttons["workout.closeSummaryButton"])
        tapWhenReady(app.buttons["workout.closeSummaryButton"])

        waitAndAssert(app.buttons["Lancer la séance"], timeout: 10)

        // Progression > Historique doit maintenant montrer les séances.
        selectTab(app, "Progression", showing: "Progression")
        tapWhenReady(app.buttons["Historique"])
        waitAndAssert(app.firstDescendant(labelContains: "Séance A"), timeout: 8, "L'historique devrait contenir la séance A tout juste terminée")
    }

    // Sorties de séance : "Reprendre plus tard" (persistance à travers un
    // kill+resume réel du process) puis "Abandonner".
    func testExitPathsResumeThenAbandon() {
        let app = XCUIApplication()
        app.launchSeeded()

        tapWhenReady(app.buttons["Lancer la séance"])
        startFromPreparation(app)
        tapWhenReady(app.buttons["Commencer directement la séance"], timeout: 15)

        // Log une série pour qu'une ActiveWorkout existe réellement à
        // reprendre. Délai généreux : cf. commentaire de
        // testFullSessionAThenSessionB (1re présentation du runner, fetch
        // réseau de l'image d'exercice).
        tapWhenReady(app.buttons["Valider la série"], timeout: 45)
        tapWhenReady(app.buttons["Passer"], timeout: 10)

        // Le tap sur la sortie peut se perdre : on re-tape jusqu'à voir la
        // confirmation, au lieu de supposer qu'elle est affichée.
        tapUntilReveals(
            app.buttons["workout.exitButton"],
            reveals: app.buttons["Reprendre plus tard"]
        )
        tapWhenReady(app.buttons["Reprendre plus tard"])

        waitAndAssert(app.buttons["Reprendre la séance"], timeout: 10)

        // Relance complète du process (sans réinitialiser le store) pour
        // vérifier que l'ActiveWorkout survit à un kill+resume.
        app.terminate()
        app.launchArguments = []
        app.launch()

        waitAndAssert(app.staticTexts["Reprendre la séance en cours ?"], timeout: 10)
        tapWhenReady(app.buttons["Reprendre"])

        tapWhenReady(app.buttons["workout.exitButton"], timeout: 45)
        waitAndAssert(app.buttons["Abandonner"])
        tapWhenReady(app.buttons["Abandonner"])

        waitAndAssert(app.buttons["Lancer la séance"], timeout: 10)
    }

    // Les suggestions de record (RecordDetection) sont optionnelles : si une
    // apparaît, on l'ignore pour ne pas bloquer le reste du test (le
    // contenu exact des suggestions n'est pas l'objet de ce test).
    private func dismissAnyRecordSuggestions(_ app: XCUIApplication) {
        let ignoreButtons = app.buttons.matching(NSPredicate(format: "label == 'Ignorer'"))
        var remaining = ignoreButtons.count
        while remaining > 0 {
            ignoreButtons.firstMatch.tap()
            remaining -= 1
        }
    }
}
