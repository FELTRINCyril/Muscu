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
    /// Fin du repos en cours. `nil` = pas de repos. Une fin passee vaut
    /// « pas de repos » : l'activite n'affiche jamais de depassement.
    var restEndsAt: Date?
    var completedSets: Int
    /// Debut du repos, pour la barre de progression. `nil` si inconnu.
    var restStartedAt: Date?
    /// Serie prevue, exactement ce que « Valider » enregistrera : « 80 kg ×
    /// 8 », « × 12 » sans charge. Pendant un repos, c'est la serie qui suit
    /// le repos. `nil` s'il n'y a rien a valider sans saisie.
    var plannedSetText: String?
    /// Serie suivante : « Série 3/4 », « Rowing · série 1/3 », « Fin de la
    /// séance ». `nil` si rien n'est prevu apres.
    var nextStepText: String?
    /// La serie courante peut etre validee d'un tap avec `plannedSetText`.
    /// Faux (serie au temps, format chronometre) : aucun bouton de
    /// validation ; un tap sur le bandeau ouvre l'application.
    var canQuickLog: Bool
    /// Identite de la serie affichee. Le bouton « Valider » la renvoie : une
    /// serie n'est validee que si c'est TOUJOURS celle qui est affichee
    /// (double tap, activite en retard sur l'application).
    var slotKey: String
    /// Echauffement guide : `setNumber` / `totalSets` comptent les paliers
    /// de montee en charge, et « Valider » coche le palier affiche.
    var isWarmup: Bool

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
        slotKey: String = "",
        isWarmup: Bool = false
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
        self.isWarmup = isWarmup
    }

    private enum CodingKeys: String, CodingKey {
        case exerciseName, setNumber, totalSets, restEndsAt, completedSets
        case restStartedAt, plannedSetText, nextStepText, canQuickLog, slotKey, isWarmup
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
        isWarmup = try container.decodeIfPresent(Bool.self, forKey: .isWarmup) ?? false
    }

    /// Etat du repos a l'instant `now`.
    enum RestPhase: Equatable {
        case none
        /// Decompte jusqu'a la fin prevue.
        case counting(endsAt: Date)
    }

    /// Le repos s'arrete a sa fin prevue : il n'y a pas de depassement. Un
    /// rendu fait apres la fin, avant que l'application n'ait pousse la mise
    /// a jour, montre donc deja la serie suivante sans repos.
    func restPhase(at now: Date) -> RestPhase {
        guard let restEndsAt, restEndsAt > now else { return .none }
        return .counting(endsAt: restEndsAt)
    }

    /// Le repos en cours peut etre ajuste de ±15 s.
    func canAdjustRest(at now: Date) -> Bool {
        restPhase(at: now) != .none
    }

    /// Ce que la Live Activity affiche a l'instant `now`.
    struct Controls: Equatable {
        /// Decompte, « −15 s », « +15 s », « Passer ».
        var showsRest: Bool
        /// « Valider » : la serie affichee (celle qui suit le repos pendant
        /// un repos), avec les valeurs de `plannedSetText`.
        var showsValidate: Bool
        /// « Ensuite : … », hors repos (le repos occupe la ligne).
        var showsNextStep: Bool
    }

    /// Jamais de bouton « Ouvrir » : un tap sur le bandeau ouvre deja
    /// l'application. « Valider » est le meme pendant et hors repos : la fin
    /// du repos ne change que la ligne du repos.
    func controls(at now: Date) -> Controls {
        let resting = restPhase(at: now) != .none
        return Controls(
            showsRest: resting,
            showsValidate: canQuickLog && !slotKey.isEmpty,
            showsNextStep: !resting && nextStepText != nil
        )
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
