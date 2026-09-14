import Foundation
import SwiftData
import MuscuEngine

/// Recalcul des semaines à venir d'un plan enregistré.
///
/// Le moteur décide ; ce service traduit, et n'écrit qu'après confirmation.
/// Deux invariants portés ici : l'historique n'est jamais touché, et une
/// semaine déjà entamée n'est jamais replanifiée.
@MainActor
enum PlanRecalculationService {
    /// Une semaine est « traitée » dès qu'une de ses séances l'est : on ne
    /// replanifie pas une semaine dans laquelle l'athlète est déjà entré.
    static func isSettled(_ week: TrainingWeek) -> Bool {
        if week.state == .done || week.state == .skipped { return true }
        return week.orderedWorkouts.contains { $0.state.isSettled }
    }

    static func preview(
        for plan: TrainingPlan,
        in context: ModelContext,
        firstFutureWeekStart: Date,
        calendar: Calendar = .current
    ) -> PlanRecalculationPreview {
        let profile = ProfileStore.currentProfile(in: context)
        let weeks = plan.allWeeks.map { week in
            PlanWeekState(
                number: week.weekNumber,
                blockKind: BlockKind(rawValue: week.block?.kindRaw ?? "") ?? .accumulation,
                startDate: week.startDate,
                volumeMultiplier: week.volumeMultiplier,
                intensityMultiplier: week.intensityMultiplier,
                isSettled: isSettled(week)
            )
        }

        return PlanRecalculation.preview(
            weeks: weeks,
            // Sans style connu (plan créé avant que l'information soit
            // conservée), on garde la périodisation constante : re-dériver
            // des multiplicateurs depuis un style supposé serait inventer.
            style: plan.periodizationStyle ?? .flat,
            deloadEveryWeeks: plan.deloadEveryWeeks > 0 ? plan.deloadEveryWeeks : nil,
            goal: profile?.primaryGoal ?? .hypertrophy,
            experience: profile?.experience ?? .intermediate,
            firstFutureWeekStart: firstFutureWeekStart,
            calendar: calendar
        )
    }

    /// Applique l'aperçu. Chaque semaine à venir est déplacée avec ses
    /// séances encore modifiables ; les séances déjà traitées ne bougent pas,
    /// et l'historique n'est jamais relu.
    @discardableResult
    static func apply(
        _ preview: PlanRecalculationPreview,
        to plan: TrainingPlan,
        in context: ModelContext,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> Int {
        let changesByNumber = Dictionary(
            preview.changes.map { ($0.number, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var movedWorkouts = 0

        for week in plan.allWeeks {
            guard let change = changesByNumber[week.weekNumber], change.changesAnything else { continue }
            guard !isSettled(week) else { continue }

            week.startDate = change.newStartDate
            week.volumeMultiplier = change.newVolumeMultiplier
            week.intensityMultiplier = change.newIntensityMultiplier
            week.updatedAt = now

            guard change.dayShift != 0 else { continue }
            for workout in week.orderedWorkouts where !workout.state.isSettled && workout.deletedAt == nil {
                guard let shifted = calendar.date(byAdding: .day, value: change.dayShift, to: workout.plannedDate) else { continue }
                workout.plannedDate = shifted
                workout.updatedAt = now
                movedWorkouts += 1
            }
        }

        // La version du plan trace le recalcul : une séance planifiée sait
        // de quelle mouture elle vient.
        plan.version += 1
        plan.updatedAt = now
        _ = PersistenceSupport.save(context, action: "Recalcul des semaines à venir")
        return movedWorkouts
    }
}
