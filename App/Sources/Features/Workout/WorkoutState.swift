import Foundation
import SwiftData
import MuscuEngine

// Phase de la seance : echauffement (avant le premier exercice, toujours
// propose) puis deroule normal. Persistee sur ActiveWorkout pour survivre a
// un kill+resume pendant l'echauffement lui-meme.
enum RunnerPhase: String, Codable {
    case warmup
    case running
}

// Coordinateur de la seance en cours.
//
// Tout le sequencement (quelle serie, quel tour, quel exercice, quel repos)
// est delegue a `MuscuEngine.WorkoutStateMachine`, pure et testable. Cette
// classe ne fait que trois choses :
//   1. construire le deroule (`WorkoutPlan`) depuis la seance de programme ;
//   2. persister chaque validation AVANT tout avancement visuel ;
//   3. exposer les suggestions qui dependent de l'historique SwiftData.
@Observable
@MainActor
final class WorkoutState: Identifiable {
    // Identifiable pour presenter le runner via fullScreenCover(item:) :
    // la forme isPresented + contenu conditionnel "if let" peut evaluer le
    // contenu avant que le @State optionnel soit visible et presenter un
    // cover vide (ecran noir constate le 20/07).
    let id = UUID()
    let programSession: ProgramSession
    let modelContext: ModelContext
    let catalogStore: CatalogStore
    let restTimer: RestTimer

    private(set) var plan: WorkoutPlan
    private(set) var position: WorkoutPosition
    let startedAt: Date
    private(set) var phase: RunnerPhase
    private(set) var runtimeState: WorkoutRuntimeState

    private(set) var activeWorkout: ActiveWorkout?

    init(
        programSession: ProgramSession,
        modelContext: ModelContext,
        catalogStore: CatalogStore,
        restTimer: RestTimer
    ) {
        self.programSession = programSession
        self.modelContext = modelContext
        self.catalogStore = catalogStore
        self.restTimer = restTimer
        self.plan = WorkoutPlanBuilder.plan(
            for: programSession,
            catalogStore: catalogStore,
            customExercises: (try? modelContext.fetch(FetchDescriptor<CustomExercise>())) ?? []
        )
        self.startedAt = .now
        self.position = .start
        self.activeWorkout = nil
        self.runtimeState = WorkoutRuntimeState()
        // L'echauffement est toujours propose au demarrage (plus de reglage
        // par seance) : WarmupView offre elle-meme "Commencer directement la
        // seance" pour le passer. Une seance reprise (restoring:) preserve
        // sa phase persistee et ne repasse jamais par ici.
        self.phase = .warmup
        _ = createActiveWorkout()
        if !PersistenceSupport.save(modelContext, action: "Démarrage de la séance") {
            activeWorkout = nil
        }
        configureRestTimer()
    }

    private init(
        programSession: ProgramSession,
        modelContext: ModelContext,
        catalogStore: CatalogStore,
        restTimer: RestTimer,
        restoring activeWorkout: ActiveWorkout
    ) {
        // Priorite au snapshot du deroule persiste sur l'ActiveWorkout :
        // sans lui, un kill+resume reconstruirait le deroule depuis la
        // ProgramSession source et perdrait les mutations faites pendant la
        // seance (ajout/retrait de serie, remplacement d'exercice), ce qui
        // desynchroniserait la position deja persistee du contenu reel.
        let restoredPlan: WorkoutPlan
        if let data = activeWorkout.planData,
           let decoded = try? JSONDecoder().decode(WorkoutPlan.self, from: data),
           !decoded.isEmpty {
            restoredPlan = decoded
        } else if let legacyData = activeWorkout.runExercisesData,
                  let legacy = LegacyRunExercise.plan(from: legacyData) {
            // Seance commencee avant le deroule unifie.
            restoredPlan = legacy
        } else {
            restoredPlan = WorkoutPlanBuilder.plan(
                for: programSession,
                catalogStore: catalogStore,
                customExercises: (try? modelContext.fetch(FetchDescriptor<CustomExercise>())) ?? []
            )
        }

        // La position est reclampee par la machine a etats : elle reste
        // valide meme si le snapshot est absent et que le programme source a
        // change depuis, ou si la donnee persistee est corrompue.
        let restoredPosition: WorkoutPosition
        if let data = activeWorkout.positionData,
           let decoded = try? JSONDecoder().decode(WorkoutPosition.self, from: data) {
            restoredPosition = decoded
        } else {
            // Ancienne seance : les index plats designaient l'exercice et la
            // serie, ce qui correspond exactement a un deroule sans groupe.
            restoredPosition = WorkoutPosition(
                nodeIndex: activeWorkout.exerciseIndex,
                setIndex: activeWorkout.setIndex
            )
        }

        self.programSession = programSession
        self.modelContext = modelContext
        self.catalogStore = catalogStore
        self.restTimer = restTimer
        self.startedAt = activeWorkout.startedAt
        self.activeWorkout = activeWorkout
        self.plan = restoredPlan
        self.position = WorkoutStateMachine.clamp(restoredPosition, in: restoredPlan)
        self.phase = RunnerPhase(rawValue: activeWorkout.phaseRaw) ?? .running
        self.runtimeState = activeWorkout.runtimeStateData
            .flatMap { try? JSONDecoder().decode(WorkoutRuntimeState.self, from: $0) }
            ?? WorkoutRuntimeState()
        configureRestTimer()
        if let endDate = runtimeState.restEndDate, runtimeState.restTotalSeconds > 0 {
            restTimer.restore(endDate: endDate, totalSeconds: runtimeState.restTotalSeconds)
        }
    }

