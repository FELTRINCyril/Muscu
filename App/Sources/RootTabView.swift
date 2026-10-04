import SwiftUI
import SwiftData
import MuscuEngine

// Squelette de navigation principal : 5 destinations. La selection est portee
// ici (et non dans chaque vue) car l'etat vide de l'Accueil doit pouvoir
// rediriger vers l'onglet Programmes.
//
// Navigation ADAPTATIVE : onglets en largeur compacte (iPhone), barre
// laterale en largeur regulière (iPad, Mac Catalyst). Les deux presentations
// affichent exactement les memes ecrans : aucune regle metier n'est dupliquee
// par plateforme.
struct RootTabView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// Profil lu par requete : changer d'unite redessine toute l'application.
    @Query(filter: #Predicate<AthleteProfile> { $0.deletedAt == nil }, sort: \AthleteProfile.createdAt)
    private var profiles: [AthleteProfile]

    private var massUnit: MassUnit { profiles.first?.massUnit ?? .kilograms }

    @State private var selectedTab = 0
    @State private var appIssue: AppIssue?

    private struct AppIssue: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        /// Propose d'exporter une copie de la base d'origine. Reserve aux
        /// erreurs d'ouverture du store : ailleurs, la base est lisible.
        var offersStoreRecovery: Bool = false
    }

    @State private var recoveryDocument: RecoveryStoreDocument?
    @State private var isExportingRecovery = false
    @State private var recoveryFilename = "muscu-base-de-secours"

    /// Chrono lance par un raccourci Siri, hors seance.
    @State private var standaloneTimer: StandaloneRestTimer?

    /// `RestTimer` est une classe d'etat, pas une valeur identifiable :
    /// cette enveloppe donne a la presentation une identite stable.
    private struct StandaloneRestTimer: Identifiable {
        let id = UUID()
        let timer: RestTimer
    }

    init(startupError: String? = nil) {
        self.startupError = startupError
        if let startupError {
            _appIssue = State(initialValue: AppIssue(
                title: "Base locale indisponible",
                message: "Muscu utilise temporairement une base vide sans toucher aux données présentes sur l’appareil. Vous pouvez exporter une copie de secours de la base d’origine avant toute autre action.\n\nDétail : \(startupError)",
                offersStoreRecovery: StoreRecovery.storeExists
            ))
        }
    }

    private let startupError: String?

    /// Les cinq destinations, definies une seule fois et partagees par les
    /// deux presentations.
    enum Destination: Int, CaseIterable, Identifiable {
        case home, programs, exercises, progress, settings

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .home: return String(localized: "Accueil")
            case .programs: return String(localized: "Programmes")
            case .exercises: return String(localized: "Exercices")
            case .progress: return String(localized: "Progression")
            case .settings: return String(localized: "Réglages")
            }
        }

        var systemImage: String {
            switch self {
            case .home: return "house.fill"
            case .programs: return "list.bullet.rectangle"
            case .exercises: return "dumbbell.fill"
            case .progress: return "chart.line.uptrend.xyaxis"
            case .settings: return "gearshape.fill"
            }
        }

        /// Raccourci clavier, utile sur iPad et Mac.
        var keyboardShortcut: KeyEquivalent {
            switch self {
            case .home: return "1"
            case .programs: return "2"
            case .exercises: return "3"
            case .progress: return "4"
            case .settings: return "5"
            }
        }
    }

    var body: some View {
        adaptiveNavigation
            .tint(Theme.accent)
            // Unite d'affichage des charges : injectee pour les vues, et
            // recopiee pour le code qui formate hors d'une vue.
            .environment(\.massUnit, massUnit)
            .onChange(of: massUnit, initial: true) { _, unit in
                WeightFormatter.storePreferredUnit(unit)
            }
            .onAppear(perform: applyIntentRequests)
            // Un raccourci peut arriver alors que l'application est deja
            // ouverte : on reagit aussi au depot d'une demande.
            .onChange(of: IntentRouter.shared.pending) { _, _ in applyIntentRequests() }
            .onChange(of: RestTimerLauncher.shared.pendingSeconds) { _, _ in applyIntentRequests() }
            .fullScreenCover(item: $standaloneTimer) { entry in
                RestTimerView(timer: entry.timer)
            }
            .onReceive(NotificationCenter.default.publisher(for: .persistenceDidFail)) { notification in
            let action = notification.userInfo?["action"] as? String ?? "Enregistrement"
            let details = notification.userInfo?["message"] as? String ?? "Erreur inconnue"
            appIssue = AppIssue(
                title: "Données non enregistrées",
                message: "\(action) a échoué. Aucune confirmation ne doit être considérée comme définitive.\n\n\(details)"
            )
            }
            .onReceive(NotificationCenter.default.publisher(for: .restNotificationsDenied)) { _ in
            appIssue = AppIssue(
                title: "Notifications désactivées",
                message: "Le chrono fonctionne dans l’app, mais aucune alerte de fin de repos ne sera affichée lorsque Muscu est en arrière-plan. Vous pouvez les autoriser dans Réglages iOS."
            )
            }
            .alert(item: $appIssue) { issue in
            if issue.offersStoreRecovery {
                return Alert(
                    title: Text(issue.title),
                    message: Text(issue.message),
                    primaryButton: .default(Text("Exporter une copie de secours")) {
                        prepareRecoveryExport()
                    },
                    secondaryButton: .cancel(Text("Plus tard"))
                )
            }
            return Alert(
                title: Text(issue.title),
                message: Text(issue.message),
                dismissButton: .default(Text("OK"))
            )
            }
            .fileExporter(
            isPresented: $isExportingRecovery,
            document: recoveryDocument,
            contentType: .data,
            defaultFilename: recoveryFilename
            ) { _ in }
    }


    // MARK: - Présentations

    /// Onglets en compact, barre latérale en régulier.
    @ViewBuilder
    private var adaptiveNavigation: some View {
        if horizontalSizeClass == .compact {
            tabNavigation
        } else {
            sidebarNavigation
        }
    }

    private var tabNavigation: some View {
        TabView(selection: $selectedTab) {
            ForEach(Destination.allCases) { destination in
                screen(for: destination)
                    .tabItem { Label(destination.title, systemImage: destination.systemImage) }
                    .tag(destination.rawValue)
            }
        }
    }

    /// Barre latérale : même contenu, navigation au clavier et pointeur.
    private var sidebarNavigation: some View {
        NavigationSplitView {
            List(Destination.allCases, selection: sidebarSelection) { destination in
                NavigationLink(value: destination) {
                    Label(destination.title, systemImage: destination.systemImage)
                }
                .keyboardShortcut(destination.keyboardShortcut, modifiers: .command)
            }
            .navigationTitle("Muscu")
            .listStyle(.sidebar)
        } detail: {
            screen(for: Destination(rawValue: selectedTab) ?? .home)
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var sidebarSelection: Binding<Destination?> {
        Binding(
            get: { Destination(rawValue: selectedTab) },
            set: { if let value = $0 { selectedTab = value.rawValue } }
        )
    }

    @ViewBuilder
    private func screen(for destination: Destination) -> some View {
        switch destination {
        case .home: HomeView(selectedTab: $selectedTab)
        case .programs: ProgramsView()
        case .exercises: ExercisesView()
        case .progress: ProgressTabView()
        case .settings: SettingsView()
        }
    }

    /// Applique les demandes deposees par les raccourcis Siri. Chaque
    /// demande est consommee une fois : revenir en arriere ne relance donc
    /// pas la meme navigation en boucle.
    private func applyIntentRequests() {
        if let destination = IntentRouter.shared.pending {
            switch destination {
            case .home:
                selectedTab = Destination.home.rawValue
                _ = IntentRouter.shared.consume()
            case .program:
                // Consommee par `ProgramsView`, qui seule connait sa pile de
                // navigation. On se contente d'ouvrir l'onglet.
                selectedTab = Destination.programs.rawValue
            case .exercise:
                // Consommee par `ExercisesView`, qui porte sa pile de
                // navigation. On se contente d'ouvrir l'onglet.
                selectedTab = Destination.exercises.rawValue
            case .weeklySummary:
                selectedTab = Destination.progress.rawValue
                _ = IntentRouter.shared.consume()
            }
        }

        if let seconds = RestTimerLauncher.shared.consume() {
            let timer = RestTimer()
            timer.onFinished = { standaloneTimer = nil }
            timer.start(seconds: seconds)
            standaloneTimer = StandaloneRestTimer(timer: timer)
        }
    }

    /// Copie la base d'origine dans un dossier temporaire, puis propose de
    /// l'enregistrer. Le fichier d'origine reste intact sur l'appareil.
    private func prepareRecoveryExport() {
        do {
            let copies = try StoreRecovery.makeRecoveryCopy()
            // Le fichier principal porte l'essentiel des donnees ; les
            // journaux SQLite restent dans le dossier temporaire pour un
            // diagnostic ulterieur.
            guard let main = copies.first, let data = try? Data(contentsOf: main) else {
                appIssue = AppIssue(
                    title: "Copie impossible",
                    message: "La base d’origine n’a pas pu être lue. Elle reste intacte sur l’appareil."
                )
                return
            }
            recoveryFilename = main.deletingPathExtension().lastPathComponent
            recoveryDocument = RecoveryStoreDocument(data: data)
            isExportingRecovery = true
        } catch {
            appIssue = AppIssue(
                title: "Copie impossible",
                message: "\(error.localizedDescription) La base d’origine reste intacte sur l’appareil."
            )
        }
    }
}

#Preview {
    RootTabView()
        .environment(CatalogStore())
        .modelContainer(for: CustomExercise.self, inMemory: true)
        .preferredColorScheme(.dark)
}
