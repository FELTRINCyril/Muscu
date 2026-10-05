import Foundation

// Seance en miroir sur la montre (lot 7).
//
// Le telephone reste la SOURCE DE VERITE : la montre affiche l'etat qu'il
// pousse a chaque transition, et lui envoie des commandes qu'il execute par
// le meme chemin que les boutons de l'application. La montre ne modifie
// jamais elle-meme l'etat affiche : une commande refusee ne laisse donc
// aucune divergence.
//
// Ce fichier est pur (Foundation seulement) : il est compile dans
// l'application, la montre et les widgets, et teste dans MuscuTests.
// Idee de structure reprise d'Ischys (`PhoneLink.swift`, licence MIT, voir
// THIRD_PARTY_NOTICES.md) ; le format est propre a Muscu.

/// Hote de la seance Sante, tel que le telephone l'a decide (miroir du
/// `HealthWorkoutHost` du moteur, que la montre ne lie pas).
enum WatchHealthHost: String, Codable, Equatable, Sendable {
    case watch
    case phone
    case afterTheFact
}

/// Etat d'une seance en cours, pousse par le telephone a chaque transition.
struct WatchMirrorState: Codable, Equatable, Sendable {
    static let currentVersion = 1

    enum Phase: String, Codable, Equatable, Sendable {
        /// Aucune seance en cours sur l'iPhone.
        case idle
        /// Echauffement guide : il se fait sur l'iPhone, la montre peut le
        /// passer.
        case warmup
        /// Une serie a faire.
        case running
        /// L'etape courante demande une saisie sur l'iPhone (bloc minute,
        /// seance libre sans exercice, serie au temps).
        case needsPhone
        /// Tout est fait : la fin (effort, recapitulatif) se valide sur
        /// l'iPhone.
        case awaitingFinish
    }

    var version: Int
    /// Ordre des etats : strictement croissant cote telephone. Un etat plus
    /// ancien arrive en retard est ignore.
    var sequence: Int
    var phase: Phase
    var activeWorkoutId: UUID?
    var sessionName: String
    var startedAt: Date?
    /// Exercice, serie n/N, repos, serie suivante, identite de la serie :
    /// exactement ce que montre la Live Activity.
    var activity: WorkoutActivityState?
    /// Valeurs proposees par l'ecran de saisie, en kilogrammes. `nil` si
    /// elles ne sont pas connues (la montre n'invente jamais une charge).
    var plannedWeightKilograms: Double?
    var plannedReps: Int?
    /// Exercice au poids du corps : la charge proposee est un lest.
    var isBodyweight: Bool
    var massUnitSymbol: String
    var healthHost: WatchHealthHost
    /// Sante active et autorisee dans Muscu sur l'iPhone : la montre peut
    /// enregistrer une seance Sante quand on la lui confie.
    var healthEnabled: Bool

    init(
        version: Int = WatchMirrorState.currentVersion,
        sequence: Int,
        phase: Phase,
        activeWorkoutId: UUID? = nil,
        sessionName: String = "",
        startedAt: Date? = nil,
        activity: WorkoutActivityState? = nil,
        plannedWeightKilograms: Double? = nil,
        plannedReps: Int? = nil,
        isBodyweight: Bool = false,
        massUnitSymbol: String = "kg",
        healthHost: WatchHealthHost = .afterTheFact,
        healthEnabled: Bool = false
    ) {
        self.version = version
        self.sequence = sequence
        self.phase = phase
        self.activeWorkoutId = activeWorkoutId
        self.sessionName = sessionName
        self.startedAt = startedAt
        self.activity = activity
        self.plannedWeightKilograms = plannedWeightKilograms
        self.plannedReps = plannedReps
        self.isBodyweight = isBodyweight
        self.massUnitSymbol = massUnitSymbol
        self.healthHost = healthHost
        self.healthEnabled = healthEnabled
    }

    static func idle(sequence: Int, massUnitSymbol: String = "kg", healthEnabled: Bool = false) -> WatchMirrorState {
        WatchMirrorState(sequence: sequence, phase: .idle, massUnitSymbol: massUnitSymbol, healthEnabled: healthEnabled)
    }

    var hasWorkout: Bool { phase != .idle && activeWorkoutId != nil }

    /// La serie affichee peut etre validee depuis la montre : meme regle que
    /// le bouton « Valider » de la Live Activity (serie a faire, valeurs
    /// pre-remplies par la saisie de l'application ; pas de serie au temps
    /// ni de format chronometre).
    var canLogFromWatch: Bool {
        phase == .running && activity?.canQuickLog == true && plannedReps != nil && plannedWeightKilograms != nil
    }
}