    // MARK: - Reprise

    // A appeler au lancement de l'app : au plus une ActiveWorkout doit exister.
    static func pendingActiveWorkout(modelContext: ModelContext) -> ActiveWorkout? {
        let descriptor = FetchDescriptor<ActiveWorkout>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        return (try? modelContext.fetch(descriptor))?.first
    }

    // Reconstruit l'etat depuis une ActiveWorkout persistee. Si la ProgramSession
    // source n'existe plus (programme supprime entre-temps), l'ActiveWorkout est
    // abandonnee proprement et la fonction retourne nil.
    static func resume(
        from activeWorkout: ActiveWorkout,
        modelContext: ModelContext,
        catalogStore: CatalogStore,
        restTimer: RestTimer
    ) -> WorkoutState? {
        let programs = (try? modelContext.fetch(FetchDescriptor<Program>())) ?? []
        guard let session = programs.flatMap(\.sessions).first(where: { $0.id == activeWorkout.programSessionId }) else {
            modelContext.delete(activeWorkout)
            _ = PersistenceSupport.save(modelContext, action: "Nettoyage de la séance interrompue")
            return nil
        }
        return WorkoutState(
            programSession: session,
            modelContext: modelContext,
            catalogStore: catalogStore,
            restTimer: restTimer,
            restoring: activeWorkout
        )
    }

    // MARK: - Etat courant

    /// Etape a afficher, decidee par la machine a etats et par elle seule.
    var currentStep: WorkoutStep {
        WorkoutStateMachine.step(at: position, in: plan)
    }

    var currentTarget: WorkoutSetTarget? {
        guard case .logSet(let target) = currentStep else { return nil }
        return target
    }

    /// Exercice en cours, quel que soit son format.
    var currentExercise: WorkoutExercisePlan? {
        switch currentStep {
        case .logSet(let target): return target.exercise
        case .timedBlock(let exercise): return exercise
        case .finished: return nil
        }
    }

    var isSessionComplete: Bool {
        WorkoutStateMachine.isFinished(position, in: plan)
    }

    var exercises: [WorkoutExercisePlan] { plan.allExercises }

    /// Avancement en creneaux valides / total, pour un libelle honnete.
    var progress: (completed: Int, total: Int) {
        WorkoutStateMachine.progress(at: position, in: plan)
    }

    /// Noeud courant, pour afficher la vue d'ensemble d'un groupe.
    var currentNode: WorkoutNode? {
        let clamped = WorkoutStateMachine.clamp(position, in: plan)
        guard clamped.nodeIndex < plan.nodes.count else { return nil }
        return plan.nodes[clamped.nodeIndex]
    }

    // Series deja loggees pour cette seance, triees exercice puis serie.
    var loggedSets: [CompletedSet] {
        (activeWorkout?.loggedSets ?? []).sorted {
            ($0.orderIndex, $0.roundIndex, $0.setIndex, $0.subSetIndex)
                < ($1.orderIndex, $1.roundIndex, $1.setIndex, $1.subSetIndex)
        }
    }

    // MARK: - Suggestions

    // %1RM + record connu -> charge de travail calculee ; %1RM sans record ->
    // nil (la vue doit demander le 1RM, cf. needsOneRepMax) ; sinon dernier
    // poids logge pour cet exercice. Le poids cible du programme (mode
    // libre) est prioritaire sur cette suggestion mais gere au niveau de
    // l'appelant, pas ici : suggestedWeight reste la logique %1RM/dernier-log
    // pure, reutilisee ailleurs (objectif, echauffement).
    func suggestedWeight(for exercise: WorkoutExercisePlan) -> Double? {
        if let percent = exercise.percentOneRepMax {
            // oneRepMax <= 0 (jamais renseigne, valeur par defaut) compte
            // comme "pas de record" : pas de charge calculable.
            guard let oneRepMax = fetchRecord(exerciseId: exercise.exerciseId)?.oneRepMax, oneRepMax > 0 else {
                return nil
            }
            return OneRepMax.workingLoad(oneRepMax: oneRepMax, percent: percent)
        }
        if let progressed = progressiveOverloadWeight(for: exercise) {
            return progressed
        }
        return lastLoggedWeight(for: exercise.exerciseId)
    }

    /// Charge proposee pour la saisie en cours, paliers de dropset compris :
    /// un palier part de la charge du palier precedent, jamais de la charge
    /// de depart.
    func prefillWeight(for target: WorkoutSetTarget) -> Double {
        let base = target.exercise.targetWeight ?? suggestedWeight(for: target.exercise) ?? 0
        guard target.isSubSet, target.exercise.format == .dropset, let dropset = target.exercise.dropset else {
            return base
        }
        let startingWeight = lastMainSetWeight(for: target) ?? base
        let loads = dropset.loads(startingFrom: startingWeight, increment: availableIncrement())
        let index = target.subSetIndex - 1
        return index < loads.count ? loads[index] : base
    }

