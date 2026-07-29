import SwiftUI
import SwiftData

@main
struct MuscuApp: App {
    let container: ModelContainer = {
        do {
            let container = try ModelContainer(for: Program.self, CompletedSession.self, ExerciseRecord.self, CustomExercise.self, ActiveWorkout.self)
            #if DEBUG
            UITestSupport.configure(container: container)
            #endif
            return container
        } catch {
            fatalError("Impossible de creer le ModelContainer: \(error)")
        }
    }()

    @State private var catalogStore = CatalogStore()
    @State private var networkStatus = NetworkStatus()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .preferredColorScheme(.dark)
                .environment(catalogStore)
                .environment(networkStatus)
        }
        .modelContainer(container)
    }
}
