import Foundation
// ActivityKit se compile sur Mac Catalyst mais chacun de ses symboles y est
// marque indisponible : seul `targetEnvironment` distingue les deux cas.
#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit
#endif

/// Contenu d'une Live Activity de seance en cours.
///
/// Volontairement pauvre : le nom de l'exercice, la position dans la seance
/// et la fin du repos. Une Live Activity s'affiche sur l'ecran verrouille :
/// tout ce qui y figure est visible sans deverrouiller le telephone.
struct WorkoutActivityState: Codable, Hashable, Sendable {
    var exerciseName: String
    var setNumber: Int
    var totalSets: Int
    /// Fin du repos en cours. `nil` = pas de repos en cours.
    var restEndsAt: Date?
    var completedSets: Int

    init(
        exerciseName: String,
        setNumber: Int,
        totalSets: Int,
        restEndsAt: Date? = nil,
        completedSets: Int = 0
    ) {
        self.exerciseName = exerciseName
        self.setNumber = setNumber
        self.totalSets = totalSets
        self.restEndsAt = restEndsAt
        self.completedSets = completedSets
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
