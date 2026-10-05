import XCTest

// Parcours de la phase 3 : profil, préparation de séance (check-in et
// progression proposée) et journal d'adaptation.
@MainActor
final class PlanningFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Le profil est facultatif : on part d'un état sans profil, on le crée,
    /// et les réglages saisis sont bien conservés.
    func testCreateAndEditProfile() {
        let app = XCUIApplication()
        app.launchEmpty()

        selectTab(app, "Réglages", showing: "Réglages")
        tapWhenReady(app.buttons["settings.profile"])
        waitAndAssert(app.navigationBars["Profil"], timeout: 15)

        tapWhenReady(app.buttons["profile.create"])
        waitAndAssert(app.firstDescendant(labelContains: "Objectif principal"), timeout: 15)

        // Un jour disponible coché doit le rester après un aller-retour.
        // Les sections d'un Form ne sont matérialisées qu'une fois visibles :
        // on fait défiler jusqu'au jour recherché avant de le taper.
        let monday = scrollToSwitch(app, named: "Lundi")
        toggle(monday)
        XCTAssertEqual(monday.value as? String, "1", "Le jour devrait être coché juste après le tap")

        tapWhenReady(app.navigationBars["Profil"].buttons.firstMatch)
        waitAndAssert(app.navigationBars["Réglages"], timeout: 15)
        tapWhenReady(app.buttons["settings.profile"])
        waitAndAssert(app.navigationBars["Profil"], timeout: 15)

        let reopened = scrollToSwitch(app, named: "Lundi")
        XCTAssertEqual(reopened.value as? String, "1", "Le jour coché doit être conservé")
    }

    /// Avant une séance : le check-in est proposé, la progression s'appuie
    /// sur l'historique, et rien n'est appliqué sans décision.
    func testSessionPreparationShowsCheckInAndExplainedProgression() {
        let app = XCUIApplication()
        app.launchSeeded()

        tapWhenReady(app.buttons["Lancer la séance"])
        waitAndAssert(app.navigationBars["Avant la séance"], timeout: 20)

        // La proposition est en haut de l'écran et doit être justifiée par
        // une performance réelle.
        waitAndAssert(app.staticTexts["Progression proposée"], timeout: 10, "L'historique seedé doit produire une proposition")
        let justification = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "8 répétitions")
        ).firstMatch
        waitAndAssert(justification, timeout: 10, "La proposition doit citer la performance qui la justifie")
        tapWhenReady(app.buttons["prep.accept"])
        waitAndAssert(app.staticTexts["Décision enregistrée"], timeout: 10)

        // Le check-in est présent et facultatif ; une douleur déclarée doit
        // déclencher un message prudent, jamais un diagnostic.
        _ = scroll(app, to: app.staticTexts["Comment vous sentez-vous ?"])
        let painStepper = scrollToStepper(app, identifier: "prep.pain")
        // Les deux boutons d'un Stepper sont fournis par UIKit et portent un
        // libellé SYSTEME (« Increment » / « Incrémenter » selon la langue).
        // On les adresse donc par leur rang dans le stepper, jamais par leur
        // texte : sinon le test dirait « vert » ou « rouge » selon la langue.
        waitAndAssert(painStepper, timeout: 10, "Le stepper de douleur devrait être présent")
        let increment = painStepper.buttons.element(boundBy: 1)
        waitAndAssert(increment, timeout: 10, "Le bouton d'incrément de la douleur devrait être présent")
        for _ in 0..<6 { increment.tap() }

        let caution = scroll(app, to: app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "professionnel de santé")
        ).firstMatch)
        XCTAssertTrue(caution.exists, "Une douleur déclarée doit déclencher un message prudent")

        // « Commencer » est dans la barre d'outils : toujours atteignable.
        tapWhenReady(app.buttons["prep.start"])
        waitAndAssert(app.buttons["Commencer directement la séance"], timeout: 20)
    }

    /// Une adaptation acceptée est tracée dans le journal et annulable.
    func testAcceptedAdaptationIsJournalledAndRevertible() {
        let app = XCUIApplication()
        app.launchSeeded()

        tapWhenReady(app.buttons["Lancer la séance"])
        waitAndAssert(app.navigationBars["Avant la séance"], timeout: 20)
        tapWhenReady(app.buttons["prep.accept"], timeout: 15)
        waitAndAssert(app.staticTexts["Décision enregistrée"], timeout: 10)

        // On quitte la préparation sans démarrer la séance.
        tapWhenReady(app.buttons["Annuler"])
        waitAndAssert(app.buttons["Lancer la séance"], timeout: 15)

        selectTab(app, "Progression", showing: "Progression")
        // Le journal est derrière le menu « Plus » de l'onglet Progression.
        tapWhenReady(app.buttons["progress.moreMenu"])
        tapWhenReady(app.buttons["Adaptations"], timeout: 10)
        waitAndAssert(app.navigationBars["Adaptations"], timeout: 15)
        waitAndAssert(app.staticTexts["Appliquée"], timeout: 10)

        tapWhenReady(app.buttons["adaptation.revert"])
        waitAndAssert(app.staticTexts["Annulée"], timeout: 10)
        waitForDisappearance(app.buttons["adaptation.revert"], timeout: 10)
    }

    // MARK: - Helpers

    /// Fait défiler jusqu'à ce qu'un interrupteur soit matérialisé et
    /// atteignable. Une `List` SwiftUI ne crée pas les lignes hors écran :
    /// sans cela, l'élément n'existe tout simplement pas dans l'arbre.
    private func scrollToSwitch(
        _ app: XCUIApplication,
        named name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        scroll(app, to: app.switches[name], file: file, line: line)
    }

    private func scrollToStepper(
        _ app: XCUIApplication,
        identifier: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        scroll(app, to: app.steppers[identifier], file: file, line: line)
    }

    /// Bascule un interrupteur de formulaire.
    ///
    /// Une ligne de `Form` contenant un `Toggle` expose DEUX éléments de type
    /// switch : le conteneur pleine largeur (dont le tap central ne bascule
    /// rien) et le contrôle réel, collé au bord droit. On tape donc le bord
    /// droit de la ligne.
    private func toggle(_ element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        usleep(300_000)
    }

    private func scroll(
        _ app: XCUIApplication,
        to element: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        // On ne teste que `exists` dans la boucle : `isHittable` declenche une
        // requete bien plus couteuse, repetee ici a chaque tour.
        for _ in 0..<8 {
            if element.exists { break }
            app.swipeUp()
            usleep(300_000)
        }
        XCTAssertTrue(element.exists && element.isHittable, "Élément jamais atteint : \(element)", file: file, line: line)
        return element
    }
}