    func needsOneRepMax(for exercise: WorkoutExercisePlan) -> Bool {
        guard let percent = exercise.percentOneRepMax, percent > 0 else { return false }
        let oneRepMax = fetchRecord(exerciseId: exercise.exerciseId)?.oneRepMax
        return oneRepMax == nil || oneRepMax! <= 0
    }

    // Enregistre (ou met a jour) le 1RM connu pour cet exercice, saisi
    // directement ou estime depuis une performance recente.
    func saveOneRepMax(_ value: Double, for exercise: WorkoutExercisePlan) {
        guard value > 0, value.isFinite else { return }
        if let record = fetchRecord(exerciseId: exercise.exerciseId) {
            record.oneRepMax = value
            record.updatedAt = .now
        } else {
            let record = ExerciseRecord(exerciseId: exercise.exerciseId, displayName: exercise.displayName, oneRepMax: value)
            modelContext.insert(record)
        }
        _ = PersistenceSupport.save(modelContext, action: "Enregistrement du 1RM")
    }

    // % du max de reps (exercices au poids du corps) : reps cible = percent x
    // max de reps connu, arrondi. Sans record, la vue doit demander le max de
    // reps (cf. needsMaxReps), meme cheminement que needsOneRepMax/%1RM.
    func suggestedReps(for exercise: WorkoutExercisePlan) -> Int? {
        guard let percent = exercise.percentMaxReps else { return nil }
        guard let maxReps = fetchRecord(exerciseId: exercise.exerciseId)?.maxReps, maxReps > 0 else { return nil }
        return Int((percent / 100.0 * Double(maxReps)).rounded())
    }

    func needsMaxReps(for exercise: WorkoutExercisePlan) -> Bool {
        guard let percent = exercise.percentMaxReps, percent > 0 else { return false }
        let maxReps = fetchRecord(exerciseId: exercise.exerciseId)?.maxReps
        return maxReps == nil || maxReps! <= 0
    }

    // Enregistre (ou met a jour) le max de reps connu pour cet exercice.
    func saveMaxReps(_ value: Int, for exercise: WorkoutExercisePlan) {
        guard value > 0 else { return }
        if let record = fetchRecord(exerciseId: exercise.exerciseId) {
            record.maxReps = value
            record.updatedAt = .now
        } else {
            let record = ExerciseRecord(exerciseId: exercise.exerciseId, displayName: exercise.displayName, maxReps: value)
            modelContext.insert(record)
        }
        _ = PersistenceSupport.save(modelContext, action: "Enregistrement du maximum de répétitions")
    }

    // "La dernière fois : 4x8 @ 72,5 kg" depuis la CompletedSession la plus
    // recente contenant cet exercice.
    func lastPerformance(for exercise: WorkoutExercisePlan) -> String? {
        guard let session = lastCompletedSession(containing: exercise.exerciseId) else { return nil }
        let matching = session.sets
            .filter { $0.exerciseId == exercise.exerciseId }
            .sorted { $0.setIndex < $1.setIndex }
        guard !matching.isEmpty, let lastSet = matching.last else { return nil }

        let repsCounts = Dictionary(grouping: matching, by: \.reps).mapValues(\.count)
        let modeReps = repsCounts.max { $0.value < $1.value }?.key ?? lastSet.reps

        return "La dernière fois : \(matching.count)x\(modeReps) @ \(Self.formatWeight(lastSet.weight)) kg"
    }

    // MARK: - Actions

    /// Valide la serie en cours puis demande a la machine a etats ou aller.
    /// La serie est persistee AVANT tout avancement visuel : en cas d'echec
    /// d'ecriture, la position ne bouge pas.
    func logSet(
        weight: Double,
        reps: Int,
        effort: EffortRating? = nil,
        reachedFailure: Bool = false,
        notes: String = "",
        stopsSubSets: Bool = false,
        role: SetRole = .working
    ) {
        guard let target = currentTarget, weight >= 0, weight.isFinite, reps > 0 else { return }
        let exercise = target.exercise
        let resolvedLoadKind = ExerciseClassification.resolvedLoadKind(base: exercise.loadKind, enteredWeight: weight)

        insertCompletedSet(
            target: target,
            weight: weight,
            reps: reps,
            loadKind: resolvedLoadKind,
            role: role,
            effort: effort ?? exercise.targetEffort,
            reachedFailure: reachedFailure,
            notes: notes
        )

        // Une serie d'echauffement, d'approche ou de back-off S'AJOUTE a la
        // prescription : elle est enregistree, mais la serie prevue reste a
        // faire. Sans cela, ajouter une approche ferait sauter une serie de
        // travail sans que rien ne le dise.
        guard role.consumesPrescribedSet else {
            _ = PersistenceSupport.save(modelContext, action: "Enregistrement d’une série supplémentaire")
            return
        }

        advance(outcome: WorkoutSetOutcome(reps: reps, weightKilograms: weight, stopsSubSets: stopsSubSets))
    }

