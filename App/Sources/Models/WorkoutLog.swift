import Foundation
import SwiftData
import MuscuEngine

/// Type de charge d'une serie, tel que persiste. Les valeurs brutes sont
/// stables : `weighted` (lest) a ete ajoute apres coup, les anciennes series
/// restent decodables et conservent leur valeur d'origine.
enum ExerciseLoadType: String, Codable, CaseIterable {
    case external
    case bodyweight
    /// Poids de corps + lest : `weight` stocke le LEST SEUL.
    case weighted
    /// Poids de corps - assistance : `weight` stocke l'ASSISTANCE.
    case assisted
    case unknown

    /// Pont vers le type pur du moteur, qui porte toutes les regles de
    /// calcul (charge effective, tonnage, eligibilite au 1RM).
    var loadKind: LoadKind {
        switch self {
        case .external: return .external
        case .bodyweight: return .bodyweight
        case .weighted: return .weighted
        case .assisted: return .assisted
        case .unknown: return .unknown
        }
    }

    init(loadKind: LoadKind) {
        switch loadKind {
        case .external: self = .external
        case .bodyweight: self = .bodyweight
        case .weighted: self = .weighted
        case .assisted: self = .assisted
        case .unknown: self = .unknown
        }
    }
}

@Model
final class CompletedSession {
    @Attribute(.unique) var id: UUID = UUID()
    var programId: UUID?
    var programSessionId: UUID?
    var date: Date = Date()
    var programName: String = ""
    var sessionName: String = ""
    var durationSeconds: Int = 0

    // MARK: - Champs v3 (facultatifs, migration legere)

    var notes: String = ""
    /// Seance planifiee a l'origine de cette seance realisee, le cas echeant.
    var scheduledWorkoutId: UUID?
    /// Check-in de forme rattache a cette seance.
    var readinessEntryId: UUID?
    /// Poids de corps connu au moment de la seance (kg). Fige ici pour que
    /// les calculs de charge effective restent justes des annees apres.
    var bodyweightKilograms: Double?
    /// Une seance terminee est immuable : une correction cree une revision
    /// tracee par ce compteur et par `updatedAt`.
    var revision: Int = 1

    // MARK: - Champs v4 (facultatifs, migration legere)

    /// Lieu ou la seance a eu lieu. nil = non renseigne.
    var placeId: UUID?
    /// Origine de la seance quand elle vient d'un import (« Strong »,
    /// « Hevy », « CSV »). Vide = saisie dans Muscu.
    var importSource: String = ""
    /// Cle de deduplication d'import. Vide hors import.
    var importSignature: String = ""

    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \CompletedSet.session)
    var sets: [CompletedSet] = []

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        programId: UUID? = nil,
        programSessionId: UUID? = nil,
        programName: String,
        sessionName: String,
        durationSeconds: Int = 0,
        notes: String = "",
        placeId: UUID? = nil,
        importSource: String = "",
        importSignature: String = "",
        scheduledWorkoutId: UUID? = nil,
        readinessEntryId: UUID? = nil,
        bodyweightKilograms: Double? = nil,
        revision: Int = 1,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil,
        sets: [CompletedSet] = []
    ) {
        self.id = id
        self.date = date
        self.programId = programId
        self.programSessionId = programSessionId
        self.programName = programName
        self.sessionName = sessionName
        self.durationSeconds = durationSeconds
        self.notes = notes
        self.placeId = placeId
        self.importSource = importSource
        self.importSignature = importSignature
        self.scheduledWorkoutId = scheduledWorkoutId
        self.readinessEntryId = readinessEntryId
        self.bodyweightKilograms = bodyweightKilograms
        self.revision = revision
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.sets = sets
    }
}

extension CompletedSession {
    var syncMetadata: SyncMetadata {
        SyncMetadata(identifier: id, createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt)
    }

    var orderedSets: [CompletedSet] {
        sets.sorted { ($0.orderIndex, $0.roundIndex, $0.setIndex, $0.subSetIndex) < ($1.orderIndex, $1.roundIndex, $1.setIndex, $1.subSetIndex) }
    }

    var workingSets: [CompletedSet] { sets.filter { $0.role.countsAsWorkingSet } }

    /// Series converties vers le type pur du moteur : toute analyse partagee
    /// (tonnage, 1RM estime, records) part de cette conversion unique.
    func metricsInputs(fallbackBodyweightKilograms: Double? = nil) -> [SetMetricsInput] {
        let bodyweight = bodyweightKilograms ?? fallbackBodyweightKilograms
        return sets.map { $0.metricsInput(bodyweightKilograms: bodyweight) }
    }
}

// CompletedSet est partage entre CompletedSession.sets (historique) et
// ActiveWorkout.loggedSets (seance en cours). SwiftData exige des inverses
// distincts pour chaque relation vers un meme type : on modelise donc les
// deux parents comme optionnels sur CompletedSet plutot que de dupliquer
// un struct Codable. Un CompletedSet donne n'a en pratique qu'un seul des
// deux parents non-nil a la fois.
@Model
final class CompletedSet {
    @Attribute(.unique) var id: UUID = UUID()
    var exerciseId: String = ""
    var displayName: String = ""
    var orderIndex: Int = 0
    var setIndex: Int = 0
    var weight: Double = 0
    var reps: Int = 0
    var isWarmup: Bool = false
    var loadTypeRaw: String = ExerciseLoadType.unknown.rawValue

