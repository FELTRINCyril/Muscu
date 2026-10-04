import Foundation
import SwiftData
import MuscuEngine

/// Construit et pousse a la montre l'etat de la seance en cours (lot 7).
///
/// L'etat reprend EXACTEMENT ce que montre la Live Activity
/// (`liveActivityState`) : un seul calcul, donc la montre, l'ecran
/// verrouille et l'application ne peuvent pas se contredire. Il est pousse
/// a chaque transition (serie validee, repos lance, passe ou prolonge,
/// echauffement termine, fin, abandon).
@MainActor
enum WatchMirrorPublisher {
    private static let sequenceKey = "watch.mirror.sequence"

    /// Sequence strictement croissante, conservee d'un lancement a l'autre.
    static func nextSequence(now: Date = .now) -> Int {
        var sequence = WatchMirrorSequence(last: UserDefaults.standard.integer(forKey: sequenceKey))
        let next = sequence.next(now: now)
        UserDefaults.standard.set(next, forKey: sequenceKey)
        return next
    }

    static func state(for workout: WorkoutState, sequence: Int? = nil) -> WatchMirrorState {
        let unit = ProfileStore.massUnit(in: workout.modelContext)
        let healthEnabled = LiveHealthWorkoutController.isAllowedForWatch(store: AppServices.healthStore)
        guard !workout.isClosed, let activeWorkoutId = workout.activeWorkout?.id else {
            return .idle(sequence: sequence ?? nextSequence(), massUnitSymbol: unit.symbol, healthEnabled: healthEnabled)
        }

        let phase: WatchMirrorState.Phase
        if workout.phase == .warmup {
            phase = .warmup
        } else if workout.isSessionComplete {
            phase = .awaitingFinish
        } else if workout.currentTarget == nil {
            phase = .needsPhone
        } else {
            phase = .running
        }

        // Valeurs proposees : celles que la Live Activity validerait d'un
        // tap. Une serie qui demande une saisie n'en a pas.
        let proposal = phase == .running ? workout.quickLogProposal() : nil
        return WatchMirrorState(
            sequence: sequence ?? nextSequence(),
            phase: phase,
            activeWorkoutId: activeWorkoutId,
            sessionName: workout.sessionTitle,
            startedAt: workout.startedAt,
            activity: workout.liveActivityState(),
            plannedWeightKilograms: proposal?.weightKilograms,
            plannedReps: proposal?.reps,
            isBodyweight: workout.currentTarget?.exercise.loadKind == .bodyweight,
            massUnitSymbol: unit.symbol,
            healthHost: LiveHealthWorkoutController.shared.watchHealthHost(forActiveWorkoutId: activeWorkoutId),
            healthEnabled: healthEnabled
        )
    }

    static func publish(_ workout: WorkoutState) {
        guard let connectivity = PhoneConnectivityService.shared else { return }
        connectivity.publishMirror(state(for: workout))
    }

    /// Plus de seance en cours : la montre revient a son accueil.
    static func publishIdle() {
        guard let connectivity = PhoneConnectivityService.shared else { return }
        connectivity.publishMirror(idleState())
    }

    static func idleState() -> WatchMirrorState {
        let unit = LiveWorkoutActions.modelContext.map { ProfileStore.massUnit(in: $0) } ?? .kilograms
        return .idle(
            sequence: nextSequence(),
            massUnitSymbol: unit.symbol,
            healthEnabled: LiveHealthWorkoutController.isAllowedForWatch(store: AppServices.healthStore)
        )
    }

    /// Etat courant : la seance en memoire, sinon la seance persistee
    /// reprise comme au lancement, sinon l'accueil.
    static func currentState() -> WatchMirrorState {
        guard let workout = LiveWorkoutActions.currentState() else { return idleState() }
        return state(for: workout)
    }

    // MARK: - Prochaine seance

    /// Prochaine seance du programme actif — celle que demarre le bouton
    /// « Commencer » de l'accueil — et ses exercices, pour que la montre
    /// enregistre sous leur vrai nom quand l'iPhone est injoignable.
    static func planSummary(in context: ModelContext) -> WatchPlanSummary {
        let unit = ProfileStore.massUnit(in: context)
        let healthEnabled = LiveHealthWorkoutController.isAllowedForWatch(store: AppServices.healthStore)
        guard let session = nextProgramSession(in: context) else {
            return WatchPlanSummary(healthEnabled: healthEnabled, massUnitSymbol: unit.symbol)
        }
        let plan = WorkoutPlanBuilder.plan(for: session)
        let exercises = plan.nodes
            .flatMap(\.exercises)
            .enumerated()
            .map { index, exercise in
                WatchPlannedExercise(
                    id: "\(index)-\(exercise.exerciseId)",
                    name: exercise.displayName,
                    setCount: max(1, exercise.setCount),
                    // Charge du programme seulement : une charge inconnue
                    // reste inconnue, jamais zero.
                    weightKilograms: exercise.targetWeight.flatMap { $0 > 0 ? $0 : nil },
                    reps: exercise.repsUpper > 0 ? exercise.repsUpper : nil
                )
            }
        return WatchPlanSummary(
            sessionName: session.name,
            programName: session.program?.name,
            exercises: exercises,
            healthEnabled: healthEnabled,
            massUnitSymbol: unit.symbol
        )
    }

