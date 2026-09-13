import Foundation
import SwiftData

extension Notification.Name {
    static let persistenceDidFail = Notification.Name("Muscu.persistenceDidFail")
}

/// Point unique de sauvegarde pour ne jamais perdre silencieusement une
/// erreur SwiftData. Les vues recoivent une alerte globale via RootTabView.
@MainActor
enum PersistenceSupport {
    @discardableResult
    static func save(_ context: ModelContext, action: String) -> Bool {
        do {
            try context.save()
            return true
        } catch {
            context.rollback()
            NotificationCenter.default.post(
                name: .persistenceDidFail,
                object: nil,
                userInfo: [
                    "action": action,
                    "message": error.localizedDescription,
                ]
            )
            return false
        }
    }

    static func report(_ error: Error, action: String) {
        NotificationCenter.default.post(
            name: .persistenceDidFail,
            object: nil,
            userInfo: [
                "action": action,
                "message": error.localizedDescription,
            ]
        )
    }
}
