import Foundation
import SwiftData
import MuscuEngine

/// Nature d'un bloc de periodisation.
enum TrainingBlockKind: String, Codable, CaseIterable, Sendable {
    case accumulation
    case intensification
    case realization
    case deload

    var displayName: String {
        switch self {
        case .accumulation: return String(localized: "Accumulation")
        case .intensification: return String(localized: "Intensification")
        case .realization: return String(localized: "Réalisation")
        case .deload: return String(localized: "Décharge")
        }
    }
}

/// Etat d'un plan. Un plan archive n'est plus propose mais reste consultable.
enum TrainingPlanStatus: String, Codable, CaseIterable, Sendable {
    case draft
    case active
    case completed
    case archived
}

/// Etat d'une semaine planifiee.
enum TrainingWeekState: String, Codable, CaseIterable, Sendable {
    case upcoming
    case current
    case done
    case skipped
}

/// Etat d'une seance planifiee. Les etats terminaux n'alterent jamais
/// l'historique : ils decrivent le PLANNING, pas la performance.
enum ScheduledWorkoutState: String, Codable, CaseIterable, Sendable {
    case planned
    case started
    case completed
    case partial
    case skipped
    case postponed
}

/// Plan d'entrainement date, adosse a un `Program`. Un plan ne duplique pas
/// les seances : il les reference par identifiant stable, afin qu'une
/// modification de programme n'ait jamais a reecrire le planning.
@Model
final class TrainingPlan {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = ""
    var programId: UUID?
    var startDate: Date = Date()
    var statusRaw: String = TrainingPlanStatus.draft.rawValue
    /// Version du plan : incrementee a chaque recalcul confirme, afin de
    /// tracer quelle version a produit une seance planifiee.
    var version: Int = 1
    var notes: String = ""

    @Relationship(deleteRule: .cascade, inverse: \TrainingBlock.plan)
    var blocks: [TrainingBlock] = []

    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        programId: UUID? = nil,
        startDate: Date = Date(),
        statusRaw: String = TrainingPlanStatus.draft.rawValue,
        version: Int = 1,
        notes: String = "",
        blocks: [TrainingBlock] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.programId = programId
        self.startDate = startDate
        self.statusRaw = statusRaw
        self.version = version
        self.notes = notes
        self.blocks = blocks
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

extension TrainingPlan {
    var status: TrainingPlanStatus {
        get { TrainingPlanStatus(rawValue: statusRaw) ?? .draft }
        set { statusRaw = newValue.rawValue }
    }

    var orderedBlocks: [TrainingBlock] { blocks.sorted { $0.orderIndex < $1.orderIndex } }

    var allWeeks: [TrainingWeek] {
        orderedBlocks.flatMap(\.orderedWeeks).sorted { $0.weekNumber < $1.weekNumber }
    }

    var syncMetadata: SyncMetadata {
        SyncMetadata(identifier: id, createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt)
    }
}

@Model
final class TrainingBlock {
    @Attribute(.unique) var id: UUID = UUID()
    var kindRaw: String = TrainingBlockKind.accumulation.rawValue
    var orderIndex: Int = 0
    var name: String = ""
    /// Explication courte du role du bloc, affichee a l'utilisateur.
    var rationale: String = ""

    var plan: TrainingPlan?

    @Relationship(deleteRule: .cascade, inverse: \TrainingWeek.block)
    var weeks: [TrainingWeek] = []

    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        kindRaw: String = TrainingBlockKind.accumulation.rawValue,
        orderIndex: Int,
        name: String = "",
        rationale: String = "",
        weeks: [TrainingWeek] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.kindRaw = kindRaw
        self.orderIndex = orderIndex
        self.name = name
        self.rationale = rationale
        self.weeks = weeks
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

extension TrainingBlock {
    var kind: TrainingBlockKind {
        get { TrainingBlockKind(rawValue: kindRaw) ?? .accumulation }
        set { kindRaw = newValue.rawValue }
    }

