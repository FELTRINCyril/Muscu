import Foundation
import SwiftData
import MuscuEngine

// Entree et sortie d'une seance, partagees par l'interface et par ce qui
// agit hors d'elle (Siri, Raccourcis, liens des widgets). Un seul chemin :
// terminer depuis Siri fait exactement ce que fait le bouton « Terminer »
// du recapitulatif, refaire depuis un widget exactement ce que fait
// « Refaire » dans l'historique.

extension WorkoutState {
    /// Resultat d'une fin de seance.
    struct Completion {
        let session: CompletedSession
        /// Records de reference battus (1RM saisi, maximum de repetitions) :
        /// jamais appliques sans confirmation, un par un.
        let recordSuggestions: [RecordDetection.RecordSuggestion]
        /// Ecarts de structure avec la seance du programme, pour proposer de
        /// le mettre a jour.
        let structureChanges: [SessionStructureChange]
    }

    /// Termine la seance : historique, widgets, Sante, records types.
    /// `nil` si l'enregistrement a echoue — rien n'est alors modifie.
    ///
    /// - Parameter outsideRunner: la fin vient de Siri ou d'un raccourci ; le
    ///   deroule, s'il est affiche, se ferme.
    func complete(effortRating: Int? = nil, outsideRunner: Bool = false) -> Completion? {
        guard let completedSession = finish(effortRating: effortRating, outsideRunner: outsideRunner) else {
            return nil
        }
        // La structure se compare au deroule FINAL de la seance, toujours en
        // memoire apres la fin ; rien n'est propose si rien n'a change.
        let changes = structureChanges

        // Ecriture dans Sante, si et seulement si l'utilisateur l'a activee.
        // Un echec n'affecte pas la seance : elle est deja enregistree.
        // Une seance Sante en direct est d'abord terminee et reliee : la
        // synchronisation la reconnait alors comme deja ecrite.
        let context = modelContext
        Task {
            await LiveHealthWorkoutController.shared.finishRecording(
                in: context,
                store: AppServices.healthStore
            )
            await HealthSyncService.synchronize(
                in: context,
                store: AppServices.healthStore
            )
        }

        let records = (try? modelContext.fetch(FetchDescriptor<ExerciseRecord>())) ?? []
        // Le poids de corps fige sur la seance prime ; a defaut on retombe
        // sur la derniere mesure connue, sans jamais supposer une valeur.
        let bodyweight = ProfileStore.latestBodyweightKilograms(in: modelContext)
        let suggestions = RecordDetection.check(
            session: completedSession,
            records: records,
            bodyweightKilograms: bodyweight
        )
        // Les records TYPES (charge, tonnage, temps, tours) sont recalcules
        // depuis l'historique et n'ont pas besoin d'etre confirmes un par un :
        // ils decrivent ce qui vient d'etre fait, sans modifier de programme.
        let candidates = PersonalBestUpdater.candidates(for: completedSession, bodyweightKilograms: bodyweight)
        if !PersonalBestUpdater.apply(
            candidates: candidates,
            context: modelContext,
            sourceSessionId: completedSession.id,
            achievedAt: completedSession.date
        ).isEmpty {
            _ = PersistenceSupport.save(modelContext, action: "Enregistrement des records")
        }
        // Les widgets affichent la semaine et la derniere seance (records
        // compris) : ils doivent refleter cette seance immediatement.
        WidgetSnapshotService.refresh(in: modelContext)
        // Sauvegarde automatique (si activee, au plus une par jour) : une
        // seance qui vient d'etre terminee est la donnee la plus precieuse.
        AutoBackupService.runIfDue(context: modelContext)
        return Completion(session: completedSession, recordSuggestions: suggestions, structureChanges: changes)
    }

    /// Seance libre preremplie depuis une seance de l'historique
    /// (« Refaire » / « Refaire à vide »).
    static func replaying(
        _ session: CompletedSession,
        mode: SessionReplay.Mode,
        modelContext: ModelContext,
        catalogStore: CatalogStore,
        restTimer: RestTimer
    ) -> WorkoutState {
        let plan = SessionReplayBuilder.plan(for: session, mode: mode, catalogStore: catalogStore, context: modelContext)
        return WorkoutState(
            freeSessionWith: modelContext,
            catalogStore: catalogStore,
            restTimer: restTimer,
            replaying: plan,
            title: session.sessionName
        )
    }
}
