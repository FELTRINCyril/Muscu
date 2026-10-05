import XCTest

/// Très grandes tailles de texte (AX5).
///
/// Le mécanisme (`@ScaledMetric`, styles de texte) est en place ; ce que ces
/// tests vérifient est autre chose : qu'aux tailles extrêmes les commandes
/// **restent atteignables et actionnables**, et non poussées hors de l'écran
/// ou réduites à une cible inatteignable.
@MainActor
final class DynamicTypeFlowTests: XCTestCase {
    /// AX5 : la plus grande taille proposée par iOS.
    private let extremeSize = "UICTContentSizeCategoryAccessibilityXXXL"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func scroll(_ app: XCUIApplication, to element: XCUIElement, maxSwipes: Int = 12) {
        for _ in 0..<maxSwipes where !(element.exists && element.isHittable) {
            app.swipeUp()
            _ = element.waitForExistence(timeout: 2)
        }
    }

    func testTheTabBarSurvivesTheLargestTextSize() {
        let app = XCUIApplication()
        app.launchEmpty(contentSizeCategory: extremeSize)

        // La barre d'onglets passe en libellés empilés à ces tailles : les
        // cinq destinations doivent rester atteignables.
        for tab in ["Accueil", "Programmes", "Exercices", "Progression", "Réglages"] {
            let button = app.buttons[tab]
            XCTAssertTrue(
                button.waitForExistence(timeout: 20),
                "L’onglet « \(tab) » doit rester présent en taille AX5"
            )
        }
    }

    /// Un écran de réglages est le pire cas : beaucoup de lignes, des
    /// libellés longs et un interrupteur au bout de chacune.
    func testASettingsScreenStaysUsableAtTheLargestTextSize() {
        let app = XCUIApplication()
        app.launchEmpty(contentSizeCategory: extremeSize)

        selectTab(app, "Réglages", showing: "Réglages")
        // En AX5 chaque ligne occupe plusieurs fois sa hauteur habituelle :
        // la ligne visée passe sous la ligne de flottaison. Le critère juste
        // est « atteignable en défilant », pas « visible d'emblée ».
        let diagnostics = app.buttons["settings.diagnostics"]
        scroll(app, to: diagnostics)
        tapUntilReveals(diagnostics, reveals: app.navigationBars["Diagnostic"])

        let toggle = app.switches["diagnostics.enabled"]
        scroll(app, to: toggle)
        XCTAssertTrue(toggle.exists, "L’interrupteur du journal doit rester atteignable en AX5")
        XCTAssertTrue(toggle.isHittable, "Atteignable ne suffit pas : il doit rester actionnable")
    }

    /// Les gros chiffres du runner sont ceux qui utilisaient une taille figée :
    /// ce sont eux qui doivent grandir, sans emporter les boutons hors écran.
    func testTheSetLoggerStaysActionableAtTheLargestTextSize() {
        let app = XCUIApplication()
        app.launchSeeded(contentSizeCategory: extremeSize)

        tapWhenReady(app.buttons["Lancer la séance"])
        startFromPreparation(app)
        tapWhenReady(app.buttons["Commencer directement la séance"], timeout: 20)

        let increment = app.buttons["Augmenter les répétitions"]
        XCTAssertTrue(
            increment.waitForExistence(timeout: 20),
            "Le bouton d’incrément doit porter un libellé lisible par VoiceOver, pas un nom de symbole"
        )
        // La carte de saisie est dans une ScrollView : en AX5 les commandes
        // descendent sous l'écran, elles ne disparaissent pas.
        scroll(app, to: increment)
        XCTAssertTrue(increment.isHittable, "Il doit rester actionnable en taille AX5")
        XCTAssertGreaterThanOrEqual(
            increment.frame.height, 44,
            "Une cible tactile descend rarement sous 44 points sans devenir pénible à viser"
        )
    }
}