// MARK: - Commandes de la montre

/// Commande envoyee par la montre. Elle est executee sur l'iPhone par le
/// MEME chemin que le bouton equivalent de l'application.
enum WatchCommand: Codable, Equatable, Sendable {
    /// Valide la serie identifiee par `slotKey` avec les valeurs ajustees a
    /// la Digital Crown (kilogrammes).
    case logSet(slotKey: String, weightKilograms: Double, reps: Int)
    case skipRest
    /// −15 s ou +15 s sur le repos en cours (`WatchCommandPolicy.restStepSeconds`).
    case adjustRest(seconds: Int)
    /// « Passer l'échauffement ».
    case finishWarmup
    /// Demarre la prochaine seance du programme sur l'iPhone.
    case startNext
    /// Demarre une seance libre sur l'iPhone.
    case startFree
    /// Redemande l'etat courant.
    case requestState
}

/// Enveloppe d'une commande : identifiant (pour apparier la reponse) et
/// seance visee (une commande pour une seance terminee est refusee).
struct WatchCommandEnvelope: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version: Int
    var id: UUID
    var workoutId: UUID?
    var command: WatchCommand

    init(version: Int = WatchCommandEnvelope.currentVersion, id: UUID = UUID(), workoutId: UUID?, command: WatchCommand) {
        self.version = version
        self.id = id
        self.workoutId = workoutId
        self.command = command
    }
}

/// Raison d'un refus, affichee telle quelle sur la montre.
enum WatchCommandRejection: String, Codable, Equatable, Sendable {
    /// Aucune seance en cours sur l'iPhone.
    case noWorkout
    /// La serie affichee n'est plus la serie courante (double tap, etat en
    /// retard) : rien n'est valide, l'etat est rafraichi.
    case staleSet
    /// La serie demande une saisie sur l'iPhone.
    case needsPhone
    /// Valeurs hors bornes.
    case invalidValues
    /// Pas de repos en cours (deja termine ou passe ailleurs).
    case noRest
    /// Une seance est deja en cours : on ne peut pas en demarrer une autre.
    case workoutAlreadyRunning
    /// Aucun programme actif, ou programme vide.
    case noNextSession
    /// L'enregistrement a echoue sur l'iPhone : rien n'a ete valide.
    case saveFailed
    /// iPhone injoignable : la commande n'est pas partie.
    case unreachable
    /// Version de l'application differente entre la montre et l'iPhone.
    case unsupported
}

/// Reponse du telephone : acceptee ou refusee, toujours avec l'etat a
/// jour — la montre affiche ce que le telephone sait, jamais ce qu'elle
/// suppose.
struct WatchCommandReply: Codable, Equatable, Sendable {
    var commandId: UUID
    var rejection: WatchCommandRejection?
    var state: WatchMirrorState

    var isAccepted: Bool { rejection == nil }
}

/// Ce que le telephone sait de la seance au moment d'evaluer une commande.
struct WatchCommandContext: Equatable, Sendable {
    var activeWorkoutId: UUID?
    var phase: WatchMirrorState.Phase
    var slotKey: String
    var canQuickLog: Bool
    var isResting: Bool
    var canAdjustRest: Bool
    var hasNextSession: Bool
}

/// Decision pure : la commande peut-elle etre executee ? Les gardes sont
/// celles du lot 6 (identite de serie, saisie entierement connue).
enum WatchCommandPolicy {
    enum Decision: Equatable, Sendable {
        case perform
        case reject(WatchCommandRejection)
    }

    static let weightRange: ClosedRange<Double> = 0...1_000
    static let repsRange: ClosedRange<Int> = 1...200
    /// Seuls les −15 s / +15 s de l'application existent : pas de duree
    /// libre (meme pas que `RestAdjustment.stepSeconds` du moteur, que la
    /// montre ne lie pas ; un test le verifie).
    static let restStepSeconds = 15

