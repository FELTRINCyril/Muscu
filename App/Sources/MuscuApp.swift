import SwiftUI
import SwiftData

@main
struct MuscuApp: App {
    let container: ModelContainer = {
        do {
            return try ModelContainer(for: Program.self, CompletedSession.self, ExerciseRecord.self, CustomExercise.self, ActiveWorkout.self)
        } catch {
            fatalError("Impossible de creer le ModelContainer: \(error)")
        }
    }()

    @State private var catalogStore = CatalogStore()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .preferredColorScheme(.dark)
                .environment(catalogStore)
        }
        .modelContainer(container)
    }
}
