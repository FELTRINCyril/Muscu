import XCTest

// Helpers de lancement partages par toute la suite : chaque test demarre
// l'app avec un etat SwiftData connu (vide ou seede), jamais avec l'etat
// laisse par une execution precedente. Voir App/Sources/UITestSupport.swift
// (cote app, #if DEBUG) pour le detail du seed.
@MainActor
extension XCUIApplication {
    /// Langue forcee pour toute la suite. Les tests verifient des libelles
    /// francais : sans ce forcage, la suite passerait ou echouerait selon la
    /// langue de la machine, ce qui n'est pas un test.
    private static let frenchArguments = [
        "-AppleLanguages", "(fr)",
        "-AppleLocale", "fr_FR",
    ]

    /// Store SwiftData entierement vide (aucun programme, aucun historique).
    func launchEmpty() {
        launchArguments = ["--uitest-reset"] + Self.frenchArguments
        launch()
    }

    /// Meme chose, dans la langue demandee. Sert a verifier que l'anglais
    /// est reellement livre, et pas seulement traduit dans le catalogue.
    func launchEmpty(language: String, locale: String) {
        launchArguments = [
            "--uitest-reset",
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", locale,
        ]
        launch()
    }

    /// Store SwiftData seede : "Programme Test" actif (Séance A classique +
    /// pyramide, Séance B intervalles + AMRAP), 1 séance dans l'historique,
    /// 2 records, 1 exercice perso. Cf. UITestSupport.seed pour le detail.
    func launchSeeded() {
        launchArguments = ["--uitest-reset", "--uitest-seed"] + Self.frenchArguments
        launch()
    }
}