    var orderedWeeks: [TrainingWeek] { weeks.sorted { $0.weekNumber < $1.weekNumber } }
}

@Model
final class TrainingWeek {
    @Attribute(.unique) var id: UUID = UUID()
    /// Numero de semaine dans le PLAN (1-based), pas dans le bloc.
    var weekNumber: Int = 1
    var startDate: Date = Date()
    var stateRaw: String = TrainingWeekState.upcoming.rawValue
    /// Cible de volume : nombre de series difficiles par groupe musculaire.
    var volumeTargetData: Data?
    /// Multiplicateur applique au volume et a l'intensite pour une decharge.
    var volumeMultiplier: Double = 1
    var intensityMultiplier: Double = 1

    var block: TrainingBlock?

    @Relationship(deleteRule: .cascade, inverse: \ScheduledWorkout.week)
    var scheduledWorkouts: [ScheduledWorkout] = []

    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        weekNumber: Int,
        startDate: Date = Date(),
        stateRaw: String = TrainingWeekState.upcoming.rawValue,
        volumeTargetData: Data? = nil,
        volumeMultiplier: Double = 1,
        intensityMultiplier: Double = 1,
        scheduledWorkouts: [ScheduledWorkout] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.weekNumber = weekNumber
        self.startDate = startDate
        self.stateRaw = stateRaw
        self.volumeTargetData = volumeTargetData
        self.volumeMultiplier = volumeMultiplier
        self.intensityMultiplier = intensityMultiplier
        self.scheduledWorkouts = scheduledWorkouts
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

extension TrainingWeek {
    var state: TrainingWeekState {
        get { TrainingWeekState(rawValue: stateRaw) ?? .upcoming }
        set { stateRaw = newValue.rawValue }
    }

    var volumeTarget: [String: Int] {
        get {
            guard let data = volumeTargetData,
                  let value = try? JSONDecoder().decode([String: Int].self, from: data) else { return [:] }
            return value
        }
        set { volumeTargetData = try? JSONEncoder().encode(newValue) }
    }

    var orderedWorkouts: [ScheduledWorkout] {
        scheduledWorkouts.sorted { $0.plannedDate < $1.plannedDate }
    }

    /// Une semaine est une DÉCHARGE quand son bloc l'est. Un volume réduit
    /// ne suffit pas : une semaine d'intensification réduit elle aussi le
    /// volume, sans être une décharge pour autant.
    var isDeload: Bool { block?.kind == .deload }
}

/// Une seance prevue a une date. Elle reference la seance de programme par
/// identifiant stable et garde une trace de la seance terminee qui en
/// resulte, sans jamais la modifier.
@Model
final class ScheduledWorkout {
    @Attribute(.unique) var id: UUID = UUID()
    var plannedDate: Date = Date()
    var programSessionId: UUID?
    /// Nom affiche au moment de la planification : garde le planning lisible
    /// meme si la seance source est renommee ou supprimee.
    var displayName: String = ""
    var stateRaw: String = ScheduledWorkoutState.planned.rawValue
    /// `CompletedSession.id` produite par cette seance planifiee, le cas echeant.
    var completedSessionId: UUID?
    var notes: String = ""

    // MARK: - Champs v4 (facultatifs, migration legere)

    /// Lieu prevu pour cette seance. nil = lieu par defaut du profil.
    var placeId: UUID?
    /// Recurrence qui a produit cette seance, le cas echeant.
    var scheduleId: UUID?
    /// Date d'origine avant un report. Conservee pour expliquer le
    /// deplacement : « reportee du 3 au 5 » est plus utile que « le 5 ».
    var originalDate: Date?

    var week: TrainingWeek?

    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        plannedDate: Date,
        programSessionId: UUID? = nil,
        displayName: String = "",
        stateRaw: String = ScheduledWorkoutState.planned.rawValue,
        completedSessionId: UUID? = nil,
        notes: String = "",
        placeId: UUID? = nil,
        scheduleId: UUID? = nil,
        originalDate: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.plannedDate = plannedDate
        self.programSessionId = programSessionId
        self.displayName = displayName
        self.stateRaw = stateRaw
        self.completedSessionId = completedSessionId
        self.notes = notes
        self.placeId = placeId
        self.scheduleId = scheduleId
        self.originalDate = originalDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

extension ScheduledWorkout {
    var state: ScheduledWorkoutState {
        get { ScheduledWorkoutState(rawValue: stateRaw) ?? .planned }
        set { stateRaw = newValue.rawValue }
    }

    var syncMetadata: SyncMetadata {
        SyncMetadata(identifier: id, createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt)
    }
}
