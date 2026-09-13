import Foundation
import SwiftData
import MuscuEngine

/// Normalisations appliquees APRES l'ouverture du store, une fois la
/// migration de schema effectuee. Volontairement separe de
/// `MuscuMigrationPlan` : une normalisation qui echoue ne doit jamais
/// empecher l'ouverture du store ni faire perdre de donnees.
///
/// Toutes les etapes sont idempotentes : les relancer a chaque demarrage ne
/// cree jamais de doublon.
@MainActor
enum SchemaUpgrade {
    /// Cle de `UserDefaults` memorisant la derniere version normalisee, pour
    /// eviter de rebalayer tout le store a chaque lancement.
    private static let lastUpgradedVersionKey = "schemaUpgrade.lastVersion"
    static let currentVersion = 2

    static func run(context: ModelContext, force: Bool = false) throws {
        let defaults = UserDefaults.standard
        let last = defaults.integer(forKey: lastUpgradedVersionKey)
        guard force || last < currentVersion else { return }

        try normalizeSyncMetadata(context: context)
        try backfillPersonalBests(context: context)

        try context.save()
        defaults.set(currentVersion, forKey: lastUpgradedVersionKey)
    }

    /// Une migration legere attribue la valeur par defaut (la date du jour)
    /// aux nouveaux champs `updatedAt`. Pour une donnee qui n'a jamais ete
    /// modifiee depuis, cette date est trompeuse lors d'une fusion : on la
    /// ramene a la date de creation connue.
    private static func normalizeSyncMetadata(context: ModelContext) throws {
        for program in try context.fetch(FetchDescriptor<Program>()) where program.updatedAt < program.createdAt {
            program.updatedAt = program.createdAt
        }
        for session in try context.fetch(FetchDescriptor<CompletedSession>()) {
            if session.createdAt > session.date { session.createdAt = session.date }
            if session.updatedAt < session.createdAt { session.updatedAt = session.createdAt }
        }
        for record in try context.fetch(FetchDescriptor<ExerciseRecord>()) where record.createdAt > record.updatedAt {
            record.createdAt = record.updatedAt
        }
    }

    /// Reprend les `ExerciseRecord` historiques sous forme de `PersonalBest`
    /// types, sans supprimer les originaux (qui restent la reference du
    /// pilotage %1RM et des exports v1/v2).
    private static func backfillPersonalBests(context: ModelContext) throws {
        let existing = try context.fetch(FetchDescriptor<PersonalBest>())
        var byKey = Dictionary(existing.map { ($0.identityKey, $0) }, uniquingKeysWith: { first, _ in first })

        for record in try context.fetch(FetchDescriptor<ExerciseRecord>()) {
            if let oneRepMax = record.oneRepMax, oneRepMax > 0 {
                upsert(
                    &byKey,
                    context: context,
                    exerciseId: record.exerciseId,
                    displayName: record.displayName,
                    kind: .estimatedOneRepMax,
                    value: oneRepMax,
                    achievedAt: record.updatedAt
                )
            }
            if let maxReps = record.maxReps, maxReps > 0 {
                upsert(
                    &byKey,
                    context: context,
                    exerciseId: record.exerciseId,
                    displayName: record.displayName,
                    kind: .maxReps,
                    value: Double(maxReps),
                    achievedAt: record.updatedAt
                )
            }
        }
    }

    private static func upsert(
        _ byKey: inout [String: PersonalBest],
        context: ModelContext,
        exerciseId: String,
        displayName: String,
        kind: PersonalBestKind,
        value: Double,
        achievedAt: Date
    ) {
        let key = PersonalBest.identityKey(exerciseId: exerciseId, kind: kind)
        if let existing = byKey[key] {
            guard existing.isImprovement(by: value) else { return }
            existing.value = value
            existing.achievedAt = achievedAt
            existing.updatedAt = .now
            return
        }
        let best = PersonalBest(
            exerciseId: exerciseId,
            displayName: displayName,
            kindRaw: kind.rawValue,
            value: value,
            achievedAt: achievedAt
        )
        context.insert(best)
        byKey[key] = best
    }
}
