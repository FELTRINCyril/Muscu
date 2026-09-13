import SwiftUI
import SwiftData

// Squelette de navigation principal : 5 onglets. La selection est portee ici
// (et non dans chaque vue) car l'etat vide de l'Accueil doit pouvoir rediriger
// vers l'onglet Programmes.
struct RootTabView: View {
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

            SettingsView()
                .tabItem {
                    Label("Réglages", systemImage: "gearshape.fill")
                }
                .tag(4)
        }
        .tint(Theme.accent)
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
