import Foundation
#if os(iOS) && !targetEnvironment(macCatalyst)
import AppIntents
#endif

/// Action demandee par un bouton de la Live Activity.
enum LiveActivityAction: Equatable, Sendable {
    /// Valide la serie identifiee par `slotKey` avec les valeurs proposees
    /// (pendant un repos : arrete le repos et valide la serie qui suit).
    case completeSet(slotKey: String)
    /// Termine le repos en cours.
    case skipRest
    /// Ajuste le repos en cours : −15 s ou +15 s, rien d'autre.
    case adjustRest(seconds: Int)
}

/// Point d'entree des boutons de la Live Activity.
///
/// Les intents ci-dessous sont compiles dans l'application ET dans
/// l'extension de widgets (le bouton doit connaitre le type), mais un
/// `LiveActivityIntent` s'execute TOUJOURS dans le processus de
/// l'application. Celle-ci installe le gestionnaire au lancement ; dans
/// l'extension il reste vide, et rien n'y est jamais execute.
@MainActor
enum LiveActivityActionCenter {
    static var handler: (@MainActor (LiveActivityAction) async -> Void)?

    static func run(_ action: LiveActivityAction) async {
        await handler?(action)
    }
}

// ActivityKit et `LiveActivityIntent` n'existent ni sur Mac Catalyst ni sur
// la montre (qui compile aussi ce dossier).
#if os(iOS) && !targetEnvironment(macCatalyst)

/// « Valider » depuis l'ecran verrouille ou la Dynamic Island.
struct CompleteSetActivityIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Valider la série"
    static let description = IntentDescription("Valide la série affichée avec la charge et les répétitions proposées.")
    /// Reserve a la Live Activity : la proposer dans Raccourcis validerait
    /// une serie sans que l'utilisateur la voie.
    static let isDiscoverable = false

    @Parameter(title: "Série")
    var slotKey: String

    init() {}

    init(slotKey: String) {
        self.slotKey = slotKey
    }

    func perform() async throws -> some IntentResult {
        await LiveActivityActionCenter.run(.completeSet(slotKey: slotKey))
        return .result()
    }
}

/// « Passer le repos ».
struct SkipRestActivityIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Passer le repos"
    static let description = IntentDescription("Termine le repos en cours.")
    static let isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult {
        await LiveActivityActionCenter.run(.skipRest)
        return .result()
    }
}

/// « −15 s » / « +15 s » sur le repos en cours. Un seul intent parametre :
/// le gestionnaire refuse toute autre valeur (`RestAdjustment.isAllowed`).
struct AdjustRestActivityIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Ajuster le repos"
    static let description = IntentDescription("Retire ou ajoute quinze secondes au repos en cours.")
    static let isDiscoverable = false

    @Parameter(title: "Secondes")
    var seconds: Int

    init() {}

    init(seconds: Int) {
        self.seconds = seconds
    }

    func perform() async throws -> some IntentResult {
        await LiveActivityActionCenter.run(.adjustRest(seconds: seconds))
        return .result()
    }
}

#endif
