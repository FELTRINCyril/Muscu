import XCTest

/// Diagnostic : le journal est lisible, désactivable et n'est jamais partagé
/// sans que son contenu ait été affiché en entier.
@MainActor
final class DiagnosticsFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// L'écran est long (explication, réglage, santé du store, journal,
    /// export). Les lignes non affichées n'existent pas dans l'arbre
    /// d'accessibilité — rendu lazy — donc on défile jusqu'à la ligne
    /// cherchée, en laissant chaque balayage se poser.
    private func scroll(_ app: XCUIApplication, to element: XCUIElement, maxSwipes: Int = 8) {
        for _ in 0..<maxSwipes where !element.exists {
            app.swipeUp()
            _ = element.waitForExistence(timeout: 2)
        }
    }

    private func openDiagnostics(_ app: XCUIApplication) {
        selectTab(app, "Réglages", showing: "Réglages")
        tapUntilReveals(
            app.buttons["settings.diagnostics"],
            reveals: app.navigationBars["Diagnostic"]
        )
    }

    func testTheScreenSaysWhatTheJournalContainsAndStartsEmpty() throws {
        let app = XCUIApplication()
        app.launchEmpty()
        openDiagnostics(app)

        XCTAssertTrue(
            app.firstDescendant(labelContains: "que des codes d’erreur").waitForExistence(timeout: 15),
            "Ce que contient le journal doit être dit avant tout partage"
        )
        XCTAssertTrue(
            app.firstDescendant(labelContains: "Aucune séance, mesure, donnée de santé").exists,
            "Ce qui n’y figure PAS doit être dit aussi"
        )
        let empty = app.staticTexts["diagnostics.empty"]
        scroll(app, to: empty)
        XCTAssertTrue(empty.exists, "Sur une installation neuve, le journal doit être vide")
    }

    func testTheStoreHealthIsShown() throws {
        let app = XCUIApplication()
        app.launchEmpty()
        openDiagnostics(app)

        let schema = app.staticTexts["diagnostics.schema"]
        scroll(app, to: schema)
        XCTAssertTrue(schema.exists, "La version de schéma fait partie de la santé du store")

        let migration = app.staticTexts["diagnostics.migration"]
        XCTAssertTrue(migration.exists || app.otherElements["diagnostics.migration"].exists,
                      "L’état de migration doit être visible")
    }

    func testTurningTheJournalOffSaysSoExplicitly() throws {
        let app = XCUIApplication()
        app.launchEmpty()
        openDiagnostics(app)

        let toggle = app.switches["diagnostics.enabled"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 15))
        XCTAssertEqual(toggle.value as? String, "1", "Le journal est actif par défaut")

        toggle.switches.firstMatch.tap()
        let disabled = app.staticTexts["diagnostics.disabled"]
        scroll(app, to: disabled)
        XCTAssertTrue(
            disabled.exists,
            "Une fois éteint, l’écran doit le dire au lieu d’afficher une liste vide ambiguë"
        )
    }

    /// Le rapport est montré en entier AVANT le partage : c'est la seule
    /// façon honnête de demander un consentement.
    func testTheReportIsShownBeforeItCanBeShared() throws {
        let app = XCUIApplication()
        app.launchEmpty()
        openDiagnostics(app)

        let export = app.buttons["diagnostics.export"]
        scroll(app, to: export)
        XCTAssertTrue(export.exists)
        tapUntilReveals(export, reveals: app.staticTexts["diagnostics.reportText"])

        let report = app.staticTexts["diagnostics.reportText"]
        XCTAssertTrue(report.exists)
        let text = report.label
        XCTAssertTrue(text.contains("Diagnostic Muscu"), "Le rapport doit être lisible avant partage")
        XCTAssertTrue(text.contains("## Stockage"), "Le rapport doit porter la santé du store")
        XCTAssertTrue(
            app.buttons["diagnostics.share"].exists,
            "Le partage n’est proposé qu’une fois le contenu affiché"
        )
    }
}
