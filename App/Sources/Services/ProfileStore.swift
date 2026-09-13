import Foundation
import SwiftData
import MuscuEngine

/// Acces unique au profil de l'athlete. Une seule instance doit exister :
/// ce point d'entree evite que chaque vue refasse sa propre requete et
/// cree un second profil par accident.
@MainActor
enum ProfileStore {
    /// Profil existant, sans rien creer. Retourne `nil` tant que
    /// l'utilisateur n'a rempli aucune information : l'application reste
    /// entierement utilisable sans profil.
    static func currentProfile(in context: ModelContext) -> AthleteProfile? {
        let descriptor = FetchDescriptor<AthleteProfile>(sortBy: [SortDescriptor(\.createdAt)])
        guard let profiles = try? context.fetch(descriptor) else { return nil }
        return profiles.first { $0.deletedAt == nil }
    }

    /// Profil existant ou nouveau profil vierge insere dans le contexte.
    /// L'appelant reste responsable de la sauvegarde (cf. PersistenceSupport).
    @discardableResult
    static func ensureProfile(in context: ModelContext) -> AthleteProfile {
        if let existing = currentProfile(in: context) { return existing }
        let profile = AthleteProfile()
        context.insert(profile)
        return profile
    }

    /// Unite de masse d'affichage. La valeur canonique stockee reste le
    /// kilogramme, quelle que soit cette preference.
    static func massUnit(in context: ModelContext) -> MassUnit {
        currentProfile(in: context)?.massUnit ?? .kilograms
    }

    /// Poids de corps connu le plus recent : mesure datee si elle existe,
    /// sinon valeur de reference du profil. `nil` quand rien n'est connu.
    static func latestBodyweightKilograms(in context: ModelContext) -> Double? {
        var descriptor = FetchDescriptor<BodyMeasurement>(
            predicate: #Predicate { $0.kindRaw == "bodyweight" && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.measuredAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        if let measurement = try? context.fetch(descriptor).first, measurement.value > 0 {
            return measurement.value
        }
        return currentProfile(in: context)?.bodyweightKilograms
    }
}
