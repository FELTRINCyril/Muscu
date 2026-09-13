import SwiftUI
import SwiftData

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
            self.container = container
            self.startupError = nil
        } catch {
            // Ne jamais effacer le store automatiquement. Un conteneur
            // temporaire permet d'ouvrir l'app et d'expliquer le probleme;
            // les donnees originales restent intactes sur disque.
            do {
                let fallback = ModelConfiguration(isStoredInMemoryOnly: true)
                let schema = Schema(versionedSchema: MuscuCurrentSchema.self)
                self.container = try ModelContainer(for: schema, configurations: fallback)
                self.startupError = error.localizedDescription
            } catch {
                fatalError("Impossible d'ouvrir même le conteneur de secours: \(error)")
            }
        }
    }

    @State private var catalogStore = CatalogStore()
    @State private var networkStatus = NetworkStatus()

    var body: some Scene {
        WindowGroup {
            RootTabView(startupError: startupError)
                .preferredColorScheme(.dark)
                .environment(catalogStore)
                .environment(networkStatus)
        }
        .modelContainer(container)
    }
}
