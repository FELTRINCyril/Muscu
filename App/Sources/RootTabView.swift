import SwiftUI
import SwiftData

// Squelette de navigation principal : 5 onglets. La selection est portee ici
// (et non dans chaque vue) car l'etat vide de l'Accueil doit pouvoir rediriger
// vers l'onglet Programmes.
struct RootTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(selectedTab: $selectedTab)
                .tabItem {
                    Label("Accueil", systemImage: "house.fill")
                }
                .tag(0)

            ProgramsView()
                .tabItem {
                    Label("Programmes", systemImage: "list.bullet.rectangle")
                }
                .tag(1)

            ExercisesView()
                .tabItem {
                    Label("Exercices", systemImage: "dumbbell.fill")
                }
                .tag(2)

            ProgressTabView()
                .tabItem {
                    Label("Progression", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(3)

            PlaceholderView(title: "Réglages")
                .tabItem {
                    Label("Réglages", systemImage: "gearshape.fill")
                }
                .tag(4)
        }
        .tint(Theme.accent)
    }
}

private struct PlaceholderView: View {
    let title: String

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            Text(title)
                .font(.title2)
                .foregroundStyle(.white)
        }
    }
}

#Preview {
    RootTabView()
        .environment(CatalogStore())
        .modelContainer(for: CustomExercise.self, inMemory: true)
        .preferredColorScheme(.dark)
}