    static func evaluate(_ envelope: WatchCommandEnvelope, in context: WatchCommandContext) -> Decision {
        guard envelope.version <= WatchCommandEnvelope.currentVersion else { return .reject(.unsupported) }
        switch envelope.command {
        case .requestState:
            return .perform
        case .startNext, .startFree:
            guard context.activeWorkoutId == nil else { return .reject(.workoutAlreadyRunning) }
            if envelope.command == .startNext, !context.hasNextSession { return .reject(.noNextSession) }
            return .perform
        case .logSet, .skipRest, .adjustRest, .finishWarmup:
            break
        }

        // Commandes de seance : elles visent LA seance affichee.
        guard let current = context.activeWorkoutId, context.phase != .idle else { return .reject(.noWorkout) }
        if let target = envelope.workoutId, target != current { return .reject(.noWorkout) }

        switch envelope.command {
        case .logSet(let slotKey, let weight, let reps):
            guard context.phase == .running else {
                return .reject(context.phase == .warmup ? .staleSet : .needsPhone)
            }
            guard slotKey == context.slotKey else { return .reject(.staleSet) }
            guard context.canQuickLog else { return .reject(.needsPhone) }
            guard weight.isFinite, weightRange.contains(weight), repsRange.contains(reps) else {
                return .reject(.invalidValues)
            }
            return .perform
        case .skipRest:
            return context.isResting ? .perform : .reject(.noRest)
        case .adjustRest(let seconds):
            guard seconds == restStepSeconds || seconds == -restStepSeconds else { return .reject(.invalidValues) }
            return context.canAdjustRest ? .perform : .reject(.noRest)
        case .finishWarmup:
            return context.phase == .warmup ? .perform : .reject(.staleSet)
        case .requestState, .startNext, .startFree:
            return .perform
        }
    }
}

// MARK: - Etat cote montre

/// Machine d'etat du miroir, cote montre. Pure : la vue n'y ajoute que
/// l'envoi reel et l'horloge.
///
/// - un etat plus ancien que celui affiche est ignore ;
/// - une seule commande a la fois : un second tap pendant l'envoi est
///   ignore (protection double tap, en plus de l'identite de serie) ;
/// - iPhone injoignable : la commande est refusee AVANT l'envoi, l'etat
///   affiche ne bouge pas.
struct WatchMirrorMachine: Equatable, Sendable {
    private(set) var state: WatchMirrorState?
    private(set) var pendingCommandId: UUID?
    /// Dernier refus, a afficher jusqu'a la prochaine action reussie.
    private(set) var notice: WatchCommandRejection?

    init(state: WatchMirrorState? = nil) {
        self.state = state
    }

    enum SendDecision: Equatable, Sendable {
        case send(WatchCommandEnvelope)
        case refused(WatchCommandRejection)
        /// Une commande est deja en route : rien n'est envoye.
        case busy
    }

    var isBusy: Bool { pendingCommandId != nil }

    /// Applique un etat recu. `false` s'il est plus ancien que l'etat
    /// affiche (ou illisible) et donc ignore.
    @discardableResult
    mutating func receive(_ incoming: WatchMirrorState) -> Bool {
        guard incoming.version <= WatchMirrorState.currentVersion else { return false }
        if let state, incoming.sequence < state.sequence { return false }
        // Seance changee (terminee, abandonnee, nouvelle) : un refus portant
        // sur l'ancienne n'a plus de sens.
        if state?.activeWorkoutId != incoming.activeWorkoutId { notice = nil }
        state = incoming
        return true
    }

    /// Prepare l'envoi d'une commande.
    mutating func prepare(_ command: WatchCommand, reachable: Bool, id: UUID = UUID()) -> SendDecision {
        guard pendingCommandId == nil else { return .busy }
        guard reachable else {
            notice = .unreachable
            return .refused(.unreachable)
        }
        let envelope = WatchCommandEnvelope(id: id, workoutId: state?.activeWorkoutId, command: command)
        pendingCommandId = id
        notice = nil
        return .send(envelope)
    }

    /// Reponse du telephone. Une reponse a une autre commande (arrivee en
    /// retard) ne libere pas la commande en cours, mais son etat est tout
    /// de meme applique s'il est plus recent.
    mutating func receive(_ reply: WatchCommandReply) {
        receive(reply.state)
        guard reply.commandId == pendingCommandId else { return }
        pendingCommandId = nil
        notice = reply.rejection
    }

    /// L'envoi a echoue (iPhone devenu injoignable entre-temps).
    mutating func sendFailed(commandId: UUID) {
        guard commandId == pendingCommandId else { return }
        pendingCommandId = nil
        notice = .unreachable
    }

    mutating func clearNotice() {
        notice = nil
    }
}

// MARK: - Ajustement a la Digital Crown

/// Charge et repetitions ajustees a la montre avant validation. Les
/// valeurs partent de la proposition de l'iPhone ; la charge se regle par
/// pas de 2,5 kg (5 lb) dans l'unite du profil et repart TOUJOURS en kg.
struct WatchSetAdjustment: Equatable, Sendable {
    let unit: WatchMassUnit
    /// Charge dans l'unite affichee.
    private(set) var displayWeight: Double
    private(set) var reps: Int

