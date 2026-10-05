import Foundation

/// Ce qu'affiche la complication de la montre : la séance en cours
/// (exercice, série, repos) ou, à défaut, la prochaine séance.
///
/// Écrit par l'application de la montre dans son groupe d'applications, lu
/// par l'extension de widgets de la montre (même règle que la décision
/// 0009 : un widget lit un instantané, jamais la source). Rien d'autre n'y
/// figure : ni charge, ni historique.
struct WatchComplicationState: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version: Int
    /// Séance en cours sur l'iPhone, suivie en miroir.
    var isWorkoutRunning: Bool
    var title: String?
    /// « Série 2/4 », ou `nil`.
    var detail: String?
    /// Fin du repos en cours, pour un décompte tenu par le système.
    var restEndsAt: Date?
    /// Séries de travail déjà faites dans la séance en cours.
    var completedSets: Int

    init(
        version: Int = WatchComplicationState.currentVersion,
        isWorkoutRunning: Bool = false,
        title: String? = nil,
        detail: String? = nil,
        restEndsAt: Date? = nil,
        completedSets: Int = 0
    ) {
        self.version = version
        self.isWorkoutRunning = isWorkoutRunning
        self.title = title
        self.detail = detail
        self.restEndsAt = restEndsAt
        self.completedSets = completedSets
    }

    static let empty = WatchComplicationState()

    /// Construit l'état depuis ce que la montre a reçu de l'iPhone. Un repos
    /// déjà terminé n'est pas affiché : le dépassement se lit dans l'app.
    static func make(
        mirror: WatchMirrorState?,
        nextSessionName: String?,
        now: Date = .now
    ) -> WatchComplicationState {
        if let mirror, mirror.hasWorkout {
            let activity = mirror.activity
            let rest = activity?.restEndsAt.flatMap { $0 > now ? $0 : nil }
            var detail: String?
            if mirror.phase == .running, let activity, activity.totalSets > 0 {
                detail = String(localized: "Série \(activity.setNumber)/\(activity.totalSets)")
            }
            return WatchComplicationState(
                isWorkoutRunning: true,
                title: mirror.phase == .warmup ? mirror.sessionName : (activity?.exerciseName ?? mirror.sessionName),
                detail: detail,
                restEndsAt: rest,
                completedSets: activity?.completedSets ?? 0
            )
        }
        return WatchComplicationState(title: nextSessionName)
    }
}

/// Lecture et écriture de l'état de la complication dans le groupe
/// d'applications de la montre.
enum WatchComplicationStore {
    static let fileName = "watch-complication.json"

    /// `true` si l'état a changé (et a été écrit) : la complication n'est
    /// rechargée que dans ce cas, pour ménager le budget du système.
    @discardableResult
    static func write(_ state: WatchComplicationState) -> Bool {
        guard state != read(), let url = AppGroup.fileURL(named: fileName),
              let data = WatchMessageCodec.encode(state) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    static func read() -> WatchComplicationState {
        guard let url = AppGroup.fileURL(named: fileName),
              let state = WatchMessageCodec.decode(WatchComplicationState.self, from: try? Data(contentsOf: url)),
              state.version <= WatchComplicationState.currentVersion else { return .empty }
        return state
    }
}
