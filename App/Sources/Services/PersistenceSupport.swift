import Foundation
import SwiftData
import MuscuEngine

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
            // Toute sauvegarde passe par ici : c'est le seul endroit ou
            // journaliser un echec de stockage sans en manquer un.
            DiagnosticsCenter.record(
                .store,
                .failure,
                code: "store.save.failed",
                detail: "\(action) — \(error.localizedDescription)"
            )
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
        DiagnosticsCenter.record(
            .store,
            .failure,
            code: "store.operation.failed",
            detail: "\(action) — \(error.localizedDescription)"
        )
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
