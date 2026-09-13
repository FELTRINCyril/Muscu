import Foundation
import SwiftData
import MuscuEngine

/// Transforme un plan propose par le moteur en entites SwiftData.
///
/// Rien n'est ecrit sans passer par ici : un plan doit arriver complet
/// (programme + blocs + semaines + seances datees) ou pas du tout.
@MainActor
enum PlanImporter {
    struct Result {
        var program: Program
        var plan: TrainingPlan
    }

    /// Cree le programme et le plan correspondant au brouillon. L'appelant
    /// reste responsable de la sauvegarde (cf. `PersistenceSupport`).
    @discardableResult
    static func insert(
        draft: DraftPlan,
        into context: ModelContext,
        activateProgram: Bool
    ) -> Result {
        let program = draft.program.toModel()
        if activateProgram {
            // Un seul programme actif a la fois : on desactive les autres.
            let existing = (try? context.fetch(FetchDescriptor<Program>())) ?? []
            for other in existing where other.isActive { other.isActive = false }
            program.isActive = true
        }
        context.insert(program)

        let plan = TrainingPlan(
            name: draft.name,
            programId: program.id,
            startDate: draft.weeks.first?.startDate ?? .now,
            statusRaw: TrainingPlanStatus.active.rawValue,
            notes: draft.rationale.joined(separator: "\n")
        )
        context.insert(plan)

        let sessionsByIndex = program.orderedSessions
        var blocksByKind: [String: TrainingBlock] = [:]
        var orderIndex = 0

        for draftWeek in draft.weeks.sorted(by: { $0.number < $1.number }) {
            // Les semaines consecutives de meme nature partagent leur bloc,
            // exactement comme le moteur les regroupe.
            let block: TrainingBlock
            let key = "\(draftWeek.blockRaw)-\(blockGroupIndex(for: draftWeek, in: draft))"
            if let existing = blocksByKind[key] {
                block = existing
            } else {
                block = TrainingBlock(
                    kindRaw: draftWeek.blockRaw,
                    orderIndex: orderIndex,
                    name: TrainingBlockKind(rawValue: draftWeek.blockRaw)?.displayName ?? "",
                    rationale: draftWeek.rationale
                )
                block.plan = plan
                plan.blocks.append(block)
                context.insert(block)
                blocksByKind[key] = block
                orderIndex += 1
            }

            let week = TrainingWeek(
                weekNumber: draftWeek.number,
                startDate: draftWeek.startDate,
                stateRaw: TrainingWeekState.upcoming.rawValue,
                volumeTargetData: try? JSONEncoder().encode(draft.weeklySetsByMuscle),
                volumeMultiplier: draftWeek.volumeMultiplier,
                intensityMultiplier: draftWeek.intensityMultiplier
            )
            week.block = block
            block.weeks.append(week)
            context.insert(week)

            for draftWorkout in draftWeek.workouts {
                let session = sessionsByIndex.indices.contains(draftWorkout.sessionIndex)
                    ? sessionsByIndex[draftWorkout.sessionIndex]
                    : nil
                let workout = ScheduledWorkout(
                    plannedDate: draftWorkout.date,
                    programSessionId: session?.id,
                    displayName: draftWorkout.displayName
                )
                workout.week = week
                week.scheduledWorkouts.append(workout)
                context.insert(workout)
            }
        }

        // La premiere semaine devient la semaine courante.
        plan.allWeeks.first?.state = .current
        return Result(program: program, plan: plan)
    }

    /// Index du groupe de semaines consecutives de meme nature, pour que deux
    /// phases d'accumulation separees par une decharge forment bien deux
    /// blocs distincts.
    private static func blockGroupIndex(for week: DraftPlanWeek, in draft: DraftPlan) -> Int {
        let ordered = draft.weeks.sorted { $0.number < $1.number }
        var group = 0
        var previousKind: String?
        for candidate in ordered {
            if let previousKind, previousKind != candidate.blockRaw {
                group += 1
            }
            previousKind = candidate.blockRaw
            if candidate.number == week.number { return group }
        }
        return group
    }
}
