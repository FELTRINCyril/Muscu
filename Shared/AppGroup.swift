import Foundation

/// Conteneur partage entre l'application, ses widgets et l'application Watch.
///
/// Rien d'intime n'y transite : uniquement l'instantane que les widgets
/// affichent deja a l'ecran verrouille. L'historique, les mesures et les
/// photos restent dans le conteneur prive de l'application.
enum AppGroup {
    static let identifier = "group.com.cyril.Muscu"

    /// Dossier partage, ou `nil` quand le groupe n'est pas disponible —
    /// l'appelant doit alors degrader proprement, jamais planter.
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    static func fileURL(named name: String) -> URL? {
        containerURL?.appendingPathComponent(name, isDirectory: false)
    }
}
