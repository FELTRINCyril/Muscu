import SwiftUI
import SwiftData

// Squelette de navigation principal : 5 onglets placeholders.
struct RootTabView: View {
    var body: some View {
        TabView {
            AccueilPlaceholderView()
                .tabItem {
                    Label("Accueil", systemImage: "house.fill")
                }

            ProgramsView()
                .tabItem {
                    Label("Programmes", systemImage: "list.bullet.rectangle")
                }

            ExercisesView()
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

// Onglet Accueil minimal : point d'entree legitime vers le runner de seance
// (bouton "Lancer la seance" sur le programme actif) + detection de reprise
// d'une seance interrompue. La Task 21 remplacera cet onglet par le vrai
// tableau de bord (carte de lancement contextuelle, vue semaine, records) ;
// ce bouton reste donc volontairement sommaire mais fonctionnel.
private struct AccueilPlaceholderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(CatalogStore.self) private var catalogStore
    @Query(sort: \Program.name) private var programs: [Program]

    @State private var restTimer = RestTimer()
    @State private var workoutState: WorkoutState?
    @State private var showingRunner = false

    @State private var pendingActiveWorkout: ActiveWorkout?
    @State private var showingResumeAlert = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 24) {
                Text("Accueil")
                    .font(.title2)
                    .foregroundStyle(.white)

                Button {
                    startSession()
                } label: {
                    Text("Lancer la séance")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .controlSize(.large)
                .padding(.horizontal, 40)
                .disabled(activeProgram == nil)
            }
        }
        .task {
            checkForResumableWorkout()
        }
        .alert("Reprendre la séance en cours ?", isPresented: $showingResumeAlert) {
            Button("Reprendre") { resumeWorkout() }
            Button("Abandonner", role: .destructive) { abandonPendingWorkout() }
            Button("Annuler", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showingRunner) {
            if let workoutState {
                WorkoutRunnerView(state: workoutState)
            }
        }
    }

    private var activeProgram: Program? {
        programs.first { $0.isActive }
    }

    private func checkForResumableWorkout() {
        guard let workout = WorkoutState.pendingActiveWorkout(modelContext: modelContext) else { return }
        pendingActiveWorkout = workout
        showingResumeAlert = true
    }

    private func resumeWorkout() {
        guard let workout = pendingActiveWorkout,
              let state = WorkoutState.resume(
                from: workout,
                modelContext: modelContext,
                catalogStore: catalogStore,
                restTimer: restTimer
              ) else { return }
        workoutState = state
        showingRunner = true
    }

    private func abandonPendingWorkout() {
        guard let workout = pendingActiveWorkout else { return }
        modelContext.delete(workout)
        try? modelContext.save()
    }

    private func startSession() {
        guard let program = activeProgram,
              let session = program.sessions.sorted(by: { $0.orderIndex < $1.orderIndex }).first else { return }
        workoutState = WorkoutState(
            programSession: session,
            modelContext: modelContext,
            catalogStore: catalogStore,
            restTimer: restTimer
        )
        showingRunner = true
    }
}

#Preview {
    RootTabView()
        .environment(CatalogStore())
        .modelContainer(for: CustomExercise.self, inMemory: true)
        .preferredColorScheme(.dark)
}
