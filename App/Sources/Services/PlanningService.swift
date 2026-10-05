import Foundation
import SwiftData
import MuscuEngine

/// Traduction entre le planning persiste et le moteur de planification.
///
/// Le moteur ne connait que des `PlannedSlot` ; ce service est le seul
/// endroit qui sait les fabriquer depuis SwiftData et y reappliquer une
/// decision. Deux ecrans ne peuvent donc pas diverger sur ce qu'est une
/// seance « manquee » ou « en conflit ».
@MainActor
enum PlanningService {
    // MARK: - Lecture

    static func scheduledWorkouts(in context: ModelContext) -> [ScheduledWorkout] {
        let descriptor = FetchDescriptor<ScheduledWorkout>(sortBy: [SortDescriptor(\.plannedDate)])
        return (try? context.fetch(descriptor))?.filter { $0.deletedAt == nil } ?? []
    }

    static func schedules(in context: ModelContext) -> [PlanningSchedule] {
        let descriptor = FetchDescriptor<PlanningSchedule>(sortBy: [SortDescriptor(\.createdAt)])
        return (try? context.fetch(descriptor))?.filter { $0.deletedAt == nil } ?? []
    }

    /// Convertit les seances planifiees en creneaux pour le moteur.
    ///
    /// Les muscles principaux viennent du catalogue : sans eux, le moteur ne
    /// signale que les collisions de date, jamais un manque de recuperation
    /// qu'il aurait invente.
    static func slots(
        in context: ModelContext,
        catalog: ExerciseCatalog?
    ) -> [PlannedSlot] {
        let sessionsById = programSessionsById(in: context)
        return scheduledWorkouts(in: context).map { workout in
            PlannedSlot(
                id: workout.id,
                date: workout.plannedDate,
                title: workout.displayName.isEmpty ? "Séance" : workout.displayName,
                primaryMuscles: muscles(for: workout, sessionsById: sessionsById, catalog: catalog),
                isSettled: workout.state.isSettled
            )
        }
    }

