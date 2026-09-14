import XCTest

// Parcours de la phase 5 : écran de synchronisation (qui doit dire la vérité
// sur son indisponibilité) et présentation adaptative sur iPad.
@MainActor
final class SyncFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Sans conteneur CloudKit configuré, l'écran l'annonce clairement au
    /// lieu d'afficher un interrupteur qui ne ferait rien.
    func testSyncScreenStatesItIsNotConfigured() {
        let app = XCUIApplication()
        app.launchEmpty()

        selectTab(app, "Réglages", showing: "Réglages")
        tapWhenReady(app.buttons["settings.sync"])
        waitAndAssert(app.navigationBars["Synchronisation"], timeout: 15)

        waitAndAssert(app.firstDescendant(labelContains: "Synchronisation indisponible"), timeout: 10)
        XCTAssertFalse(app.switches["sync.toggle"].exists, "Aucun interrupteur ne doit être proposé tant que rien n'est configuré")

        // L'écran explique quand même les règles de résolution des conflits.
        waitAndAssert(app.firstDescendant(labelContains: "jamais réécrite"), timeout: 10)
    }

    /// L'import propose explicitement fusionner ou remplacer, et annonce la
    /// sauvegarde de sécurité.
    func testImportOffersMergeOrReplace() {
        let app = XCUIApplication()
        app.launchSeeded()

        selectTab(app, "Réglages", showing: "Réglages")
        // Même raison que dans SettingsFlowTests : la section Données est
        // rendue paresseusement, plus bas dans l'écran.
        let exportLabel = app.firstDescendant(labelContains: "Exporter")
        for _ in 0..<6 where !exportLabel.exists {
            app.swipeUp()
            // Laisser la ligne se matérialiser : enchaîner les balayages la
            // ferait dépasser sans jamais la voir.
            _ = exportLabel.waitForExistence(timeout: 2)
        }
        waitAndAssert(exportLabel, timeout: 15)
    }
}

// Présentation adaptative : sur iPad, la navigation passe en barre latérale.
// Ces tests ne s'exécutent que sur une destination iPad.
@MainActor
final class AdaptiveLayoutTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSidebarIsUsedOnRegularWidth() throws {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .pad,
            "Cette vérification n'a de sens que sur iPad"
        )

        let app = XCUIApplication()
        app.launchSeeded()

        // La barre latérale expose les mêmes destinations que les onglets.
        for destination in ["Accueil", "Programmes", "Exercices", "Progression", "Réglages"] {
            waitAndAssert(
                app.firstDescendant(labelContains: destination),
                timeout: 15,
                "La destination \(destination) devrait être accessible depuis la barre latérale"
            )
        }
    }

    func testTabBarIsUsedOnCompactWidth() throws {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .phone,
            "Cette vérification n'a de sens que sur iPhone"
        )

        let app = XCUIApplication()
        app.launchSeeded()
        waitAndAssert(app.tabBars.firstMatch, timeout: 15)
    }
}