    // MARK: - Champs v3 (facultatifs, migration legere)

    /// Role de la serie. Vide = deduit de `isWarmup`, qui reste la source de
    /// verite pour les series enregistrees avant l'ajout de ce champ.
    var roleRaw: String = ""
    var sideConventionRaw: String = SideConvention.bilateral.rawValue
    var tempoNotation: String = ""
    /// `EffortRating` encode (RPE ou RIR declare). nil = non renseigne.
    var effortData: Data?
    var notes: String = ""
    /// Echec musculaire atteint sur cette serie, marque explicitement.
    var reachedFailure: Bool = false
    /// Groupe (superset, circuit) auquel la serie appartient, et tour courant.
    var groupId: UUID?
    var roundIndex: Int = 0
    /// Palier d'un dropset, mini-serie d'un rest-pause ou d'un myo-reps.
    /// Zero = serie principale.
    var subSetIndex: Int = 0
    var durationSeconds: Int?
    var distanceMeters: Double?
    var calories: Double?
    /// Exercice initialement prevu lorsqu'une substitution a eu lieu :
    /// l'historique garde prevu ET realise.
    var plannedExerciseId: String = ""
    var formatRaw: String = SetFormat.classic.rawValue
    /// Rang de saisie dans la seance (0-based). L'ordre d'affichage groupe
    /// les series par exercice ; ce rang conserve l'ordre REEL de saisie,
    /// dont depend la correction de la derniere serie. Zero pour les series
    /// anterieures a ce champ, qui n'en avaient pas besoin (aucun groupe).
    var sequenceIndex: Int = 0

    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?

    var session: CompletedSession?
    var activeWorkout: ActiveWorkout?

    init(
        id: UUID = UUID(),
        exerciseId: String,
        displayName: String,
        orderIndex: Int,
        setIndex: Int,
        weight: Double,
        reps: Int,
        isWarmup: Bool = false,
        loadTypeRaw: String = ExerciseLoadType.unknown.rawValue,
        roleRaw: String = "",
        sideConventionRaw: String = SideConvention.bilateral.rawValue,
        tempoNotation: String = "",
        effortData: Data? = nil,
        notes: String = "",
        reachedFailure: Bool = false,
        groupId: UUID? = nil,
        roundIndex: Int = 0,
        subSetIndex: Int = 0,
        durationSeconds: Int? = nil,
        distanceMeters: Double? = nil,
        calories: Double? = nil,
        plannedExerciseId: String = "",
        formatRaw: String = SetFormat.classic.rawValue,
        sequenceIndex: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.displayName = displayName
        self.orderIndex = orderIndex
        self.setIndex = setIndex
        self.weight = weight
        self.reps = reps
        self.isWarmup = isWarmup
        self.loadTypeRaw = loadTypeRaw
        self.roleRaw = roleRaw
        self.sideConventionRaw = sideConventionRaw
        self.tempoNotation = tempoNotation
        self.effortData = effortData
        self.notes = notes
        self.reachedFailure = reachedFailure
        self.groupId = groupId
        self.roundIndex = roundIndex
        self.subSetIndex = subSetIndex
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.calories = calories
        self.plannedExerciseId = plannedExerciseId
        self.formatRaw = formatRaw
        self.sequenceIndex = sequenceIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    var loadType: ExerciseLoadType {
        ExerciseLoadType(rawValue: loadTypeRaw) ?? .unknown
    }
}

extension CompletedSet {
    /// Role de la serie. Les series anterieures a ce champ n'ont que
    /// `isWarmup` : on le respecte plutot que d'inventer un role.
    var role: SetRole {
        get {
            if let role = SetRole(rawValue: roleRaw) { return role }
            return isWarmup ? .warmup : .working
        }
        set {
            roleRaw = newValue.rawValue
            isWarmup = newValue == .warmup
        }
    }

    var sideConvention: SideConvention {
        get { SideConvention(rawValue: sideConventionRaw) ?? .bilateral }
        set { sideConventionRaw = newValue.rawValue }
    }

    var tempo: Tempo? {
        get { tempoNotation.isEmpty ? nil : Tempo(notation: tempoNotation) }
        set { tempoNotation = newValue?.notation ?? "" }
    }

    var effort: EffortRating? {
        get {
            guard let data = effortData,
                  let value = try? JSONDecoder().decode(EffortRating.self, from: data),
                  value.isValid else { return nil }
            return value
        }
        set { effortData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    var format: SetFormat {
        get { SetFormat(rawValue: formatRaw) ?? .classic }
        set { formatRaw = newValue.rawValue }
    }

    /// Conversion unique vers le type pur du moteur. Toute formule
    /// (tonnage, 1RM estime, duree sous tension) passe par la.
    func metricsInput(bodyweightKilograms: Double?) -> SetMetricsInput {
        SetMetricsInput(
            weightKilograms: weight,
            reps: reps,
            loadKind: loadType.loadKind,
            side: sideConvention,
            isWarmup: !role.countsAsWorkingSet,
            bodyweightKilograms: bodyweightKilograms,
            durationSeconds: durationSeconds,
            distanceMeters: distanceMeters
        )
    }

    var syncMetadata: SyncMetadata {
        SyncMetadata(identifier: id, createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt)
    }
}
