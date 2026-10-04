import Foundation
import SwiftData
import MuscuEngine

struct IntervalRuntimeState: Codable, Equatable {
    var exerciseId: String
    var index: Int
    var segmentEndDate: Date?
    var isPaused: Bool
    var pausedRemaining: TimeInterval
    var showingRepsEntry: Bool
    var totalReps: Int
}

struct AmrapRuntimeState: Codable, Equatable {
    var exerciseId: String
    var endDate: Date?
    var isFinished: Bool
    var counter: Int
}

struct WarmupRuntimeState: Codable, Equatable {
    var stepRaw: String = "choice"
    var endDate: Date?
    var startedAt: Date?
    var cardioMinutes: Int = Warmup.cardioMinutes

    init(
        stepRaw: String = "choice",
        endDate: Date? = nil,
        startedAt: Date? = nil,
        cardioMinutes: Int = Warmup.cardioMinutes
    ) {
        self.stepRaw = stepRaw
        self.endDate = endDate
        self.startedAt = startedAt
        self.cardioMinutes = cardioMinutes
    }

    /// Meme raison que `WorkoutRuntimeState` : `cardioMinutes` est arrive
    /// apres, et une cle absente ne doit pas faire echouer tout l'etat.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stepRaw = try container.decodeIfPresent(String.self, forKey: .stepRaw) ?? "choice"
        endDate = try container.decodeIfPresent(Date.self, forKey: .endDate)
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        cardioMinutes = try container.decodeIfPresent(Int.self, forKey: .cardioMinutes) ?? Warmup.cardioMinutes
    }
}

/// Bloc « For Time » : on mesure le TEMPS mis pour accomplir le travail,
/// avec un plafond facultatif. `startedAt` est une date absolue afin que le
/// chrono reste juste apres une mise en arriere-plan prolongee.
struct ForTimeRuntimeState: Codable, Equatable {
    var exerciseId: String
    var startedAt: Date?
    var finishedAt: Date?
    var completedRounds: Int = 0
    var extraReps: Int = 0
}

/// Etat volatil d'une seance en cours : ce qui n'a de sens que pendant son
/// deroulement (chrono de repos, intervalle, AMRAP, For Time, echauffement).
///
/// Ce type est **persiste en JSON** sur `ActiveWorkout.runtimeStateData`, ce
/// qui en fait un format de donnees a part entiere : il gagne des champs au
/// fil des versions et doit rester lisible par l'application qui vient.
///
/// Le decodeur synthetise par Swift n'applique PAS les valeurs par defaut
/// quand une cle manque : `restTotalSeconds` et `warmup`, ajoutes apres coup,
/// faisaient donc **echouer** le decodage d'un etat ecrit par une version
/// anterieure. L'echec etait rattrape par un `?? WorkoutRuntimeState()` :
/// l'utilisateur perdait son chrono de repos et son AMRAP en cours, sans la
/// moindre trace. D'ou le decodeur explicite ci-dessous, et le numero de
/// version qui permettra de refuser proprement un format plus recent.
struct WorkoutRuntimeState: Codable, Equatable {
    /// Version du FORMAT, pas de l'etat. A incrementer quand un champ change
    /// de sens — jamais quand on en ajoute un tolerant.
    static let currentVersion = 1

    var version: Int = WorkoutRuntimeState.currentVersion
    var restEndDate: Date?
    var restTotalSeconds: Int = 0
    var interval: IntervalRuntimeState?
    var amrap: AmrapRuntimeState?
    var forTime: ForTimeRuntimeState?
    var warmup = WarmupRuntimeState()

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Un etat ecrit avant l'introduction du numero porte la version 1.
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        restEndDate = try container.decodeIfPresent(Date.self, forKey: .restEndDate)
        restTotalSeconds = try container.decodeIfPresent(Int.self, forKey: .restTotalSeconds) ?? 0
        interval = try container.decodeIfPresent(IntervalRuntimeState.self, forKey: .interval)
        amrap = try container.decodeIfPresent(AmrapRuntimeState.self, forKey: .amrap)
        forTime = try container.decodeIfPresent(ForTimeRuntimeState.self, forKey: .forTime)
        warmup = try container.decodeIfPresent(WarmupRuntimeState.self, forKey: .warmup) ?? WarmupRuntimeState()
    }

    /// Un etat ecrit par une version PLUS RECENTE de l'application ne doit
    /// pas etre interprete a moitie : mieux vaut repartir d'un etat neuf que
    /// de deviner ce qu'on ne comprend pas.
    var isReadable: Bool { version <= WorkoutRuntimeState.currentVersion }
}

