import SwiftUI

@main
struct MuscuWatchApp: App {
    @State private var connectivity = WatchConnectivityService()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(connectivity)
        }
    }
}
