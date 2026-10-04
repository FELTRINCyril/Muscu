import Foundation
// ActivityKit se compile sur Mac Catalyst mais chacun de ses symboles y est
// marque indisponible : seul `targetEnvironment` distingue les deux cas.
#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit
#endif

/// Contenu d'une Live Activity de seance en cours.
///
/// Ce qui figure ici est visible sur l'ecran verrouille SANS deverrouiller
/// le telephone : l'exercice, la position dans la seance, la serie prevue
/// (charge x repetitions, exactement ce que l'ecran de saisie propose), la
/// serie suivante et le repos. Jamais un poids de corps, une note ou un
/// commentaire. Les textes arrivent deja mis en forme dans l'unite du
/// profil : l'extension n'a ni le moteur ni la base.
///
/// Tous les champs ajoutes apres la phase 7 sont FACULTATIFS au decodage :
/// une activite demarree par une version precedente reste lisible.
struct WorkoutActivityState: Codable, Hashable, Sendable {
    var exerciseName: String
    var setNumber: Int
    var totalSets: Int
    /// Fin du repos en cours, conservee pendant le depassement (« +0:12 »).
    /// `nil` = pas de repos.
    var restEndsAt: Date?
    var completedSets: Int
    /// Debut du repos, pour la barre de progression. `nil` si inconnu.
    var restStartedAt: Date?
    /// Serie prevue : « 80 kg × 8 », « × 12 » au poids du corps. `nil` si
    /// la charge ou les repetitions ne sont pas connues.
    var plannedSetText: String?
    /// Serie suivante : « Série 3/4 », « Rowing · série 1/3 », « Fin de la
    /// séance ». `nil` si rien n'est prevu apres.
    var nextStepText: String?
    /// La serie courante peut etre validee d'un tap avec `plannedSetText`.
    /// Faux : le bouton devient « Ouvrir ».
    var canQuickLog: Bool
    /// Identite de la serie affichee. Le bouton « Valider » la renvoie : une
    /// serie n'est validee que si c'est TOUJOURS celle qui est affichee
    /// (double tap, activite en retard sur l'application).
    var slotKey: String

    init(
        exerciseName: String,
        setNumber: Int,
        totalSets: Int,
        restEndsAt: Date? = nil,
        completedSets: Int = 0,
        restStartedAt: Date? = nil,
        plannedSetText: String? = nil,
        nextStepText: String? = nil,
        canQuickLog: Bool = false,
        slotKey: String = ""
    ) {
        self.exerciseName = exerciseName
        self.setNumber = setNumber
        self.totalSets = totalSets
        self.restEndsAt = restEndsAt
        self.completedSets = completedSets
        self.restStartedAt = restStartedAt
        self.plannedSetText = plannedSetText
        self.nextStepText = nextStepText
        self.canQuickLog = canQuickLog
        self.slotKey = slotKey
    }

    private enum CodingKeys: String, CodingKey {
        case exerciseName, setNumber, totalSets, restEndsAt, completedSets
        case restStartedAt, plannedSetText, nextStepText, canQuickLog, slotKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        exerciseName = try container.decode(String.self, forKey: .exerciseName)
        setNumber = try container.decode(Int.self, forKey: .setNumber)
        totalSets = try container.decode(Int.self, forKey: .totalSets)
        restEndsAt = try container.decodeIfPresent(Date.self, forKey: .restEndsAt)
        completedSets = try container.decodeIfPresent(Int.self, forKey: .completedSets) ?? 0
        restStartedAt = try container.decodeIfPresent(Date.self, forKey: .restStartedAt)
        plannedSetText = try container.decodeIfPresent(String.self, forKey: .plannedSetText)
        nextStepText = try container.decodeIfPresent(String.self, forKey: .nextStepText)
        canQuickLog = try container.decodeIfPresent(Bool.self, forKey: .canQuickLog) ?? false
        slotKey = try container.decodeIfPresent(String.self, forKey: .slotKey) ?? ""
    }

    /// Au-dela, un depassement n'a plus de sens : meme borne que le chrono
    /// de l'application (`RestCountdown.maximumOvertimeSeconds`).
    static let maximumOvertimeSeconds: TimeInterval = 3_600

    /// Etat du repos a l'instant `now`.
    enum RestPhase: Equatable {
        case none
        /// Decompte jusqu'a la fin prevue.
        case counting(endsAt: Date)
        /// Repos termine : depassement compte depuis la fin prevue.
        case overtime(since: Date)
    }

    func restPhase(at now: Date) -> RestPhase {
        guard let restEndsAt else { return .none }
        if restEndsAt > now { return .counting(endsAt: restEndsAt) }
        guard now.timeIntervalSince(restEndsAt) <= Self.maximumOvertimeSeconds else { return .none }
        return .overtime(since: restEndsAt)
    }

    /// Le repos en cours peut etre prolonge de 30 s (pas pendant un
    /// depassement : comme dans l'application).
    func canExtendRest(at now: Date) -> Bool {
        if case .counting = restPhase(at: now) { return true }
        return false
    }
}

#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
struct WorkoutActivityAttributes: ActivityAttributes {
    typealias ContentState = WorkoutActivityState

    /// Nom de la seance, fixe pour toute la duree de l'activite.
    var sessionName: String
    var startedAt: Date
}
#endif