    init(plannedWeightKilograms: Double, plannedReps: Int, unit: WatchMassUnit) {
        self.unit = unit
        self.displayWeight = Self.clampWeight(unit.fromKilograms(plannedWeightKilograms), unit: unit)
        self.reps = Self.clampReps(plannedReps)
    }

    /// Charge envoyee : la proposition exacte tant que rien n'a ete
    /// touche (pas d'arrondi parasite d'une conversion aller-retour).
    private var untouchedKilograms: Double?

    init(proposal state: WatchMirrorState) {
        let unit = WatchMassUnit(symbol: state.massUnitSymbol)
        self.init(plannedWeightKilograms: state.plannedWeightKilograms ?? 0, plannedReps: state.plannedReps ?? 1, unit: unit)
        untouchedKilograms = state.plannedWeightKilograms
    }

    var weightKilograms: Double {
        untouchedKilograms ?? unit.toKilograms(displayWeight)
    }

    /// Nouvelle charge (unite affichee), arrondie au pas et bornee.
    mutating func setDisplayWeight(_ value: Double) {
        let clamped = Self.clampWeight(value, unit: unit)
        guard clamped != displayWeight else { return }
        displayWeight = clamped
        untouchedKilograms = nil
    }

    mutating func setReps(_ value: Int) {
        reps = Self.clampReps(value)
    }

    private static func clampWeight(_ value: Double, unit: WatchMassUnit) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(0, value), unit.maximum)
    }

    private static func clampReps(_ value: Int) -> Int {
        min(max(WatchCommandPolicy.repsRange.lowerBound, value), WatchCommandPolicy.repsRange.upperBound)
    }
}

// MARK: - Haptique du repos

/// Signal haptique du repos au poignet.
enum RestHapticCue: Equatable, Sendable {
    /// Trois dernieres secondes : 3, 2, 1.
    case countdown(secondsRemaining: Int)
    /// Fin du repos.
    case finished
}

/// Decide quand vibrer pendant un repos. Chaque signal ne part qu'une fois
/// par repos ; apres une suspension (poignet baisse), seuls le signal
/// courant part — jamais une rafale de signaux rates.
struct RestHapticTracker: Equatable, Sendable {
    static let countdownSeconds = 3
    /// Au-dela, la fin est passee depuis trop longtemps pour vibrer.
    static let lateFinishTolerance: TimeInterval = 10

    private var restEndsAt: Date?
    private var lastFiredSecond: Int?
    private var finishedFired = false

    init() {}

    mutating func cues(at now: Date, restEndsAt: Date?) -> [RestHapticCue] {
        if restEndsAt != self.restEndsAt {
            // Nouveau repos, ±15 s ou repos passe : on repart de zero.
            self.restEndsAt = restEndsAt
            lastFiredSecond = nil
            finishedFired = false
        }
        guard let restEndsAt else { return [] }

        let remaining = restEndsAt.timeIntervalSince(now)
        if remaining <= 0 {
            guard !finishedFired else { return [] }
            finishedFired = true
            lastFiredSecond = 0
            return -remaining <= Self.lateFinishTolerance ? [.finished] : []
        }

        let second = Int(remaining.rounded(.up))
        guard second <= Self.countdownSeconds else { return [] }
        if let lastFiredSecond, second >= lastFiredSecond { return [] }
        lastFiredSecond = second
        return [.countdown(secondsRemaining: second)]
    }
}

// MARK: - Prochaine seance, pour demarrer et pour le mode autonome

/// Exercice de la prochaine seance, envoye a la montre pour qu'elle
/// enregistre sous son VRAI nom quand l'iPhone est injoignable.
struct WatchPlannedExercise: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var name: String
    var setCount: Int
    /// Charge proposee (kg), `nil` si inconnue.
    var weightKilograms: Double?
    /// Repetitions visees (haut de fourchette), `nil` si inconnues.
    var reps: Int?
}

/// Ce que la montre sait de la prochaine seance.
struct WatchPlanSummary: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version: Int
    var sessionName: String?
    var programName: String?
    var exercises: [WatchPlannedExercise]
    /// Sante active et autorisee dans Muscu sur l'iPhone.
    var healthEnabled: Bool
    var massUnitSymbol: String

    init(
        version: Int = WatchPlanSummary.currentVersion,
        sessionName: String? = nil,
        programName: String? = nil,
        exercises: [WatchPlannedExercise] = [],
        healthEnabled: Bool = false,
        massUnitSymbol: String = "kg"
    ) {
        self.version = version
        self.sessionName = sessionName
        self.programName = programName
        self.exercises = exercises
        self.healthEnabled = healthEnabled
        self.massUnitSymbol = massUnitSymbol
    }

    static let empty = WatchPlanSummary()
}

