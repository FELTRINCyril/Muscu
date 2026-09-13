import Foundation
import SwiftData

@MainActor
enum DataIntegrityRepair {
    static func run(context: ModelContext) throws {
        let programs = try context.fetch(FetchDescriptor<Program>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))
        let activePrograms = programs.filter(\.isActive)
        for program in activePrograms.dropFirst() { program.isActive = false }

        let workouts = try context.fetch(FetchDescriptor<ActiveWorkout>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)]))
        for workout in workouts.dropFirst() { context.delete(workout) }

        let records = try context.fetch(FetchDescriptor<ExerciseRecord>())
        for group in Dictionary(grouping: records, by: \.exerciseId).values {
            guard let keeper = group.max(by: { $0.updatedAt < $1.updatedAt }) else { continue }
            for duplicate in group where duplicate !== keeper {
                keeper.oneRepMax = maxNilSafe(keeper.oneRepMax, duplicate.oneRepMax)
                keeper.maxReps = maxNilSafe(keeper.maxReps, duplicate.maxReps)
                keeper.updatedAt = max(keeper.updatedAt, duplicate.updatedAt)
                context.delete(duplicate)
            }
            if keeper.oneRepMax == nil && keeper.maxReps == nil { context.delete(keeper) }
        }

        let history = try context.fetch(FetchDescriptor<CompletedSession>())
        for completed in history where completed.programId == nil || completed.programSessionId == nil {
            let matchingPrograms = programs.filter { $0.name == completed.programName }
            guard matchingPrograms.count == 1, let program = matchingPrograms.first else { continue }
            let matchingSessions = program.sessions.filter { $0.name == completed.sessionName }
            guard matchingSessions.count == 1, let session = matchingSessions.first else { continue }
            completed.programId = program.id
            completed.programSessionId = session.id
        }

        try context.save()
    }

    private static func maxNilSafe<T: Comparable>(_ lhs: T?, _ rhs: T?) -> T? {
        switch (lhs, rhs) {
        case (nil, nil): nil
        case (let value?, nil), (nil, let value?): value
        case (let lhs?, let rhs?): max(lhs, rhs)
        }
    }
}
