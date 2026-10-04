import Foundation
import SwiftData
import MuscuEngine

/// Destination demandee par un raccourci. L'interface l'observe et s'y rend
/// au prochain affichage.
enum IntentDestination: Equatable, Sendable {
    case home
    case program(UUID)
    case exercise(String)
    case weeklySummary
    /// Lien direct : reprendre la seance en cours.
    case resumeWorkout
    /// Lien direct : preparer la prochaine seance du programme actif.
    case startNextSession
    /// Lien direct : proposer de refaire une seance de l'historique.
    case replaySession(UUID)

    init(_ link: MuscuDeepLink) {
        switch link {
        case .resumeWorkout: self = .resumeWorkout
        case .startNextSession: self = .startNextSession
        case .replaySession(let id): self = .replaySession(id)
        }
    }

    /// Destinations consommees par l'accueil, qui seul peut presenter une
    /// seance.
    var isHandledByHome: Bool {
        switch self {
        case .resumeWorkout, .startNextSession, .replaySession: return true
        case .home, .program, .exercise, .weeklySummary: return false
        }
    }
}

/// Point de rendez-vous entre les App Intents et l'interface.
///
/// Un intent ne manipule jamais la navigation directement : il depose une
/// demande, l'application la consomme UNE FOIS. Sans cela, revenir en
/// arriere relancerait la meme navigation en boucle.
@MainActor
@Observable
final class IntentRouter {
    static let shared = IntentRouter()

    private(set) var pending: IntentDestination?

    private init() {}

    func request(_ destination: IntentDestination) {
        pending = destination
    }

    func consume() -> IntentDestination? {
        defer { pending = nil }
        return pending
    }
}

/// Conteneur SwiftData pour les intents.
///
/// Un intent peut s'executer sans que l'application soit lancee : il lui
/// faut donc son propre acces au store, ouvert avec le MEME schema et le
/// MEME plan de migration que l'application.
@MainActor
enum IntentStore {
    private static var cached: ModelContainer?

    /// Conteneur de l'application, enregistre au lancement. Un intent
    /// execute dans le processus de l'application ecrit ainsi dans le MEME
    /// conteneur que l'interface : ce qu'il modifie s'affiche aussitot.
    static func register(_ container: ModelContainer) {
        cached = container
    }

    static func container() throws -> ModelContainer {
        if let cached { return cached }
        let container = try ModelContainer(
            for: Schema(versionedSchema: MuscuCurrentSchema.self),
            migrationPlan: MuscuMigrationPlan.self
        )
        cached = container
        return container
    }

    static func context() throws -> ModelContext {
        ModelContext(try container())
    }

    /// Le catalogue est un JSON embarque en LECTURE SEULE : il n'a pas
    /// besoin du contexte principal, et une requete Siri peut le charger
    /// depuis n'importe quel acteur.
    nonisolated static func catalog() -> ExerciseCatalog? {
        try? ExerciseCatalog.load()
    }
}