// MARK: - Seance Sante tenue par la montre

/// Commande Sante envoyee par le telephone a la montre hote.
enum WatchHealthCommand: Codable, Equatable, Sendable {
    /// La seance Muscu est terminee : terminer, enregistrer et relier.
    case finish(activeWorkoutId: UUID, completedSessionId: UUID, endDate: Date)
    /// La seance Muscu est abandonnee : rien n'est enregistre.
    case discard(activeWorkoutId: UUID)
    /// « Reprendre plus tard » / reprise du deroule.
    case pause(activeWorkoutId: UUID)
    case resume(activeWorkoutId: UUID)
}

/// Cardio mesure par la montre (valeurs agregees, `nil` = non mesure).
struct WatchCardio: Codable, Equatable, Sendable {
    var averageHeartRate: Double?
    var minimumHeartRate: Double?
    var maximumHeartRate: Double?
    var activeEnergyKilocalories: Double?
}

/// Reponse de la montre a une demande de fin : l'entrainement est
/// enregistre dans Sante (`workoutIdentifier`), ou rien ne l'a ete (`nil` :
/// pas de seance Sante sur la montre, enregistrement refuse) — l'iPhone
/// ecrit alors la seance apres coup, sans attendre.
struct WatchHealthResult: Codable, Equatable, Sendable {
    var activeWorkoutId: UUID
    var completedSessionId: UUID
    var workoutIdentifier: String?
    var cardio: WatchCardio
}

/// Mesures en direct de la montre, affichees sur l'iPhone.
struct WatchLiveMetrics: Codable, Equatable, Sendable {
    var activeWorkoutId: UUID
    var heartRate: Double?
    var activeEnergyKilocalories: Double?
}

// MARK: - Encodage

/// Encodage des messages : JSON (dates ISO 8601) dans un `Data`, sous une
/// cle par type. Un message illisible est ignore, jamais interprete.
enum WatchMessageCodec {
    static func encode<Value: Encodable>(_ value: Value) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(value)
    }

    static func decode<Value: Decodable>(_ type: Value.Type, from data: Data?) -> Value? {
        guard let data else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }

    /// Message pret a envoyer : `[cle: Data]`.
    static func message<Value: Encodable>(_ value: Value, key: String) -> [String: Any]? {
        encode(value).map { [key: $0] }
    }
}

/// Sequence strictement croissante des etats pousses par le telephone,
/// meme apres une relance (base sur l'horloge, jamais en arriere).
struct WatchMirrorSequence: Sendable {
    private(set) var last: Int

    init(last: Int = 0) {
        self.last = last
    }

    mutating func next(now: Date = .now) -> Int {
        let candidate = Int((now.timeIntervalSince1970 * 1_000).rounded(.down))
        last = max(last + 1, candidate)
        return last
    }
}

// MARK: - Seance Sante a la montre

/// Que doit faire la montre de sa seance Sante quand elle recoit l'etat de
/// l'iPhone ? Pure : la regle « une seule seance Sante, celle que l'iPhone
/// a confiee a la montre » (decision 0017) vue du poignet.
enum WatchHealthPlanner {
    enum Action: Equatable, Sendable {
        case none
        /// Demarrer la seance Sante de cette seance Muscu (seance demarree
        /// depuis la montre).
        case start(UUID)
        /// Une seance Sante tourne deja, lancee par l'iPhone
        /// (`startWatchApp`) avant que la montre ne sache laquelle : on
        /// l'y rattache.
        case associate(UUID)
    }

    /// - Parameters:
    ///   - isRecording: une seance Sante tourne sur la montre.
    ///   - recordingWorkoutId: la seance Muscu qu'elle suit, `nil` si elle
    ///     n'est pas encore rattachee.
    ///   - closedWorkoutIds: seances deja terminees ou abandonnees a la
    ///     montre — jamais redemarrees par un etat en retard.
    static func action(
        for state: WatchMirrorState,
        isRecording: Bool,
        recordingWorkoutId: UUID?,
        closedWorkoutIds: Set<UUID>
    ) -> Action {
        guard state.hasWorkout,
              state.healthHost == .watch,
              state.healthEnabled,
              let id = state.activeWorkoutId,
              !closedWorkoutIds.contains(id) else { return .none }
        if isRecording {
            return recordingWorkoutId == nil ? .associate(id) : .none
        }
        return .start(id)
    }
}