    private static func programSessionsById(in context: ModelContext) -> [UUID: ProgramSession] {
        let sessions = (try? context.fetch(FetchDescriptor<ProgramSession>())) ?? []
        return Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private static func muscles(
        for workout: ScheduledWorkout,
        sessionsById: [UUID: ProgramSession],
        catalog: ExerciseCatalog?
    ) -> Set<String> {
        guard let catalog,
              let sessionId = workout.programSessionId,
              let session = sessionsById[sessionId] else { return [] }
        var muscles: Set<String> = []
        for exercise in session.orderedExercises {
            guard let entry = catalog.exercise(id: exercise.exerciseId) else { continue }
            muscles.formUnion(entry.primaryMuscles)
        }
        return muscles
    }

    // MARK: - Récurrence

    /// Materialise une recurrence en seances planifiees.
    ///
    /// IDEMPOTENT : relancer la generation ne cree pas de doublon et ne
    /// touche jamais une seance deja commencee, terminee ou deplacee a la
    /// main. Une seance devenue hors recurrence n'est supprimee que si elle
    /// est encore a l'etat « prevue » et dans le futur.
    @discardableResult
    static func applyRecurrence(
        _ schedule: PlanningSchedule,
        program: Program?,
        in context: ModelContext,
        calendar: Calendar = .current,
        now: Date = .now,
        horizonWeeks: Int = 8
    ) -> (created: Int, removed: Int) {
        guard schedule.isEnabled, schedule.recurrence.isValid else { return (0, 0) }

        let horizon = calendar.date(byAdding: .weekOfYear, value: horizonWeeks, to: now)
        let occurrences = RecurrenceExpander.occurrences(
            of: schedule.recurrence,
            calendar: calendar,
            limit: horizonWeeks * 7,
            until: horizon
        )

        let existing = scheduledWorkouts(in: context).filter { $0.scheduleId == schedule.id }
        var byDate: [Date: ScheduledWorkout] = [:]
        for workout in existing {
            // Une seance DEPLACEE reste rattachee a son creneau d'origine :
            // sans cela, la recurrence croirait le creneau vide et creerait
            // un doublon a la date que l'utilisateur venait de quitter.
            let slot = workout.originalDate ?? workout.plannedDate
            byDate[calendar.startOfDay(for: slot)] = workout
        }

        let sessions = program?.orderedSessions ?? []
        var created = 0

        for (index, occurrence) in occurrences.enumerated() {
            let day = calendar.startOfDay(for: occurrence.date)
            if let known = byDate[day] {
                byDate.removeValue(forKey: day)
                // Une seance deja traitee — commencee, terminee, ignoree ou
                // deplacee a la main — n'est jamais rehabillee : le planning
                // ne doit pas reecrire une decision prise.
                guard known.state == .planned, known.originalDate == nil else { continue }
                if known.plannedDate != occurrence.date {
                    known.plannedDate = occurrence.date
                    known.updatedAt = now
                }
                continue
            }

            let session = sessions.isEmpty ? nil : sessions[index % sessions.count]
            let workout = ScheduledWorkout(
                plannedDate: occurrence.date,
                programSessionId: session?.id,
                displayName: session?.name ?? (schedule.name.isEmpty ? "Séance" : schedule.name),
                placeId: schedule.placeId,
                scheduleId: schedule.id
            )
            context.insert(workout)
            created += 1
        }

        // Ce qui reste dans `byDate` n'est plus produit par la recurrence.
        var removed = 0
        for (_, orphan) in byDate
        where orphan.state == .planned && orphan.originalDate == nil && orphan.plannedDate > now {
            orphan.deletedAt = now
            orphan.updatedAt = now
            removed += 1
        }

        schedule.updatedAt = now
        return (created, removed)
    }

    // MARK: - Décisions

    /// Deplace une seance. L'historique n'est jamais touche : seule la date
    /// prevue change, et la date d'origine est conservee pour l'expliquer.
    static func move(_ workout: ScheduledWorkout, to date: Date, in context: ModelContext, now: Date = .now) {
        guard workout.state != .completed else { return }
        if workout.originalDate == nil { workout.originalDate = workout.plannedDate }
        workout.plannedDate = date
        if workout.state == .planned { workout.state = .postponed }
        workout.updatedAt = now
        _ = PersistenceSupport.save(context, action: "Déplacement de la séance")
    }

    static func update(_ workout: ScheduledWorkout, to state: ScheduledWorkoutState, in context: ModelContext, now: Date = .now) {
        workout.state = state
        workout.updatedAt = now
        _ = PersistenceSupport.save(context, action: "Mise à jour du planning")
    }

    /// Propositions de replanification pour les seances manquees.
    static func rescheduleProposals(
        in context: ModelContext,
        catalog: ExerciseCatalog?,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> [RescheduleProposal] {
        let allSlots = slots(in: context, catalog: catalog)
        let missed = RescheduleAdvisor.missedSlots(among: allSlots, now: now, calendar: calendar)
        guard !missed.isEmpty else { return [] }

        let preferred = preferredWeekdays(in: context)
        var proposals: [RescheduleProposal] = []
        var projected = allSlots

        for slot in missed {
            guard let proposal = RescheduleAdvisor.proposal(
                for: slot,
                among: projected,
                preferredWeekdays: preferred,
                now: now,
                calendar: calendar
            ) else { continue }
            proposals.append(proposal)
            // La proposition suivante doit tenir compte de la precedente,
            // sinon deux seances manquees atterrissent le meme jour.
            projected = projected.map { existing in
                guard existing.id == slot.id else { return existing }
                return PlannedSlot(
                    id: existing.id,
                    date: proposal.proposedDate,
                    title: existing.title,
                    primaryMuscles: existing.primaryMuscles,
                    isSettled: false
                )
            }
        }
        return proposals
    }

    static func preferredWeekdays(in context: ModelContext) -> Set<Int> {
        schedules(in: context)
            .filter(\.isEnabled)
            .reduce(into: Set<Int>()) { $0.formUnion($1.weekdays) }
    }

    /// Applique une proposition apres confirmation explicite.
    static func accept(_ proposal: RescheduleProposal, in context: ModelContext, now: Date = .now) {
        guard let workout = scheduledWorkouts(in: context).first(where: { $0.id == proposal.workoutId }) else { return }
        move(workout, to: proposal.proposedDate, in: context, now: now)
    }

    // MARK: - Conflits

    static func conflicts(
        in context: ModelContext,
        catalog: ExerciseCatalog?,
        calendar: Calendar = .current
    ) -> [ScheduleConflict] {
        ScheduleConflictDetector.conflicts(among: slots(in: context, catalog: catalog), calendar: calendar)
    }
}

extension ScheduledWorkoutState {
    /// Etat « traite » : la decision a ete prise, le creneau ne peut plus
    /// etre considere comme manque ni entrer en collision.
    var isSettled: Bool {
        switch self {
        case .completed, .partial, .skipped, .started: return true
        case .planned, .postponed: return false
        }
    }
}
