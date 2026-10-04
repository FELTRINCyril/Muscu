import Foundation
#if os(iOS) && !targetEnvironment(macCatalyst)
import AppIntents
#endif

/// Action demandee par un bouton de la Live Activity.
enum LiveActivityAction: Equatable, Sendable {
    /// Valide la serie identifiee par `slotKey` avec les valeurs proposees.
    case completeSet(slotKey: String)
    /// Termine le repos en cours (ou son depassement).
    case skipRest
    /// Prolonge le repos en cours.
    case extendRest(seconds: Int)
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

/// « Valider la série » depuis l'ecran verrouille ou la Dynamic Island.
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

/// « +30 s » sur le repos en cours.
struct ExtendRestActivityIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Prolonger le repos"
    static let description = IntentDescription("Ajoute trente secondes au repos en cours.")
    static let isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult {
        await LiveActivityActionCenter.run(.extendRest(seconds: 30))
        return .result()
    }
}

#endif
