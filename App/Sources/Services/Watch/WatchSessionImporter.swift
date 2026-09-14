import Foundation
import SwiftData
import MuscuEngine

/// Reçoit une séance faite à la montre et l'ajoute à l'historique.
///
/// Garantie du jalon : l'identifiant vient de la montre et ne change jamais.
/// Il devient l'identifiant de la `CompletedSession`, qui est unique dans le
/// modèle — rejouer un transfert ne peut donc pas créer de doublon, même
/// après une coupure, une relance ou une réinstallation.
@MainActor
enum WatchSessionImporter {
    static let sourceName = "Apple Watch"

    @discardableResult
    static func importSession(
        _ payload: WatchSessionPayload,
        in context: ModelContext,
        now: Date = .now
    ) -> WatchTransferDecision {
        let existing = Set(((try? context.fetch(FetchDescriptor<CompletedSession>())) ?? []).map(\.id))

        let decision = WatchTransferReconciler.decide(
            incomingId: payload.id,
            version: payload.version,
            setCount: payload.sets.count,
            currentVersion: WatchSessionPayload.currentVersion,
            existingSessionIds: existing
        )
        guard decision.writesAnything else { return decision }

        let session = CompletedSession(
            id: payload.id,
            date: payload.startedAt,
            programName: sourceName,
            sessionName: payload.sessionName,
            durationSeconds: payload.durationSeconds,
            importSource: sourceName,
            createdAt: now,
            updatedAt: now
        )
        context.insert(session)

        var orderByExercise: [String: Int] = [:]
        for (sequence, set) in payload.sets.enumerated() {
            let orderIndex = orderByExercise[set.exerciseName] ?? orderByExercise.count
            orderByExercise[set.exerciseName] = orderIndex

            let completedSet = CompletedSet(
                exerciseId: "",
                displayName: set.exerciseName,
                orderIndex: orderIndex,
                setIndex: set.setIndex,
                weight: set.weightKilograms,
                reps: set.reps,
                loadTypeRaw: ExerciseLoadType.external.rawValue,
                roleRaw: SetRole.working.rawValue,
                sequenceIndex: sequence,
                createdAt: now,
                updatedAt: now
            )
            completedSet.session = session
            session.sets.append(completedSet)
            context.insert(completedSet)
        }

        guard PersistenceSupport.save(context, action: "Séance reçue de la montre") else {
            // L'enregistrement a echoue : on ne pretend pas avoir accepte.
            return .empty
        }
        return decision
    }
}