    /// Un palier de pyramide : meme cheminement que `logSet`, mais les
    /// repetitions seules sont saisies (poids du corps).
    func logPyramidStep(reps: Int) {
        guard let target = currentTarget, target.exercise.format == .pyramid else { return }
        logSet(weight: 0, reps: reps)
    }

    // Un bloc d'intervalles / EMOM / AMRAP / For Time = une seule saisie.
    func logTimedBlock(totalReps: Int, durationSeconds: Int? = nil) {
        guard case .timedBlock(let exercise) = currentStep else { return }
        let clamped = WorkoutStateMachine.clamp(position, in: plan)
        let target = WorkoutSetTarget(
            exercise: exercise,
            groupId: currentNode?.id ?? exercise.id,
            groupKind: currentNode?.kind ?? .single,
            round: clamped.round + 1,
            totalRounds: currentNode?.effectiveRounds ?? 1,
            memberPosition: clamped.memberIndex + 1,
            totalMembers: currentNode?.exercises.count ?? 1,
            setNumber: clamped.setIndex + 1,
            totalSets: 1,
            subSetIndex: 0,
            targetRepsLower: 0,
            targetRepsUpper: 0
        )
        insertCompletedSet(
            target: target,
            weight: 0,
            reps: totalReps,
            loadKind: .bodyweight,
            durationSeconds: durationSeconds
        )
        switch exercise.format {
        case .intervals, .emom: runtimeState.interval = nil
        case .amrap: runtimeState.amrap = nil
        case .forTime: runtimeState.forTime = nil
        default: break
        }
        advance(outcome: WorkoutSetOutcome(reps: totalReps))
    }

    // MARK: - Echauffement

    // Premier exercice classique de la seance pour lequel une charge de
    // travail est calculable ET suffisante pour justifier une montee en
    // charge (cf. Warmup.rampSets, qui retourne [] sous 30 kg).
    func warmupTargetExercise() -> WorkoutExercisePlan? {
        exercises.first { exercise in
            guard exercise.format == .classic, let weight = suggestedWeight(for: exercise) else { return false }
            return !Warmup.rampSets(workingWeight: weight).isEmpty
        }
    }

    func warmupRampSets() -> [WarmupSet] {
        guard let target = warmupTargetExercise(), let weight = suggestedWeight(for: target) else { return [] }
        return Warmup.rampSets(workingWeight: weight)
    }

    // Loggee avec le role "warmup", sur l'index reel du futur exercice cible.
    func logWarmupSet(_ warmupSet: WarmupSet, rampIndex: Int) {
        guard let target = warmupTargetExercise(),
              let targetIndex = exercises.firstIndex(where: { $0.id == target.id }) else { return }
        // Idempotent : un kill+resume en pleine echauffement restaure
        // checkedRamps depuis loggedSets (cf. WarmupView.onAppear), mais on
        // se protege ici aussi contre un double-log du meme palier (meme
        // orderIndex+setIndex+role), source de doublons dans l'historique.
        let alreadyLogged = loggedSets.contains {
            $0.role == .warmup && $0.orderIndex == targetIndex && $0.setIndex == rampIndex
        }
        guard !alreadyLogged else { return }
        insertCompletedSet(
            exerciseId: target.exerciseId,
            displayName: target.displayName,
            orderIndex: targetIndex,
            setIndex: rampIndex,
            weight: warmupSet.weight,
            reps: warmupSet.reps,
            role: .warmup,
            loadKind: ExerciseClassification.resolvedLoadKind(base: target.loadKind, enteredWeight: warmupSet.weight),
            format: target.format
        )
        _ = PersistenceSupport.save(modelContext, action: "Enregistrement de l’échauffement")
    }

    // Passe en phase normale, que l'echauffement ait ete fait entierement,
    // partiellement ou pas du tout ("Passer l'échauffement" a tout moment).
    func finishWarmup() {
        phase = .running
        runtimeState.warmup = WarmupRuntimeState()
        guard let workout = activeWorkout else { return }
        workout.phaseRaw = RunnerPhase.running.rawValue
        persistRuntimeState(action: "Fin de l’échauffement")
    }

    func updateWarmupRuntime(_ value: WarmupRuntimeState) {
        runtimeState.warmup = value
        persistRuntimeState(action: "Progression de l’échauffement")
    }

    func updateIntervalRuntime(_ value: IntervalRuntimeState?) {
        runtimeState.interval = value
        persistRuntimeState(action: "Progression des intervalles")
    }

    func updateAmrapRuntime(_ value: AmrapRuntimeState?) {
        runtimeState.amrap = value
        persistRuntimeState(action: "Progression de l’AMRAP")
    }

    func updateForTimeRuntime(_ value: ForTimeRuntimeState?) {
        runtimeState.forTime = value
        persistRuntimeState(action: "Progression du For Time")
    }

