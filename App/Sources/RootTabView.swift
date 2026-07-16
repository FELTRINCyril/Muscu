import SwiftUI

// Squelette de navigation principal : 5 onglets placeholders.
struct RootTabView: View {
    var body: some View {
        TabView {
            PlaceholderView(title: "Accueil")
                .tabItem {
                    Label("Accueil", systemImage: "house.fill")
                }

            PlaceholderView(title: "Programmes")
                .tabItem {
                    Label("Programmes", systemImage: "list.bullet.rectangle")
                }

            PlaceholderView(title: "Exercices")
                .tabItem {
                    Label("Exercices", systemImage: "dumbbell.fill")
                }

            PlaceholderView(title: "Progression")
                .tabItem {
                    Label("Progression", systemImage: "chart.line.uptrend.xyaxis")
                }

            PlaceholderView(title: "Réglages")
                .tabItem {
                    Label("Réglages", systemImage: "gearshape.fill")
                }
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
        .preferredColorScheme(.dark)
}
