import Foundation
import Network

// Etat reseau observable : utilise pour desactiver le bouton video (et tout
// autre point d'entree necessitant internet) hors ligne, cf. spec section 9
// ("bouton video desactive avec message"). NWPathMonitor demarre a l'init et
// publie ses mises a jour sur le thread principal (isOnline est lu par SwiftUI).
@Observable
final class NetworkStatus: @unchecked Sendable {
    private(set) var isOnline: Bool = true

    private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isOnline = path.status == .satisfied
            }
        }
        monitor.start(queue: DispatchQueue(label: "NetworkStatus.monitor"))
    }

    deinit {
        monitor.cancel()
    }
}