    // 1RM maxReps connu pour cet exercice ; a defaut, une valeur plausible
    // deduite de la pyramide elle-meme (jamais 0, sinon adaptiveRest
    // retomberait a tort sur minRest a chaque palier).
    func pyramidMaxReps(for exercise: WorkoutExercisePlan) -> Int {
        if let maxReps = fetchRecord(exerciseId: exercise.exerciseId)?.maxReps, maxReps > 0 {
            return maxReps
        }
        let fallback = (exercise.pyramidReps.max() ?? 1) * 2
        return max(1, fallback)
    }

    func skipExercise() {
        let previous = position
        position = WorkoutStateMachine.skipExercise(from: position, in: plan)
        if !persistPosition(action: "Progression de la séance") { position = previous }
    }

    /// Revient a la serie precedente pour la corriger, tant que la seance
    /// n'est pas finalisee. La serie loggee correspondante est supprimee :
    /// elle sera re-saisie, sans jamais laisser de doublon dans l'historique.
    func stepBack() {
        guard let previous = previousPosition(), let removed = lastWorkingSet() else { return }
        let savedPosition = position
        position = previous
        modelContext.delete(removed)
        if !persistPosition(action: "Correction de la dernière série") {
            position = savedPosition
        }
    }

    var canStepBack: Bool { previousPosition() != nil }

    /// Se deplace vers un autre exercice de la seance (apercu). Aucune serie
    /// deja enregistree n'est supprimee : on change seulement de place.
    func moveTo(position newPosition: WorkoutPosition) {
        let previous = position
        position = WorkoutStateMachine.clamp(newPosition, in: plan)
        if !persistPosition(action: "Navigation dans la séance") { position = previous }
    }

    // Remplace l'exercice courant pour cette seance uniquement : ne touche
    // jamais a la PrescribedExercise du programme. exerciseId peut designer
    // un exercice du catalogue ou un CustomExercise (son UUID en String).
    func replaceExercise(exerciseId: String, displayName: String) {
        let clamped = WorkoutStateMachine.clamp(position, in: plan)
        guard clamped.nodeIndex < plan.nodes.count,
              clamped.memberIndex < plan.nodes[clamped.nodeIndex].exercises.count else { return }
        let previous = plan
        var exercise = plan.nodes[clamped.nodeIndex].exercises[clamped.memberIndex]
        let replacedId = exercise.exerciseId
        exercise.exerciseId = exerciseId
        exercise.displayName = displayName
        exercise.loadKind = resolvedLoadKind(forExerciseId: exerciseId)
        plan.nodes[clamped.nodeIndex].exercises[clamped.memberIndex] = exercise
        substitutions[exercise.id] = replacedId
        if !persistPlan(action: "Modification de la séance") { plan = previous }
    }

    func addSet() {
        let clamped = WorkoutStateMachine.clamp(position, in: plan)
        guard clamped.nodeIndex < plan.nodes.count else { return }
        let previous = plan
        if plan.nodes[clamped.nodeIndex].isGroup {
            plan.nodes[clamped.nodeIndex].rounds += 1
        } else {
            guard clamped.memberIndex < plan.nodes[clamped.nodeIndex].exercises.count else { return }
            plan.nodes[clamped.nodeIndex].exercises[clamped.memberIndex].setCount += 1
        }
        if !persistPlan(action: "Modification de la séance") { plan = previous }
    }

    // "Retirer une série" ne doit jamais faire descendre le nombre de series
    // en dessous du nombre de series deja realisees pour l'exercice courant,
    // ni en dessous de 1 : sinon la position se retrouverait clampee sur une
    // serie deja loggee, et la prochaine validation persisterait un setIndex
    // DUPLIQUE. Si la serie retiree etait justement celle en attente de
    // saisie, on avance comme si elle venait d'etre validee.
    func removeSet() {
        let clamped = WorkoutStateMachine.clamp(position, in: plan)
        guard clamped.nodeIndex < plan.nodes.count else { return }
        let previousPlan = plan
        let previousPosition = position
        let node = plan.nodes[clamped.nodeIndex]

        if node.isGroup {
            let minimumRounds = max(1, clamped.round + (clamped.memberIndex > 0 ? 1 : 0))
            plan.nodes[clamped.nodeIndex].rounds = max(minimumRounds, node.rounds - 1)
        } else {
            guard clamped.memberIndex < node.exercises.count else { return }
            let minimumSets = max(1, clamped.setIndex)
            let current = node.exercises[clamped.memberIndex].setCount
            plan.nodes[clamped.nodeIndex].exercises[clamped.memberIndex].setCount = max(minimumSets, current - 1)
        }

        // La machine a etats decide seule si la position reste valide ou si
        // l'exercice est maintenant termine.
        let reclamped = WorkoutStateMachine.clamp(position, in: plan)
        let isExhausted = node.isGroup
            ? reclamped.round >= plan.nodes[clamped.nodeIndex].rounds
            : reclamped.setIndex >= plan.nodes[clamped.nodeIndex].exercises[clamped.memberIndex].setCount
        position = isExhausted
            ? WorkoutStateMachine.skipExercise(from: reclamped, in: plan)
            : reclamped

        if !persistPlan(action: "Modification de la séance") {
            plan = previousPlan
            position = previousPosition
        }
    }

