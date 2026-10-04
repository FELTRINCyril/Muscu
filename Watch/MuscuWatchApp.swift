import HealthKit
import SwiftUI
import WatchKit

@main
struct MuscuWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var delegate
    @State private var connectivity = WatchConnectivityService()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(connectivity)
                .environment(WatchHealthSession.shared)
        }
    }
}

/// Lancement de la montre par l'iPhone dans une séance
/// (`HKHealthStore.startWatchApp`, possible grâce au mode d'arrière-plan
/// « workout-processing »), et reprise d'une séance Santé restée ouverte.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        Task { @MainActor in await WatchHealthSession.shared.recover() }
    }

    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { @MainActor in await WatchHealthSession.shared.startLaunchedByPhone() }
    }
}