@MainActor
extension XCUIApplication {
    /// Cherche un element (peu importe son type - certaines lignes de liste
    /// composees de plusieurs Text dans un Button/NavigationLink sont
    /// agregees par SwiftUI en un seul element d'accessibilite, d'autres
    /// non selon le contexte) dont le label contient `text`. Plus robuste
    /// qu'un query type par type (staticTexts/buttons) quand la structure
    /// exacte de l'arbre d'accessibilite n'est pas garantie.
    func firstDescendant(labelContains text: String) -> XCUIElement {
        descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    /// Ligne de resultat (Button) dont le label contient `text` - plus precis
    /// que firstDescendant(labelContains:) quand on sait deja que la cible
    /// est une ligne de liste tappable (evite de matcher un conteneur non
    /// interactif au meme label).
    func firstResultButton(labelContains text: String) -> XCUIElement {
        buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    /// Comme firstResultButton, mais choisit explicitement le premier match
    /// HITTABLE parmi tous ceux qui correspondent au label - indispensable
    /// quand une sheet/un ecran pousse recouvre un ecran precedent qui
    /// contient un texte similaire : ce dernier reste dans l'arbre
    /// d'accessibilite (non detruit, juste recouvert) et un simple
    /// `.firstMatch` peut donc pointer sur un element invisible et non
    /// tappable au lieu de celui reellement affiche.
    func firstHittableButton(labelContains text: String, timeout: TimeInterval = 20) -> XCUIElement {
        firstHittable(in: buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", text)), timeout: timeout)
    }

    /// Variante de firstHittableButton qui ne suppose pas le type Button
    /// (utile pour des lignes de liste dont le type exact d'accessibilite
    /// n'est pas garanti - NavigationLink, cellule custom, etc.).
    func firstHittableDescendant(labelContains text: String, timeout: TimeInterval = 20) -> XCUIElement {
        firstHittable(in: descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", text)), timeout: timeout)
    }

    /// Match EXACT (pas CONTAINS) sur un Button - utile quand `text` pourrait
    /// être un sous-ensemble du label d'un autre élément recouvert (ex : le
    /// nom d'un muscle "Pectoraux" est aussi un fragment du label composite
    /// "Nom d'exercice, Pectoraux" d'une ligne de catalogue recouverte par la
    /// sheet en cours).
    func firstHittableButton(exactLabel text: String, timeout: TimeInterval = 20) -> XCUIElement {
        firstHittable(in: buttons.matching(NSPredicate(format: "label == %@", text)), timeout: timeout)
    }

    /// Certaines listes SwiftUI (List/LazyVStack) ne matérialisent que les
    /// lignes visibles + une petite marge : un élément plus bas dans une
    /// longue liste (ex : "Pectoraux" dans la liste alphabétique des
    /// muscles) peut ne PAS exister du tout dans l'arbre d'accessibilité
    /// tant qu'il n'a jamais été scrollé en vue au moins une fois. Ce
    /// helper swipe vers le haut par petits pas jusqu'à ce que l'élément
    /// exact recherché apparaisse et devienne hittable.
    func scrollUntilHittableButton(exactLabel text: String, maxSwipes: Int = 12) -> XCUIElement {
        let query = buttons.matching(NSPredicate(format: "label == %@", text))
        for _ in 0..<maxSwipes {
            let match = query.firstMatch
            if match.exists, match.isHittable {
                return match
            }
            swipeUp()
            usleep(300_000)
        }
        return query.firstMatch
    }

    private func firstHittable(in query: XCUIElementQuery, timeout: TimeInterval) -> XCUIElement {
        let deadline = Date().addingTimeInterval(timeout)
        var fallback: XCUIElement?
        repeat {
            let all = query.allElementsBoundByIndex
            if let hit = all.first(where: { $0.isHittable }) {
                return hit
            }
            if fallback == nil { fallback = all.first }
            usleep(200_000)
        } while Date() < deadline
        return fallback ?? query.firstMatch
    }
}

@MainActor
extension XCUIElement {
    /// Tape un texte dans un champ de recherche puis laisse le temps à la
    /// liste filtrée (potentiellement volumineuse - le catalogue complet
    /// fait 873 exercices) de se stabiliser avant de continuer. Sans cette
    /// pause, une requête immédiatement après typeText() peut matcher un
    /// état de filtre intermédiaire (encore en cours de re-rendu au
    /// caractère précédent) et taper sur un élément qui a depuis bougé.
    func typeAndSettle(_ text: String, settleSeconds: UInt32 = 1) {
        tap()
        let app = XCUIApplication()
        if !app.keyboards.firstMatch.waitForExistence(timeout: 2) {
            coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            _ = app.keyboards.firstMatch.waitForExistence(timeout: 2)
        }
        // Envoyer le texte a l'application active evite que XCUITest
        // revalide un ancien snapshot du SearchField pendant que SwiftUI le
        // reconstruit apres la prise de focus (regression observee iOS 26).
        app.typeText(text)
        sleep(settleSeconds)
    }
}

@MainActor
extension XCTestCase {
    /// Attend qu'un element existe, avec un message d'echec explicite (plus
    /// lisible qu'un simple booleen dans les rapports de test).
    @discardableResult
    func waitAndAssert(
        _ element: XCUIElement,
        timeout: TimeInterval = 20,
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        let exists = element.waitForExistence(timeout: timeout)
        XCTAssertTrue(exists, message.isEmpty ? "Élément attendu introuvable : \(element)" : message, file: file, line: line)
        return exists
    }

    /// Tape un bouton et re-tape si l'ecran attendu n'apparait pas : un tap
    /// synthetise par XCUITest peut se perdre (arrive pendant une transition
    /// ou une phase non interactive) sans qu'aucune erreur ne soit levee.
    func tapUntilReveals(
        _ button: XCUIElement,
        reveals revealed: XCUIElement,
        attempts: Int = 3,
        timeoutPerAttempt: TimeInterval = 7,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(button.waitForExistence(timeout: 20), "Bouton introuvable : \(button)", file: file, line: line)
        for _ in 0..<attempts {
            if button.exists, button.isHittable {
                button.tap()
            }
            if revealed.waitForExistence(timeout: timeoutPerAttempt) { return }
        }
        XCTFail("Jamais apparu apres \(attempts) taps sur \(button) : \(revealed)", file: file, line: line)
    }

    /// Tape un champ jusqu'a obtenir le focus clavier puis saisit le texte.
    /// Un tap unique peut partir pendant l'animation de presentation d'une
    /// sheet et ne pas donner le focus : typeText echouerait alors avec
    /// "Neither element nor any descendant has keyboard focus".
    func focusAndType(
        _ field: XCUIElement,
        text: String,
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(field.waitForExistence(timeout: timeout), "Champ introuvable : \(field)", file: file, line: line)
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if field.isHittable {
                field.tap()
            }
            if (field.value(forKey: "hasKeyboardFocus") as? Bool) == true {
                field.typeText(text)
                return
            }
            usleep(300_000)
        } while Date() < deadline
        XCTFail("Focus clavier jamais obtenu sur : \(field)", file: file, line: line)
    }

    /// Attend qu'un element ait disparu de l'arbre d'accessibilite. Utile
    /// pour synchroniser sur la fermeture d'un ecran ephemere (ex : chrono
    /// de repos qui expire de lui-meme) avant de taper derriere.
    func waitForDisappearance(
        _ element: XCUIElement,
        timeout: TimeInterval = 20,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(result, .completed, "Élément toujours présent après \(timeout) s : \(element)", file: file, line: line)
    }

    /// Valide l'écran de préparation (check-in et propositions de
    /// progression) pour entrer dans la séance. Cet écran est facultatif :
    /// on le traverse sans rien renseigner.
    func startFromPreparation(
        _ app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        tapUntilReveals(
            app.buttons["prep.start"],
            reveals: app.buttons["Commencer directement la séance"],
            file: file,
            line: line
        )
    }

    /// Attend que le runner affiche l'exercice attendu.
    ///
    /// Vise l'identifiant du titre plutot qu'une recherche sur tout l'arbre
    /// d'accessibilite : `descendants(matching: .any)` est lent et devient
    /// peu fiable quand la suite complete tourne depuis longtemps.
    func waitForRunnerExercise(
        _ app: XCUIApplication,
        nameContains text: String,
        timeout: TimeInterval = 20,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let title = app.staticTexts["workout.exerciseName"]
        let predicate = NSPredicate(format: "label CONTAINS[c] %@", text)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: title)
        XCTAssertEqual(
            XCTWaiter().wait(for: [expectation], timeout: timeout),
            .completed,
            "Le runner devrait afficher « \(text) », affiché : « \(title.exists ? title.label : "aucun titre")»",
            file: file,
            line: line
        )
    }

    /// Bascule d'onglet fiable. Un tap synthetise sur la tab bar peut se
    /// perdre quand l'app est encore en train de se stabiliser apres le
    /// lancement (reset/seed du store) : XCUITest ne signale alors aucune
    /// erreur, mais l'ecran attendu n'apparait jamais. On re-tape tant que
    /// la barre de navigation cible n'est pas affichee.
    func selectTab(
        _ app: XCUIApplication,
        _ tabName: String,
        showing navigationTitle: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        tapUntilReveals(
            app.tabBars.buttons[tabName],
            reveals: app.navigationBars[navigationTitle],
            file: file,
            line: line
        )
    }

    /// Tap defensif : attend l'existence puis la "hittability" avant de taper,
    /// pour eviter les echecs intermittents purement lies au timing des
    /// animations SwiftUI (sheets, navigation push/pop, confirmationDialog).
    func tapWhenReady(
        _ element: XCUIElement,
        timeout: TimeInterval = 20,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Élément introuvable avant tap : \(element)", file: file, line: line)
        let predicate = NSPredicate(format: "hittable == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        _ = XCTWaiter().wait(for: [expectation], timeout: timeout)
        element.tap()
    }
}
