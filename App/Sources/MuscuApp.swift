import SwiftUI
import SwiftData
import UserNotifications

@main
struct MuscuApp: App {
    let container: ModelContainer
    let startupError: String?

    init() {
        LegacyDataCleanup.run()
        #if DEBUG
        // Les tests UI demandent explicitement un etat de depart propre
        // (--uitest-reset). Pendant le developpement, le store du simulateur
        // peut dater d'une version intermediaire du schema et devenir
        // illisible : dans ce cas SEULEMENT, et uniquement en DEBUG derriere
        // ce drapeau explicite, on repart d'un store neuf. Aucun chemin de
        // production ne supprime jamais de donnees.
        UITestSupport.resetStoreIfUnreadable()
        #endif
        do {
            let schema = Schema(versionedSchema: MuscuCurrentSchema.self)
            let container = try ModelContainer(
                for: schema,
                migrationPlan: MuscuMigrationPlan.self
            )
            #if DEBUG
            UITestSupport.configure(container: container)
            #endif
            try SchemaUpgrade.run(context: container.mainContext)
            try DataIntegrityRepair.run(context: container.mainContext)
            // Purge differee des suppressions logiques : un tombstone garde
            // sa raison d'etre 90 jours, le temps qu'un appareil hors ligne
            // recoive la suppression. Au-dela il ne sert plus a rien.
            //
            // Volontairement NON propagee : une purge est un entretien de
            // confort. La propager ferait basculer tout le demarrage vers le
            // conteneur de secours en memoire, et l'utilisateur perdrait
            // l'acces a ses donnees pour une tache qui pouvait attendre.
            do {
                try TombstonePurge.run(context: container.mainContext)
            } catch {
                DiagnosticsCenter.record(.store, code: "store.tombstones.purgeFailed", error: error)
            }
            self.container = container
            self.startupError = nil
            self._phoneConnectivity = State(initialValue: PhoneConnectivityService(modelContainer: container))
            self.notificationResponder = NotificationResponder(container: container)
            UNUserNotificationCenter.current().delegate = self.notificationResponder
            Self.installOutsideActions(container: container)
            return
        } catch {
            // Ne jamais effacer le store automatiquement. Un conteneur
            // temporaire permet d'ouvrir l'app et d'expliquer le probleme;
            // les donnees originales restent intactes sur disque.
            DiagnosticsCenter.record(.store, code: "store.open.failed", error: error)
            do {
                let fallback = ModelConfiguration(isStoredInMemoryOnly: true)
                let schema = Schema(versionedSchema: MuscuCurrentSchema.self)
                let container = try ModelContainer(for: schema, configurations: fallback)
                self.container = container
                self.startupError = error.localizedDescription
                self._phoneConnectivity = State(initialValue: PhoneConnectivityService(modelContainer: container))
                self.notificationResponder = NotificationResponder(container: container)
                UNUserNotificationCenter.current().delegate = self.notificationResponder
                Self.installOutsideActions(container: container)
            } catch {
                fatalError("Impossible d'ouvrir même le conteneur de secours: \(error)")
            }
        }
    }

    @State private var catalogStore = CatalogStore()
    @State private var networkStatus = NetworkStatus()
    @State private var phoneConnectivity: PhoneConnectivityService
    @Environment(\.scenePhase) private var scenePhase

    /// Delegue retenu par l'application : `UNUserNotificationCenter` ne
    /// conserve qu'une reference faible a son delegue.
    private let notificationResponder: NotificationResponder

    var body: some Scene {
        WindowGroup {
            RootTabView(startupError: startupError)
                .preferredColorScheme(.dark)
                .environment(catalogStore)
                .environment(networkStatus)
                .task {
                    await refreshReminders()
                    // Une seance interrompue par un arret brutal peut laisser
                    // une Live Activity ouverte : on la ferme au demarrage,
                    // SAUF si la seance est toujours a reprendre. Ses boutons
                    // ont pu relancer l'application en arriere-plan : elle
                    // decrit alors la seance en cours, et on la reprend.
                    if WorkoutState.pendingActiveWorkout(modelContext: container.mainContext) != nil {
                        WorkoutActivityController.adoptRunningActivity()
                    } else {
                        await WorkoutActivityController.endOrphans()
                    }
                    // Meme chose pour une seance Sante en direct : elle est
                    // rattachee, terminee ou abandonnee selon ce qu'est
                    // devenue la seance Muscu.
                    await LiveHealthWorkoutController.shared.recover(
                        in: container.mainContext,
                        store: AppServices.healthStore
                    )
                    WidgetSnapshotService.refresh(in: container.mainContext, catalogStore: catalogStore)
                    // La montre recoit le meme instantane que les widgets :
                    // un seul calcul, donc aucun risque de divergence.
                    phoneConnectivity.publish(WidgetSnapshotStore.read())
                }
                .environment(phoneConnectivity)
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.NSSystemTimeZoneDidChange)) { _ in
                    // Un changement de fuseau decale tous les rappels : on
                    // recalcule au lieu de laisser des heures fausses.
                    Task { await refreshReminders() }
                }
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await refreshReminders() }
        }
    }

    /// Intents et boutons de la Live Activity s'executent dans ce processus,
    /// parfois avant toute interface : ils recoivent le conteneur ici, au
    /// tout debut du lancement.
    @MainActor
    private static func installOutsideActions(container: ModelContainer) {
        IntentStore.register(container)
        LiveWorkoutActions.install(container: container)
    }

    @MainActor
    private func refreshReminders() async {
        await ReminderService.refresh(
            in: container.mainContext,
            scheduler: AppServices.notificationScheduler,
            catalog: catalogStore.catalog
        )
    }
}
