import Foundation

/// Liens directs vers l'application (widgets, Live Activity).
///
/// Un lien ne fait QUE naviguer : il peut venir de n'importe ou (une autre
/// application peut ouvrir `muscu://`), il ne doit donc jamais ecrire quoi
/// que ce soit sans que l'utilisateur le confirme dans l'application.
/// Refaire une seance passe par une confirmation, demarrer la prochaine
/// seance par l'ecran de preparation, exactement comme depuis l'accueil.
enum MuscuDeepLink: Equatable, Sendable {
    /// Ouvre la seance en cours.
    case resumeWorkout
    /// Prepare la prochaine seance du programme actif.
    case startNextSession
    /// Propose de refaire une seance de l'historique.
    case replaySession(UUID)

    static let scheme = "muscu"

    private enum Host {
        static let workout = "workout"
        static let startNext = "start-next"
        static let replay = "replay"
    }

    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .resumeWorkout:
            components.host = Host.workout
        case .startNextSession:
            components.host = Host.startNext
        case .replaySession(let id):
            components.host = Host.replay
            components.queryItems = [URLQueryItem(name: "session", value: id.uuidString)]
        }
        // Les composants ci-dessus sont tous valides : l'URL existe toujours.
        return components.url ?? URL(fileURLWithPath: "/")
    }

    /// Lien reconnu, ou `nil` pour tout ce qui n'est pas exactement l'un des
    /// trois liens ci-dessus (schema, hote ou identifiant inconnus).
    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        switch components.host?.lowercased() {
        case Host.workout:
            self = .resumeWorkout
        case Host.startNext:
            self = .startNextSession
        case Host.replay:
            guard let value = components.queryItems?.first(where: { $0.name == "session" })?.value,
                  let id = UUID(uuidString: value) else { return nil }
            self = .replaySession(id)
        default:
            return nil
        }
    }
}