    // "Abandonner" : supprime la seance en cours et les series deja loggees
    // (cascade sur ActiveWorkout.loggedSets). Rien n'est ecrit a l'historique.
    func discard() {
        guard let workout = activeWorkout else { return }
        modelContext.delete(workout)
        if PersistenceSupport.save(modelContext, action: "Abandon de la séance") {
            activeWorkout = nil
            // Abandonner doit faire disparaitre la Live Activity : la laisser
            // sur l'ecran verrouille apres une seance abandonnee serait un
            // defaut visible sans meme ouvrir l'application.
            Task { await WorkoutActivityController.end() }
        }
    }

    // Fin de seance : bascule les series loggees vers une CompletedSession
    // (historique), supprime l'ActiveWorkout, sauvegarde.
    func finish() -> CompletedSession? {
        let duration = Int(Date.now.timeIntervalSince(startedAt))
        let completedSession = CompletedSession(
            date: .now,
            programId: programSession.program?.id,
            programSessionId: programSession.id,
            programName: programSession.program?.name ?? "",
            sessionName: programSession.name,
            durationSeconds: duration,
            bodyweightKilograms: knownBodyweightKilograms()
        )
        modelContext.insert(completedSession)

        let workoutToDelete = activeWorkout
        if let workout = workoutToDelete {
            for set in workout.loggedSets {
                set.activeWorkout = nil
                set.session = completedSession
                completedSession.sets.append(set)
            }
            workout.loggedSets.removeAll()
            modelContext.delete(workout)
        }

        guard PersistenceSupport.save(modelContext, action: "Finalisation de la séance") else {
            return nil
        }
        activeWorkout = nil
        Task { await WorkoutActivityController.end() }
        return completedSession
    }

    // MARK: - Prive

    /// Exercice prevu avant substitution, par identifiant de prescription.
    /// L'historique conserve prevu ET realise (cf. CompletedSet.plannedExerciseId).
    private var substitutions: [UUID: String] = [:]

    /// Avance la position apres une validation, persiste, puis lance le repos
    /// decide par la machine a etats. Aucun repos n'est lance si la seance est
    /// terminee.
    private func advance(outcome: WorkoutSetOutcome) {
        let previousPosition = position
        let result = WorkoutStateMachine.advance(from: position, in: plan, outcome: outcome)
        position = result.position

        if let workout = activeWorkout {
            workout.positionData = try? JSONEncoder().encode(position)
            workout.exerciseIndex = position.nodeIndex
            workout.setIndex = position.setIndex
            workout.runtimeStateData = try? JSONEncoder().encode(runtimeState)
        }
        guard PersistenceSupport.save(modelContext, action: "Enregistrement de la série") else {
            position = previousPosition
            return
        }

        if !isSessionComplete, let rest = result.rest, rest.seconds > 0 {
            restTimer.start(seconds: rest.seconds)
        }

        refreshLiveActivity()
    }

    /// Etat courant publie sur la Live Activity. Rien de plus que ce que
    /// l'ecran affiche deja.
    func liveActivityState() -> WorkoutActivityState {
        let target = currentTarget
        return WorkoutActivityState(
            exerciseName: target?.exercise.displayName ?? currentExercise?.displayName ?? programSession.name,
            setNumber: target?.setNumber ?? 0,
            totalSets: target?.totalSets ?? 0,
            restEndsAt: restTimer.isRunning ? restTimer.endDate : nil,
            completedSets: loggedSets.filter { $0.role.countsAsWorkingSet }.count
        )
    }

    func startLiveActivity() {
        WorkoutActivityController.start(
            sessionName: programSession.name,
            state: liveActivityState()
        )
    }

    func refreshLiveActivity() {
        guard WorkoutActivityController.isRunning else { return }
        let state = liveActivityState()
        Task { await WorkoutActivityController.update(state) }
    }

    @discardableResult
    private func persistPosition(action: String) -> Bool {
        guard let workout = activeWorkout else { return false }
        workout.positionData = try? JSONEncoder().encode(position)
        workout.exerciseIndex = position.nodeIndex
        workout.setIndex = position.setIndex
        return PersistenceSupport.save(modelContext, action: action)
    }

    // Persiste le snapshot du deroule ET la position dans la meme
    // sauvegarde, afin qu'une modification de seance reste atomique.
    @discardableResult
    private func persistPlan(action: String) -> Bool {
        guard let workout = activeWorkout else { return false }
        do {
            workout.planData = try JSONEncoder().encode(plan)
            workout.positionData = try JSONEncoder().encode(position)
            workout.exerciseIndex = position.nodeIndex
            workout.setIndex = position.setIndex
            return PersistenceSupport.save(modelContext, action: action)
        } catch {
            PersistenceSupport.report(error, action: action)
            return false
        }
    }

