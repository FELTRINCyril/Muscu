import Foundation
import SwiftData
import MuscuEngine

/// Marque les entités synchronisables modifiées localement, pour que la file
/// d'attente parte réellement à la prochaine synchronisation.
///
/// Le défaut corrigé : `SyncService.enqueue` existait, était testé, et
/// **n'était appelé par aucun code applicatif**. Ni la fin d'une séance, ni
/// l'édition d'un programme, ni une mesure ne remplissaient la file. Le jour
/// où un conteneur CloudKit sera branché, seule une réinscription complète
/// aurait fait partir quoi que ce soit.
///
/// Le branchement se fait au **point unique de sauvegarde**
/// (`PersistenceSupport.save`) plutôt qu'à chaque appelant : SwiftData sait
/// dire ce qui a changé, et un point unique ne peut pas être oublié.
///
/// Tant que la synchronisation est éteinte — c'est-à-dire toujours,
/// aujourd'hui — ce code ne fait **rien** : pas de lecture, pas d'écriture.
@MainActor
enum SyncOutboxFeeder {
    /// Miroir léger de `SyncState.isEnabled`.
    ///
    /// Lire l'état persisté à chaque sauvegarde coûterait une requête sur le
    /// chemin le plus fréquent de l'application (chaque série validée). Ce
    /// drapeau est écrit en même temps que l'état, et sert de garde d'entrée.
    private static let enabledKey = "sync.enabled"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// Évite qu'une sauvegarde déclenchée par la mise à jour de la file ne
    /// relance le mécanisme sur elle-même.
    private static var isFeeding = false

    struct Change: Equatable {
        let kind: SyncEntityKind
        let identifier: UUID
    }

    /// Ce qui est sur le point d'être écrit. À appeler **avant** `save()` :
    /// après, SwiftData a vidé ses listes de changements.
    static func pendingChanges(in context: ModelContext) -> [Change] {
        guard isEnabled, !isFeeding else { return [] }

        var changes: [Change] = []
        func collect(_ models: [any PersistentModel]) {
            for model in models {
                guard let tracked = model as? any SyncTracked else { continue }
                changes.append(Change(kind: type(of: tracked).syncKind, identifier: tracked.syncIdentifier))
            }
        }
        collect(context.insertedModelsArray)
        collect(context.changedModelsArray)
        // Les suppressions sont logiques (`deletedAt`) et passent donc par
        // `changedModelsArray`. Une suppression physique — la purge des
        // tombstones — n'a rien à propager : l'autre appareil a déjà reçu la
        // suppression logique, et la purge est une décision locale.
        return changes
    }

    /// Inscrit les changements dans la file. À appeler **après** un `save()`
    /// réussi : une modification qui n'a pas été écrite n'a rien à propager.
    static func record(_ changes: [Change], in context: ModelContext) {
        guard isEnabled, !isFeeding, !changes.isEmpty else { return }
        isFeeding = true
        defer { isFeeding = false }

        let state = SyncService.state(in: context)
        var outbox = state.outbox
        for change in changes {
            outbox.enqueue(kind: change.kind, identifier: change.identifier, updatedAt: .now)
        }
        state.outbox = outbox
        state.updatedAt = .now
        // Sauvegarde directe : repasser par `PersistenceSupport` rentrerait
        // dans ce même code.
        try? context.save()
    }
}

/// Entités qui voyagent entre appareils : le lien entre un modèle SwiftData
/// et sa nature côté synchronisation.
///
/// `SyncIdentifiable` fournit déjà l'identifiant stable ; il ne manquait que
/// la nature.
protocol SyncTracked: SyncIdentifiable {
    static var syncKind: SyncEntityKind { get }
}

extension Program: SyncTracked { static var syncKind: SyncEntityKind { .program } }
extension CompletedSession: SyncTracked { static var syncKind: SyncEntityKind { .completedSession } }
extension ActiveWorkout: SyncTracked { static var syncKind: SyncEntityKind { .activeWorkout } }
extension ExerciseRecord: SyncTracked { static var syncKind: SyncEntityKind { .exerciseRecord } }
extension PersonalBest: SyncTracked { static var syncKind: SyncEntityKind { .personalBest } }
extension CustomExercise: SyncTracked { static var syncKind: SyncEntityKind { .customExercise } }
extension AthleteProfile: SyncTracked { static var syncKind: SyncEntityKind { .athleteProfile } }
extension BodyMeasurement: SyncTracked { static var syncKind: SyncEntityKind { .bodyMeasurement } }
extension ReadinessEntry: SyncTracked { static var syncKind: SyncEntityKind { .readinessEntry } }
extension HealthWorkoutLink: SyncTracked { static var syncKind: SyncEntityKind { .healthWorkoutLink } }
extension TrainingPlan: SyncTracked { static var syncKind: SyncEntityKind { .trainingPlan } }
extension TrainingGoal: SyncTracked { static var syncKind: SyncEntityKind { .trainingGoal } }
extension AdaptationEntry: SyncTracked { static var syncKind: SyncEntityKind { .adaptationEntry } }