// Une seule instance au plus doit exister : la seance en cours, pour
// permettre la reprise apres interruption de l'app.
@Model
final class ActiveWorkout {
    @Attribute(.unique) var id: UUID = UUID()
    var startedAt: Date = Date()
    var programSessionId: UUID = UUID()
    var exerciseIndex: Int = 0
    var setIndex: Int = 0

    // Phase de la seance ("warmup" ou "running", cf. RunnerPhase dans
    // WorkoutState.swift). Champ optionnel-par-defaut : les ActiveWorkout
    // deja persistees avant l'ajout de l'echauffement n'etaient jamais en
    // phase d'echauffement, "running" est donc un defaut correct pour elles.
    var phaseRaw: String = "running"

    // Snapshot JSON (encodage de [RunExercise], cf. WorkoutState.swift) des
    // exercices de la seance en cours, tels que mutes en memoire par
    // addSet/removeSet/replaceExercise. Sans ce snapshot, un kill+resume de
    // l'app reconstruirait les exercices depuis la ProgramSession source et
    // perdrait ces mutations, desynchronisant exerciseIndex/setIndex (deja
    // persistes) du contenu reel de la seance. Champ optionnel : les
    // ActiveWorkout deja persistees avant son ajout se contentent de nil et
    // retombent sur la reconstruction depuis le programme (cf. `resume`).
    var runExercisesData: Data?
    var runtimeStateData: Data?

    // Snapshot du deroule (WorkoutPlan) et position exacte dans ce deroule
    // (WorkoutPosition), tels que la machine a etats du moteur les manipule.
    // Champs optionnels : une ActiveWorkout persistee avant leur ajout
    // retombe sur `runExercisesData` + `exerciseIndex`/`setIndex`.
    var planData: Data?
    var positionData: Data?

    // Seance libre : demarree sans programme, ses exercices sont ajoutes au
    // fil de l'eau. `programSessionId` ne designe alors aucune seance de
    // programme. Faux pour toute seance anterieure a ce champ (v7), qui
    // venait forcement d'un programme.
    var isFreeSession: Bool = false

    // Metadonnees de synchronisation. Une seance en cours n'a qu'un seul
    // proprietaire d'edition a la fois : c'est la strategie de fusion
    // `singleOwner` qui tranche, sur la base de `updatedAt`.
    var updatedAt: Date = Date()
    var deletedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \CompletedSet.activeWorkout)
    var loggedSets: [CompletedSet] = []

    init(
        id: UUID = UUID(),
        startedAt: Date = Date(),
        programSessionId: UUID,
        exerciseIndex: Int = 0,
        setIndex: Int = 0,
        phaseRaw: String = "running",
        runExercisesData: Data? = nil,
        runtimeStateData: Data? = nil,
        planData: Data? = nil,
        positionData: Data? = nil,
        isFreeSession: Bool = false,
        updatedAt: Date = Date(),
        deletedAt: Date? = nil,
        loggedSets: [CompletedSet] = []
    ) {
        self.id = id
        self.startedAt = startedAt
        self.programSessionId = programSessionId
        self.exerciseIndex = exerciseIndex
        self.setIndex = setIndex
        self.phaseRaw = phaseRaw
        self.runExercisesData = runExercisesData
        self.runtimeStateData = runtimeStateData
        self.planData = planData
        self.positionData = positionData
        self.isFreeSession = isFreeSession
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.loggedSets = loggedSets
    }
}

extension DraftProgram {
    func toModel() -> Program {
        let sessionModels = sessions.enumerated().map { sessionIndex, draftSession -> ProgramSession in
            let exerciseModels = draftSession.exercises.enumerated().map { exerciseIndex, draftExercise -> PrescribedExercise in
                PrescribedExercise(
                    exerciseId: draftExercise.exerciseId,
                    displayName: draftExercise.displayName,
                    orderIndex: exerciseIndex,
                    formatRaw: SetFormat.classic.rawValue,
                    sets: draftExercise.sets,
                    repsLower: draftExercise.repsLower,
                    repsUpper: draftExercise.repsUpper,
                    restSeconds: draftExercise.restSeconds,
                    percentOneRepMax: draftExercise.percentOneRepMax
                )
            }
            return ProgramSession(
                name: draftSession.name,
                orderIndex: sessionIndex,
                warmupEnabled: draftSession.warmupEnabled,
                exercises: exerciseModels
            )
        }
        return Program(
            name: name,
            notes: notes,
            sessions: sessionModels
        )
    }
}

extension ActiveWorkout {
    var syncMetadata: SyncMetadata {
        SyncMetadata(identifier: id, createdAt: startedAt, updatedAt: updatedAt, deletedAt: deletedAt)
    }

    func touch(now: Date = .now) { updatedAt = now }
}