    /// Position de la derniere serie REELLEMENT enregistree, ou `nil` si
    /// rien n'a encore ete valide dans cette seance.
    ///
    /// Elle est reconstruite depuis la serie elle-meme plutot qu'en rejouant
    /// la machine a etats : rejouer supposerait de connaitre les resultats
    /// saisis, dont depend la sortie des blocs a sous-series (rest-pause,
    /// myo-reps). La serie enregistree, elle, porte sa position exacte.
    private func previousPosition() -> WorkoutPosition? {
        guard let last = lastWorkingSet() else { return nil }
        // L'index d'ordre de la serie designe sa place dans le deroule ; on
        // retombe sur l'identifiant d'exercice si le deroule a change depuis
        // (remplacement d'exercice pendant la seance).
        let exercise = exercises.indices.contains(last.orderIndex)
            ? exercises[last.orderIndex]
            : exercises.first(where: { $0.exerciseId == last.exerciseId })
        guard let exercise else { return nil }

        for (nodeIndex, node) in plan.nodes.enumerated() {
            guard let memberIndex = node.exercises.firstIndex(where: { $0.id == exercise.id }) else { continue }
            return WorkoutPosition(
                nodeIndex: nodeIndex,
                round: last.roundIndex,
                memberIndex: memberIndex,
                setIndex: last.setIndex,
                subSetIndex: last.subSetIndex
            )
        }
        return nil
    }

    /// Derniere serie de travail REELLEMENT saisie. On se fie au rang de
    /// saisie et jamais a l'ordre d'affichage : dans un superset, les series
    /// sont affichees groupees par exercice, ce qui n'est pas l'ordre dans
    /// lequel elles ont ete faites.
    private func lastWorkingSet() -> CompletedSet? {
        (activeWorkout?.loggedSets ?? [])
            .filter { $0.role.countsAsWorkingSet }
            .max { $0.sequenceIndex < $1.sequenceIndex }
    }

    /// Rang de saisie suivant dans cette seance.
    private func nextSequenceIndex() -> Int {
        ((activeWorkout?.loggedSets ?? []).map(\.sequenceIndex).max() ?? -1) + 1
    }

    private func insertCompletedSet(
        target: WorkoutSetTarget,
        weight: Double,
        reps: Int,
        loadKind: LoadKind,
        role: SetRole = .working,
        effort: EffortRating? = nil,
        reachedFailure: Bool = false,
        notes: String = "",
        durationSeconds: Int? = nil
    ) {
        let orderIndex = exercises.firstIndex { $0.id == target.exercise.id } ?? 0
        insertCompletedSet(
            exerciseId: target.exercise.exerciseId,
            displayName: target.exercise.displayName,
            orderIndex: orderIndex,
            setIndex: target.setNumber - 1,
            weight: weight,
            reps: reps,
            role: role,
            loadKind: loadKind,
            format: target.exercise.format,
            groupId: target.groupKind == .single ? nil : target.groupId,
            roundIndex: target.round - 1,
            subSetIndex: target.subSetIndex,
            side: target.exercise.side,
            tempo: target.exercise.tempo,
            effort: effort,
            reachedFailure: reachedFailure,
            notes: notes,
            durationSeconds: durationSeconds,
            plannedExerciseId: substitutions[target.exercise.id] ?? ""
        )
    }

    // Insere un CompletedSet et le rattache a l'ActiveWorkout courante
    // (creee au besoin, paresseusement). Ne fait ni avancer la position ni
    // sauvegarder : cf. `advance(outcome:)` pour la suite d'une validation,
    // et `logWarmupSet` pour l'echauffement (qui sauvegarde lui-meme).
    private func insertCompletedSet(
        exerciseId: String,
        displayName: String,
        orderIndex: Int,
        setIndex: Int,
        weight: Double,
        reps: Int,
        role: SetRole,
        loadKind: LoadKind,
        format: WorkoutFormat,
        groupId: UUID? = nil,
        roundIndex: Int = 0,
        subSetIndex: Int = 0,
        side: SideConvention = .bilateral,
        tempo: Tempo? = nil,
        effort: EffortRating? = nil,
        reachedFailure: Bool = false,
        notes: String = "",
        durationSeconds: Int? = nil,
        plannedExerciseId: String = ""
    ) {
        let newSet = CompletedSet(
            exerciseId: exerciseId,
            displayName: displayName,
            orderIndex: orderIndex,
            setIndex: setIndex,
            weight: weight,
            reps: reps,
            isWarmup: role == .warmup,
            loadTypeRaw: ExerciseLoadType(loadKind: loadKind).rawValue,
            roleRaw: role.rawValue,
            sideConventionRaw: side.rawValue,
            tempoNotation: tempo?.notation ?? "",
            effortData: effort.flatMap { try? JSONEncoder().encode($0) },
            notes: notes,
            reachedFailure: reachedFailure,
            groupId: groupId,
            roundIndex: roundIndex,
            subSetIndex: subSetIndex,
            durationSeconds: durationSeconds,
            plannedExerciseId: plannedExerciseId,
            formatRaw: SetFormat(rawValue: format.rawValue)?.rawValue ?? SetFormat.classic.rawValue,
            sequenceIndex: nextSequenceIndex()
        )
        modelContext.insert(newSet)
        let workout = activeWorkout ?? createActiveWorkout()
        newSet.activeWorkout = workout
        workout.loggedSets.append(newSet)
    }

    private func configureRestTimer() {
        restTimer.onStateChange = { [weak self] endDate, totalSeconds in
            guard let self else { return }
            self.runtimeState.restEndDate = endDate
            self.runtimeState.restTotalSeconds = totalSeconds
            self.persistRuntimeState(action: "Chronomètre de repos")
        }
    }

