import Foundation
import SwiftData
import MuscuEngine

/// Seance en cours, joignable hors de l'interface.
///
/// Les boutons de la Live Activity et les intents Siri s'executent dans le
/// processus de l'application, parfois sans qu'aucun ecran ne soit affiche
/// (application relancee en arriere-plan par le systeme). Ils doivent agir
/// sur LA seance en cours, par le meme coordinateur que l'interface :
/// jamais une seconde copie qui divergerait.
///
/// Le coordinateur est retenu tant que la seance n'est ni terminee ni
/// abandonnee ; l'interface qui la reprend ensuite retrouve le meme objet
/// (cf. `WorkoutState.resumeOrAdopt`).
@MainActor
final class LiveWorkoutRegistry {
    static let shared = LiveWorkoutRegistry()

    private init() {}

    private(set) var current: WorkoutState?
    /// Coordinateur dont le deroule est actuellement a l'ecran.
    private var presentedStateID: UUID?

    func register(_ state: WorkoutState) {
        current = state
    }

    func unregister(_ state: WorkoutState) {
        if current === state { current = nil }
        if presentedStateID == state.id { presentedStateID = nil }
    }

    /// Coordinateur deja en memoire pour cette seance, dans ce contexte.
    func state(for activeWorkout: ActiveWorkout, in context: ModelContext) -> WorkoutState? {
        // Comparaison par identifiant persistant, sans lire les attributs :
        // une seance supprimee ailleurs (abandon depuis l'alerte de reprise,
        // effacement des donnees) ne doit jamais etre relue.
        guard let current,
              !current.isClosed,
              current.modelContext === context,
              let workout = current.activeWorkout,
              workout.modelContext != nil,
              !workout.isDeleted,
              workout.persistentModelID == activeWorkout.persistentModelID else { return nil }
        return current
    }

    func runnerDidAppear(_ state: WorkoutState) {
        presentedStateID = state.id
    }

    func runnerDidDisappear(_ state: WorkoutState) {
        if presentedStateID == state.id { presentedStateID = nil }
    }

    /// Le deroule d'une seance est deja affiche : un lien « reprendre » n'a
    /// rien a presenter de plus.
    var isRunnerVisible: Bool { presentedStateID != nil }
}

/// Execution des actions venues de l'exterieur de l'interface : boutons de
/// la Live Activity, intents Siri de fin et d'abandon.
@MainActor
enum LiveWorkoutActions {
    private static var container: ModelContainer?
    /// Catalogue charge a la demande : une relance en arriere-plan pour un
    /// bouton de la Live Activity n'a pas d'interface, donc pas d'environnement.
    private static var catalogStore: CatalogStore?

    /// Installe le gestionnaire des boutons de la Live Activity. Appele au
    /// lancement de l'application, AVANT que le systeme n'execute un intent.
    static func install(container: ModelContainer) {
        self.container = container
        LiveActivityActionCenter.handler = { action in
            await perform(action)
        }
    }

    /// Seance en cours : le coordinateur deja en memoire, sinon la seance
    /// persistee reprise exactement comme au lancement de l'application.
    /// `nil` s'il n'y a pas de seance en cours.
    static func currentState() -> WorkoutState? {
        guard let container else { return nil }
        // L'activite affichee est peut-etre anterieure a ce lancement : on
        // la reprend pour pouvoir la mettre a jour ou la fermer.
        WorkoutActivityController.adoptRunningActivity()
        let context = container.mainContext
        guard let pending = WorkoutState.pendingActiveWorkout(modelContext: context) else { return nil }
        let catalog = catalogStore ?? CatalogStore()
        catalogStore = catalog
        return WorkoutState.resumeOrAdopt(
            from: pending,
            modelContext: context,
            catalogStore: catalog,
            restTimer: RestTimer()
        )
    }

    /// Contexte de l'application, pour ce qui agit hors de l'interface.
    static var modelContext: ModelContext? { container?.mainContext }

    /// Demarre une seance demandee depuis la montre : la prochaine seance du
    /// programme actif (celle du bouton « Commencer » de l'accueil) ou une
    /// seance libre. `nil` si une seance est deja en cours, s'il n'y a pas
    /// de prochaine seance, ou si l'enregistrement a echoue.
    static func startWorkout(free: Bool) -> WorkoutState? {
        guard let container else { return nil }
        let context = container.mainContext
        // Une seule seance active a la fois, comme sur l'accueil.
        guard WorkoutState.pendingActiveWorkout(modelContext: context) == nil else { return nil }
        let catalog = catalogStore ?? CatalogStore()
        catalogStore = catalog

        let state: WorkoutState
        if free {
            state = WorkoutState(freeSessionWith: context, catalogStore: catalog, restTimer: RestTimer())
        } else {
            guard let session = WatchMirrorPublisher.nextProgramSession(in: context) else { return nil }
            state = WorkoutState(programSession: session, modelContext: context, catalogStore: catalog, restTimer: RestTimer())
        }
        guard state.activeWorkout != nil else {
            // Demarrage non enregistre : rien ne doit rester en memoire.
            LiveWorkoutRegistry.shared.unregister(state)
            return nil
        }
        return state
    }

    /// Bouton de la Live Activity : meme action que le bouton equivalent de
    /// l'application, puis mise a jour de l'activite.
    static func perform(_ action: LiveActivityAction) async {
        guard let state = currentState() else {
            // Plus aucune seance (terminee ailleurs, abandonnee) : une Live
            // Activity restee affichee n'a plus rien a montrer.
            await WorkoutActivityController.endOrphans()
            return
        }
        switch action {
        case .completeSet(let slotKey):
            // Une serie qui n'est plus celle affichee n'est pas validee :
            // l'activite est seulement remise a jour.
            state.logProposedSet(slotKey: slotKey)
        case .skipRest:
            // « Passer » de l'ecran de repos, et fin du depassement.
            state.restTimer.skip()
        case .extendRest(let seconds):
            // Seul le +30 s de l'application existe : pas de duree libre.
            if seconds == 30 { state.restTimer.addThirtySeconds() }
        }
        await state.refreshLiveActivityNow()
    }
}