    /// Meme regle que la carte de l'accueil (`HomeView.nextSession`).
    static func nextProgramSession(in context: ModelContext) -> ProgramSession? {
        let programs = ((try? context.fetch(FetchDescriptor<Program>())) ?? []).filter { $0.deletedAt == nil }
        guard let program = programs.first(where: \.isActive) else { return nil }
        let completed = (try? context.fetch(FetchDescriptor<CompletedSession>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        ))) ?? []
        return HomeView.nextSession(for: program, completedSessions: completed)
    }
}

/// Execute les commandes de la montre, par le MEME chemin que les boutons de
/// l'application et de la Live Activity (`LiveWorkoutActions`).
@MainActor
enum WatchCommandHandler {
    static func handle(_ envelope: WatchCommandEnvelope) async -> WatchCommandReply {
        let workout = LiveWorkoutActions.currentState()
        let context = commandContext(for: workout)

        switch WatchCommandPolicy.evaluate(envelope, in: context) {
        case .reject(let rejection):
            if workout == nil { await WorkoutActivityController.endOrphans() }
            return reply(to: envelope, rejection: rejection, workout: workout)
        case .perform:
            break
        }

        switch envelope.command {
        case .requestState:
            return reply(to: envelope, rejection: nil, workout: workout)
        case .startNext, .startFree:
            return await start(envelope)
        case .logSet(let slotKey, let weight, let reps):
            guard let workout else { return reply(to: envelope, rejection: .noWorkout, workout: nil) }
            // Echec d'ecriture : la position n'a pas bouge, rien n'est valide.
            let logged = workout.logAdjustedSet(slotKey: slotKey, weightKilograms: weight, reps: reps)
            await workout.refreshLiveActivityNow()
            return reply(to: envelope, rejection: logged ? nil : .saveFailed, workout: workout)
        case .skipRest:
            workout?.restTimer.skip()
        case .extendRest:
            workout?.restTimer.addThirtySeconds()
        case .finishWarmup:
            workout?.finishWarmup()
        }
        if let workout { await workout.refreshLiveActivityNow() }
        return reply(to: envelope, rejection: nil, workout: workout)
    }

    static func commandContext(for workout: WorkoutState?) -> WatchCommandContext {
        let hasNext = LiveWorkoutActions.modelContext.map { WatchMirrorPublisher.nextProgramSession(in: $0) != nil } ?? false
        guard let workout, !workout.isClosed, workout.activeWorkout != nil else {
            return WatchCommandContext(
                activeWorkoutId: nil,
                phase: .idle,
                slotKey: "",
                canQuickLog: false,
                isResting: false,
                canExtendRest: false,
                hasNextSession: hasNext
            )
        }
        let state = WatchMirrorPublisher.state(for: workout, sequence: 0)
        let now = Date.now
        return WatchCommandContext(
            activeWorkoutId: state.activeWorkoutId,
            phase: state.phase,
            slotKey: state.activity?.slotKey ?? "",
            canQuickLog: state.canLogFromWatch,
            isResting: state.activity.map { $0.restPhase(at: now) != .none } ?? false,
            canExtendRest: state.activity?.canExtendRest(at: now) ?? false,
            hasNextSession: hasNext
        )
    }

    /// Demarre la seance demandee a la montre, exactement comme les boutons
    /// de l'accueil (sans l'ecran de preparation : le check-in reste
    /// facultatif). La montre enregistre alors la seance Sante elle-meme.
    private static func start(_ envelope: WatchCommandEnvelope) async -> WatchCommandReply {
        guard let workout = LiveWorkoutActions.startWorkout(free: envelope.command == .startFree) else {
            return reply(
                to: envelope,
                rejection: envelope.command == .startFree ? .saveFailed : .noNextSession,
                workout: nil
            )
        }
        if let id = workout.activeWorkout?.id,
           HealthWorkoutCoordination.hostForWatchStart(
               healthAllowed: LiveHealthWorkoutController.isAllowedForWatch(store: AppServices.healthStore)
           ) == .watch {
            LiveHealthWorkoutController.shared.adoptWatchHost(activeWorkoutId: id)
        }
        // L'accueil, s'il est affiche, presente aussitot le deroule.
        IntentRouter.shared.request(.resumeWorkout)
        await workout.refreshLiveActivityNow()
        return reply(to: envelope, rejection: nil, workout: workout)
    }

    private static func reply(
        to envelope: WatchCommandEnvelope,
        rejection: WatchCommandRejection?,
        workout: WorkoutState?
    ) -> WatchCommandReply {
        let state = workout.map { WatchMirrorPublisher.state(for: $0) } ?? WatchMirrorPublisher.idleState()
        return WatchCommandReply(commandId: envelope.id, rejection: rejection, state: state)
    }
}