    private func persistRuntimeState(action: String) {
        guard let workout = activeWorkout else { return }
        do {
            workout.runtimeStateData = try JSONEncoder().encode(runtimeState)
            _ = PersistenceSupport.save(modelContext, action: action)
        } catch {
            PersistenceSupport.report(error, action: action)
        }
    }

    private func createActiveWorkout() -> ActiveWorkout {
        let workout = ActiveWorkout(
            startedAt: startedAt,
            programSessionId: programSession.id,
            exerciseIndex: position.nodeIndex,
            setIndex: position.setIndex,
            phaseRaw: phase.rawValue,
            runtimeStateData: try? JSONEncoder().encode(runtimeState),
            planData: try? JSONEncoder().encode(plan),
            positionData: try? JSONEncoder().encode(position)
        )
        modelContext.insert(workout)
        activeWorkout = workout
        return workout
    }

    private func fetchRecord(exerciseId: String) -> ExerciseRecord? {
        let descriptor = FetchDescriptor<ExerciseRecord>(predicate: #Predicate { $0.exerciseId == exerciseId })
        return try? modelContext.fetch(descriptor).first
    }

    private func resolvedLoadKind(forExerciseId exerciseId: String) -> LoadKind {
        if let catalogExercise = catalogStore.exercise(id: exerciseId) {
            return ExerciseClassification.loadKind(for: catalogExercise)
        }
        let customExercises = (try? modelContext.fetch(FetchDescriptor<CustomExercise>())) ?? []
        if let custom = customExercises.first(where: { $0.id.uuidString == exerciseId }) {
            return custom.defaultLoadKind
        }
        return .unknown
    }

    /// Increment de chargement disponible pour cet athlete, utilise par les
    /// paliers de dropset. Valeur par defaut du profil a defaut de reglage.
    private func availableIncrement() -> Double {
        guard let profile = ProfileStore.currentProfile(in: modelContext) else { return 2.5 }
        return profile.nearestAvailableIncrement(to: 2.5)
    }

    /// Charge de la serie principale du palier en cours, pour enchainer les
    /// baisses d'un dropset depuis la charge reellement soulevee.
    private func lastMainSetWeight(for target: WorkoutSetTarget) -> Double? {
        loggedSets.last {
            $0.exerciseId == target.exercise.exerciseId
                && $0.subSetIndex == 0
                && $0.setIndex == target.setNumber - 1
                && $0.roundIndex == target.round - 1
        }?.weight
    }

    private func lastLoggedWeight(for exerciseId: String) -> Double? {
        let descriptor = FetchDescriptor<CompletedSet>(
            predicate: #Predicate { $0.exerciseId == exerciseId && $0.session != nil }
        )
        guard let sets = try? modelContext.fetch(descriptor), !sets.isEmpty else { return nil }
        let sorted = sets.sorted { lhs, rhs in
            let lhsDate = lhs.session?.date ?? .distantPast
            let rhsDate = rhs.session?.date ?? .distantPast
            if lhsDate != rhsDate { return lhsDate > rhsDate }
            return lhs.setIndex > rhs.setIndex
        }
        return sorted.first?.weight
    }

    private func knownBodyweightKilograms() -> Double? {
        ProfileStore.latestBodyweightKilograms(in: modelContext)
    }

    /// Progression double simple et prudente : lorsque toutes les series de
    /// travail de la derniere seance ont atteint le haut de la fourchette,
    /// la prochaine saisie propose un palier de 2,5 kg. Aucune progression
    /// automatique pour le poids du corps, l'assiste ou les prescriptions
    /// pilotees par un pourcentage de 1RM.
    private func progressiveOverloadWeight(for exercise: WorkoutExercisePlan) -> Double? {
        guard exercise.format == .classic,
              exercise.percentOneRepMax == nil,
              exercise.repsUpper > 0,
              exercise.loadKind == .external,
              let session = lastCompletedSession(containing: exercise.exerciseId) else { return nil }
        let sets = session.sets.filter {
            $0.role.countsAsWorkingSet && $0.exerciseId == exercise.exerciseId && $0.weight > 0
        }
        guard sets.count >= max(1, exercise.setCount),
              sets.allSatisfy({ $0.reps >= exercise.repsUpper }),
              let lastWeight = sets.max(by: { $0.setIndex < $1.setIndex })?.weight else { return nil }
        return ((lastWeight + availableIncrement()) * 2).rounded() / 2
    }

    private func lastCompletedSession(containing exerciseId: String) -> CompletedSession? {
        let descriptor = FetchDescriptor<CompletedSession>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        guard let sessions = try? modelContext.fetch(descriptor) else { return nil }
        return sessions.first { session in session.sets.contains { $0.exerciseId == exerciseId } }
    }

    /// Conservee comme point d'appel historique des vues du runner ; la
    /// mise en forme elle-meme vit dans `WeightFormatter`, utilisable hors
    /// du fil principal.
    static func formatWeight(_ weight: Double) -> String {
        WeightFormatter.number(weight)
    }
}
