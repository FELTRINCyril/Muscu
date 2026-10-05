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
    /// Seance de programme a l'origine de la seance. `nil` pour une seance
    /// libre, demarree sans programme.
    let programSession: ProgramSession?
    /// Seance libre : les exercices sont ajoutes au fil de l'eau, et c'est
    /// l'utilisateur qui decide de la fin (un deroule epuise n'est pas une
    /// seance terminee : il attend l'exercice suivant).
    let isFreeSession: Bool
    let modelContext: ModelContext
    let catalogStore: CatalogStore
    let restTimer: RestTimer

    private(set) var plan: WorkoutPlan
    private(set) var position: WorkoutPosition
    let startedAt: Date
    private(set) var phase: RunnerPhase
    private(set) var runtimeState: WorkoutRuntimeState

    private(set) var activeWorkout: ActiveWorkout?

    /// Fin demandee explicitement (seance libre). Volatile : apres une
    /// reprise, la seance libre attend de nouveau un exercice ou la fin.
    private(set) var endRequested = false

    /// Seance terminee ou abandonnee : plus aucune serie ne peut s'y
    /// ajouter (une saisie tardive recreerait une seance fantome).
    private(set) var isClosed = false

    /// Terminee ou abandonnee HORS du deroule (Siri, Raccourcis) : le
    /// deroule affiche, s'il l'est, doit se fermer.
    private(set) var endedOutsideRunner = false

    /// Mise a l'echelle de la semaine de plan appliquee au demarrage. Elle
    /// est conservee pour que l'ecran de preparation et le runner puissent la
    /// DIRE : alleger une seance sans le signaler serait une modification
    /// silencieuse.
    let weekScaling: WeekScaling

    init(
        programSession: ProgramSession,
        modelContext: ModelContext,
        catalogStore: CatalogStore,
        restTimer: RestTimer,
        weekScaling: WeekScaling? = nil
    ) {
        self.programSession = programSession
        self.isFreeSession = false
        self.modelContext = modelContext
        self.catalogStore = catalogStore
        self.restTimer = restTimer
        let scaling = weekScaling ?? WeekScalingResolver.scaling(
            for: programSession,
            context: modelContext
        )
        self.weekScaling = scaling
        // La mise a l'echelle est appliquee UNE FOIS, ici, puis figee dans le
        // snapshot persiste : une seance de decharge reprise apres un arret
        // reste une seance de decharge.
        self.plan = scaling.applied(
            to: WorkoutPlanBuilder.plan(
                for: programSession,
                catalogStore: catalogStore,
                customExercises: (try? modelContext.fetch(FetchDescriptor<CustomExercise>())) ?? []
            )
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
        // Structure de depart, figee : la fin de seance la compare au
        // deroule final pour proposer de mettre le programme a jour.
        self.runtimeState.structureBaseline = SessionStructureDiff.entries(of: plan)
        _ = createActiveWorkout()
        if !PersistenceSupport.save(modelContext, action: "Démarrage de la séance") {
            activeWorkout = nil
        }
        configureRestTimer()
        LiveWorkoutRegistry.shared.register(self)
    }

    /// Seance libre : aucun programme, un deroule vide auquel les exercices
    /// s'ajoutent au fil de l'eau. Pas d'echauffement guide : il n'y a pas
    /// encore d'exercice sur lequel le calculer.
    ///
    /// `replaying` preremplit le deroule (« Refaire » une seance de
    /// l'historique) ; la seance reste libre : elle ne se termine que sur
    /// demande et accepte d'autres exercices.
    init(
        freeSessionWith modelContext: ModelContext,
        catalogStore: CatalogStore,
        restTimer: RestTimer,
        replaying plan: WorkoutPlan = WorkoutPlan(nodes: []),
        title: String? = nil
    ) {
        self.programSession = nil
        self.isFreeSession = true
        self.modelContext = modelContext
        self.catalogStore = catalogStore
        self.restTimer = restTimer
        self.weekScaling = .neutral
        self.plan = plan
        self.startedAt = .now
        self.position = .start
        self.activeWorkout = nil
        var runtimeState = WorkoutRuntimeState()
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        runtimeState.title = trimmedTitle?.isEmpty == false ? trimmedTitle : nil
        self.runtimeState = runtimeState
        self.phase = .running
        _ = createActiveWorkout()
        if !PersistenceSupport.save(modelContext, action: "Démarrage de la séance libre") {
            activeWorkout = nil
        }
        configureRestTimer()
        LiveWorkoutRegistry.shared.register(self)
    }

    private init(
        programSession: ProgramSession?,
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
           !decoded.isEmpty || programSession == nil {
            // Une seance libre peut legitimement avoir un deroule vide.
            restoredPlan = decoded
        } else if let programSession {
            if let legacyData = activeWorkout.runExercisesData,
               let legacy = LegacyRunExercise.plan(from: legacyData) {
                // Seance commencee avant le deroule unifie.
                restoredPlan = legacy
            } else {
                // Dernier recours : le deroule est reconstruit depuis la
                // seance source. Il faut donc RE-appliquer la mise a
                // l'echelle, sinon une seance de decharge reprise apres perte
                // du snapshot reviendrait silencieusement au volume plein.
                restoredPlan = WeekScalingResolver
                    .scaling(for: programSession, context: modelContext)
                    .applied(
                        to: WorkoutPlanBuilder.plan(
                            for: programSession,
                            catalogStore: catalogStore,
                            customExercises: (try? modelContext.fetch(FetchDescriptor<CustomExercise>())) ?? []
                        )
                    )
            }
        } else {
            // Seance libre sans instantane lisible (archive, synchronisation) :
            // le deroule est reconstruit depuis les series deja enregistrees,
            // les exercices restants sont a rajouter.
            restoredPlan = Self.freeSessionPlan(rebuiltFrom: activeWorkout.loggedSets)
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
        self.isFreeSession = programSession == nil
        self.modelContext = modelContext
        self.catalogStore = catalogStore
        self.restTimer = restTimer
        self.startedAt = activeWorkout.startedAt
        self.activeWorkout = activeWorkout
        // Le deroule restaure porte DEJA la mise a l'echelle : on ne la
        // reapplique pas, on la retient seulement pour pouvoir la dire.
        self.weekScaling = programSession.map {
            WeekScalingResolver.scaling(for: $0, context: modelContext)
        } ?? .neutral
        self.plan = restoredPlan
        self.position = WorkoutStateMachine.clamp(restoredPosition, in: restoredPlan)
        self.phase = RunnerPhase(rawValue: activeWorkout.phaseRaw) ?? .running
        self.runtimeState = Self.decodeRuntimeState(activeWorkout.runtimeStateData)
        configureRestTimer()
        if let endDate = runtimeState.restEndDate, runtimeState.restTotalSeconds > 0 {
            restTimer.restore(endDate: endDate, totalSeconds: runtimeState.restTotalSeconds)
        }
        LiveWorkoutRegistry.shared.register(self)
    }

    /// Deroule d'une seance libre reconstruit depuis ses series : un
    /// exercice seul par exercice rencontre, dans l'ordre des series. Les
    /// index d'ordre des series sont renumerotes sur ce deroule, sinon un
    /// exercice ajoute ensuite partagerait l'index d'un exercice deja fait.
    private static func freeSessionPlan(rebuiltFrom sets: [CompletedSet]) -> WorkoutPlan {
        let byOrder = Dictionary(grouping: sets, by: \.orderIndex)
        var nodes: [WorkoutNode] = []
        for (newIndex, orderIndex) in byOrder.keys.sorted().enumerated() {
            let group = byOrder[orderIndex] ?? []
            guard let first = group.first else { continue }
            let working = group.filter { $0.role.consumesPrescribedSet }
            nodes.append(.single(WorkoutExercisePlan(
                exerciseId: first.exerciseId,
                displayName: first.displayName,
                loadKind: first.loadType.loadKind,
                setCount: max(1, (working.map(\.setIndex).max() ?? 0) + 1)
            )))
            for set in group { set.orderIndex = newIndex }
        }
        return WorkoutPlan(nodes: nodes)
    }

    // MARK: - Reprise

    // A appeler au lancement de l'app : au plus une ActiveWorkout doit exister.
    static func pendingActiveWorkout(modelContext: ModelContext) -> ActiveWorkout? {
        let descriptor = FetchDescriptor<ActiveWorkout>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        return (try? modelContext.fetch(descriptor))?.first
    }

    /// Reprise depuis l'interface ou depuis un bouton de la Live Activity :
    /// la meme seance est peut-etre deja en memoire (reprise en
    /// arriere-plan par un bouton, ou « Reprendre plus tard »). La
    /// reconstruire ferait coexister deux coordinateurs — et deux chronos —
    /// pour une seule seance ; on reprend donc celui qui existe.
    static func resumeOrAdopt(
        from activeWorkout: ActiveWorkout,
        modelContext: ModelContext,
        catalogStore: CatalogStore,
        restTimer: RestTimer
    ) -> WorkoutState? {
        if let live = LiveWorkoutRegistry.shared.state(for: activeWorkout, in: modelContext) {
            return live
        }
        return resume(from: activeWorkout, modelContext: modelContext, catalogStore: catalogStore, restTimer: restTimer)
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
        if activeWorkout.isFreeSession {
            return WorkoutState(
                programSession: nil,
                modelContext: modelContext,
                catalogStore: catalogStore,
                restTimer: restTimer,
                restoring: activeWorkout
            )
        }
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

    /// Seance terminee, prete pour le recapitulatif. Pour une seance libre,
    /// seule la demande explicite de l'utilisateur la termine.
    var isSessionComplete: Bool {
        isFreeSession ? endRequested : isPlanExhausted
    }

    /// Plus aucun exercice a derouler. Une seance libre dans cet etat attend
    /// le prochain exercice.
    var isPlanExhausted: Bool {
        WorkoutStateMachine.isFinished(position, in: plan)
    }

    /// Titre de la seance : nom de la seance de programme, ou « Séance
    /// libre ».
    var sessionTitle: String {
        programSession?.name ?? runtimeState.title ?? Self.freeSessionTitle
    }

    // MARK: - Structure et programme

    /// Ce qui a change dans la STRUCTURE de la seance par rapport a la seance
    /// du programme au demarrage : exercices ajoutes, retires, remplaces,
    /// deplaces, nombre de series, mesure. Vide pour une seance libre, une
    /// seance reprise d'avant cette fonction, ou si rien n'a change.
    var structureChanges: [SessionStructureChange] {
        guard programSession != nil, let baseline = runtimeState.structureBaseline else { return [] }
        return SessionStructureDiff.changes(baseline: baseline, final: SessionStructureDiff.entries(of: plan))
    }

    /// Structure de depart, pour reporter les ecarts dans le programme.
    var structureBaseline: [SessionStructureEntry]? { runtimeState.structureBaseline }

    static var freeSessionTitle: String { String(localized: "Séance libre") }

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

    /// Repetitions proposees pour la serie : objectif en % du maximum de
    /// repetitions, sinon haut puis bas de la fourchette. `nil` si aucune
    /// n'est connue — jamais un 1 invente.
    func proposedReps(for target: WorkoutSetTarget) -> Int? {
        if let targetReps = suggestedReps(for: target.exercise) {
            return targetReps > 0 ? targetReps : nil
        }
        if target.targetRepsUpper > 0 { return target.targetRepsUpper }
        return target.targetRepsLower > 0 ? target.targetRepsLower : nil
    }

    /// Repetitions pre-remplies dans la saisie. Le champ doit partir d'une
    /// valeur valide : a defaut de mieux, 1, que l'utilisateur corrige.
    func prefillReps(for target: WorkoutSetTarget) -> Int {
        if let targetReps = suggestedReps(for: target.exercise) { return targetReps }
        return proposedReps(for: target) ?? 1
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

    // MARK: - Historique de l'exercice en direct

    /// Seance passee reduite a ce que le deroule affiche pour UN exercice.
    struct ExerciseHistorySession {
        let id: UUID
        let date: Date
        let programSessionId: UUID?
        let sets: [HistoricalSet]
    }

    /// Historique par exercice, lu une fois par seance : il ne change pas
    /// pendant la seance (les series en cours ne sont rattachees a une
    /// `CompletedSession` qu'a la fin). Ignore par l'observation : le
    /// remplir pendant le calcul d'une vue ne doit pas la redessiner.
    @ObservationIgnored private var historyCache: [String: [ExerciseHistorySession]] = [:]

    /// Seances terminees contenant cet exercice, de la plus recente a la
    /// plus ancienne, series de travail principales uniquement.
    func history(forExerciseId exerciseId: String) -> [ExerciseHistorySession] {
        if let cached = historyCache[exerciseId] { return cached }
        let descriptor = FetchDescriptor<CompletedSet>(
            predicate: #Predicate { $0.exerciseId == exerciseId && $0.session != nil }
        )
        let sets: [CompletedSet]
        do {
            sets = try modelContext.fetch(descriptor)
        } catch {
            DiagnosticsCenter.record(.store, code: "workout.history.fetchFailed", error: error)
            return []
        }
        var bySession: [UUID: (session: CompletedSession, sets: [HistoricalSet])] = [:]
        for set in sets {
            guard let session = set.session, session.deletedAt == nil, set.deletedAt == nil else { continue }
            let historical = HistoricalSet(
                weightKilograms: set.weight,
                reps: set.reps,
                isPrescribedWorkingSet: set.role == .working,
                orderIndex: set.orderIndex,
                roundIndex: set.roundIndex,
                setIndex: set.setIndex,
                subSetIndex: set.subSetIndex,
                sequenceIndex: set.sequenceIndex
            )
            bySession[session.id, default: (session, [])].sets.append(historical)
        }
        let result = bySession.values
            .map { entry in
                ExerciseHistorySession(
                    id: entry.session.id,
                    date: entry.session.date,
                    programSessionId: entry.session.programSessionId,
                    sets: PreviousPerformance.workingSets(entry.sets)
                )
            }
            .filter { !$0.sets.isEmpty }
            .sorted { $0.date > $1.date }
        historyCache[exerciseId] = result
        return result
    }

    /// Ce qui a ete fait a la MEME serie de travail lors de la derniere
    /// seance comparable : la derniere de cette seance de programme si
    /// l'exercice y figurait, sinon la derniere tout court. Rien pour un
    /// palier de dropset ou une mini-serie : ils n'ont pas de rang propre.
    func previousSet(for target: WorkoutSetTarget) -> HistoricalSet? {
        guard !target.isSubSet else { return nil }
        let sessions = history(forExerciseId: target.exercise.exerciseId)
        let comparable = programSession.flatMap { current in
            sessions.first { $0.programSessionId == current.id }
        } ?? sessions.first
        guard let comparable else { return nil }
        let rank = PreviousPerformance.workingRank(
            round: target.round,
            setNumber: target.setNumber,
            totalSets: target.totalSets
        )
        return PreviousPerformance.reference(atWorkingRank: rank, in: comparable.sets)
    }

    /// Bandeau des ~10 dernieres seances de l'exercice.
    func previousSessionsStrip(for exercise: WorkoutExercisePlan, now: Date = .now) -> [PreviousSessionsStrip.Entry] {
        let sessions = history(forExerciseId: exercise.exerciseId).prefix(PreviousSessionsStrip.defaultLimit).map { session in
            PreviousSessionsStrip.SessionSets(
                id: session.id,
                date: session.date,
                sets: session.sets.map { .init(weightKilograms: $0.weightKilograms, reps: $0.reps) }
            )
        }
        return PreviousSessionsStrip.entries(from: Array(sessions), now: now)
    }

    /// Exercice a la barre : seul cas ou le calculateur de disques a un sens.
    func usesBarbell(_ exercise: WorkoutExercisePlan) -> Bool {
        RestDefaults.isBarbell(equipment: equipment(forExerciseId: exercise.exerciseId))
    }

    // MARK: - Record en direct

    /// Record battu par la derniere serie validee, a celebrer. N'ecrit
    /// rien : la fin de seance reste la source de verite des records.
    struct LiveRecordCelebration: Identifiable, Equatable {
        let id = UUID()
        let exerciseName: String
        let kind: LiveRecord.Kind
    }

    private(set) var liveRecordCelebration: LiveRecordCelebration?

    /// Ferme la celebration, seulement si c'est encore celle-la : une
    /// fermeture differee ne doit pas emporter une celebration plus recente.
    func dismissLiveRecordCelebration(id: UUID? = nil) {
        guard id == nil || liveRecordCelebration?.id == id else { return }
        liveRecordCelebration = nil
    }

    /// Meilleures valeurs connues AVANT cette seance : record saisi (1RM),
    /// records types non qualifies (1RM estime, charge maximale).
    private func liveRecordBaseline(exerciseId: String) -> LiveRecord.Baseline {
        let bests = ((try? modelContext.fetch(FetchDescriptor<PersonalBest>(
            predicate: #Predicate { $0.exerciseId == exerciseId }
        ))) ?? []).filter { $0.deletedAt == nil && $0.configurationKey.isEmpty }
        let typedOneRepMax = bests.filter { $0.kind == .estimatedOneRepMax }.map(\.value).max()
        let manualOneRepMax = fetchRecord(exerciseId: exerciseId)?.oneRepMax.flatMap { $0 > 0 ? $0 : nil }
        let oneRepMax = [typedOneRepMax, manualOneRepMax].compactMap { $0 }.max()
        let load = bests.filter { $0.kind == .maxWeight }.map(\.value).max()
        return LiveRecord.Baseline(bestEstimatedOneRepMax: oneRepMax, bestLoad: load)
    }

    /// Verifie la serie qui vient d'etre enregistree.
    private func checkLiveRecord(for newSet: CompletedSet) {
        guard newSet.role.countsAsWorkingSet else { return }
        let bodyweight = knownBodyweightKilograms()
        let earlier = loggedSets
            .filter { $0.id != newSet.id && $0.exerciseId == newSet.exerciseId }
            .map { $0.metricsInput(bodyweightKilograms: bodyweight) }
        guard let kind = LiveRecord.celebration(
            for: newSet.metricsInput(bodyweightKilograms: bodyweight),
            earlierThisSession: earlier,
            baseline: liveRecordBaseline(exerciseId: newSet.exerciseId)
        ) else { return }
        liveRecordCelebration = LiveRecordCelebration(exerciseName: newSet.displayName, kind: kind)
        FeedbackSettings.celebrateRecord()
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
        guard !isClosed, let target = currentTarget, weight >= 0, weight.isFinite, reps > 0 else { return }
        let exercise = target.exercise
        // La serie suivante est saisie : le depassement de repos s'arrete.
        restTimer.endOvertime()
        let resolvedLoadKind = ExerciseClassification.resolvedLoadKind(base: exercise.loadKind, enteredWeight: weight)

        let newSet = insertCompletedSet(
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
            if PersistenceSupport.save(modelContext, action: "Enregistrement d’une série supplémentaire") {
                checkLiveRecord(for: newSet)
            }
            return
        }

        // La celebration ne suit qu'une serie REELLEMENT enregistree.
        if advance(outcome: WorkoutSetOutcome(reps: reps, weightKilograms: weight, stopsSubSets: stopsSubSets)) {
            checkLiveRecord(for: newSet)
        }
    }

    /// Un palier de pyramide : meme cheminement que `logSet`, mais les
    /// repetitions seules sont saisies (poids du corps).
    func logPyramidStep(reps: Int) {
        guard let target = currentTarget, target.exercise.format == .pyramid else { return }
        logSet(weight: 0, reps: reps)
    }

    // Un bloc d'intervalles / EMOM / AMRAP / For Time = une seule saisie.
    func logTimedBlock(totalReps: Int, durationSeconds: Int? = nil) {
        guard !isClosed, case .timedBlock(let exercise) = currentStep else { return }
        restTimer.endOvertime()
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
        guard !isClosed, let target = warmupTargetExercise(),
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
        refreshLiveActivity()
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

    /// Palier suivant d'une pyramide, annonce pendant le repos (la position
    /// a deja avance sur lui). `nil` hors pyramide.
    var pyramidUpNext: (step: Int, total: Int, reps: Int)? {
        guard let target = currentTarget, target.exercise.format == .pyramid else { return nil }
        return (target.setNumber, target.totalSets, target.targetRepsLower)
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

    // MARK: - Ajout et ordre des exercices

    /// Ajoute un exercice en fin de seance, pour cette seance uniquement :
    /// le programme n'est jamais modifie. Series classiques, repos par
    /// defaut de son materiel. Dans une seance libre dont le deroule etait
    /// epuise, il devient aussitot l'exercice courant.
    func addExercise(exerciseId: String, displayName: String) {
        let equipment = equipment(forExerciseId: exerciseId)
        let exercise = WorkoutExercisePlan(
            exerciseId: exerciseId,
            displayName: displayName,
            loadKind: resolvedLoadKind(forExerciseId: exerciseId),
            setCount: 3,
            repsLower: 8,
            repsUpper: 12,
            restSeconds: WorkoutSettings.restDefaults.seconds(forEquipment: equipment)
        )
        let previous = plan
        plan = WorkoutPlanEditing.appending(exercise, to: plan)
        if !persistPlan(action: "Ajout d’un exercice") { plan = previous }
        refreshLiveActivity()
    }

    /// Exercices deja commences : au moins une serie enregistree, quel que
    /// soit son role. Une serie dont l'index ne designe plus rien verrouille
    /// par prudence tous les exercices du meme identifiant.
    private var startedExerciseIDs: Set<UUID> {
        let all = exercises
        var started: Set<UUID> = []
        for set in loggedSets {
            if all.indices.contains(set.orderIndex) {
                started.insert(all[set.orderIndex].id)
            } else {
                for exercise in all where exercise.exerciseId == set.exerciseId {
                    started.insert(exercise.id)
                }
            }
        }
        return started
    }

    /// Noeuds restants que l'utilisateur peut reordonner, dans l'ordre.
    var reorderableNodes: [WorkoutNode] {
        WorkoutPlanEditing
            .reorderableNodeIndices(in: plan, position: position, startedExerciseIDs: startedExerciseIDs)
            .map { plan.nodes[$0] }
    }

    /// Reordonne les exercices restants. Les series deja enregistrees sont
    /// renumerotees avec le deroule, dans la meme sauvegarde : un exercice
    /// commence ne bouge pas, mais son index « a plat » peut changer si un
    /// groupe de taille differente passe devant lui.
    @discardableResult
    func reorderRemaining(_ newOrder: [UUID]) -> Bool {
        guard let result = WorkoutPlanEditing.reordering(
            plan,
            position: position,
            startedExerciseIDs: startedExerciseIDs,
            newOrder: newOrder
        ) else { return false }
        let previousPlan = plan
        let previousPosition = position
        let mapping = WorkoutPlanEditing.flatIndexMapping(from: plan, to: result.plan)
        let sets = activeWorkout?.loggedSets ?? []
        let previousIndices = sets.map(\.orderIndex)
        for set in sets {
            if let newIndex = mapping[set.orderIndex] { set.orderIndex = newIndex }
        }
        plan = result.plan
        position = result.position
        guard persistPlan(action: "Ordre des exercices") else {
            plan = previousPlan
            position = previousPosition
            for (set, index) in zip(sets, previousIndices) { set.orderIndex = index }
            return false
        }
        refreshLiveActivity()
        return true
    }

    /// Change ce que mesure l'exercice courant (poids x repetitions, temps,
    /// distance), pour cette seance uniquement. Seul le format classique
    /// porte une mesure.
    func setMeasure(_ measure: SetMeasure) {
        let clamped = WorkoutStateMachine.clamp(position, in: plan)
        guard clamped.nodeIndex < plan.nodes.count,
              clamped.memberIndex < plan.nodes[clamped.nodeIndex].exercises.count,
              plan.nodes[clamped.nodeIndex].exercises[clamped.memberIndex].format == .classic else { return }
        let previous = plan
        var exercise = plan.nodes[clamped.nodeIndex].exercises[clamped.memberIndex]
        exercise.measure = measure == .weightReps ? nil : measure
        if !measure.measuresDuration { exercise.targetDurationSeconds = nil }
        if !measure.measuresDistance { exercise.targetDistanceMeters = nil }
        plan.nodes[clamped.nodeIndex].exercises[clamped.memberIndex] = exercise
        if !persistPlan(action: "Modification de la séance") { plan = previous }
    }

    /// Valide une serie mesuree en temps et / ou en distance. Meme
    /// cheminement que `logSet` : persistance d'abord, avancement ensuite.
    /// La charge eventuelle (lest d'un gainage, charge d'un portage) est
    /// enregistree mais ne produit aucun tonnage : il n'y a pas de
    /// repetitions.
    func logMeasuredSet(
        _ result: MeasuredSetResult,
        weight: Double = 0,
        effort: EffortRating? = nil,
        notes: String = "",
        role: SetRole = .working
    ) {
        guard !isClosed, let target = currentTarget,
              result.isValid(for: target.exercise.effectiveMeasure),
              weight >= 0, weight.isFinite else { return }
        restTimer.endOvertime()
        let exercise = target.exercise
        let loadKind = ExerciseClassification.resolvedLoadKind(base: exercise.loadKind, enteredWeight: weight)
        let newSet = insertCompletedSet(
            target: target,
            weight: weight,
            reps: 0,
            loadKind: loadKind,
            role: role,
            effort: effort ?? exercise.targetEffort,
            notes: notes,
            durationSeconds: result.durationSeconds,
            distanceMeters: result.distanceMeters
        )
        guard role.consumesPrescribedSet else {
            if PersistenceSupport.save(modelContext, action: "Enregistrement d’une série supplémentaire") {
                checkLiveRecord(for: newSet)
            }
            return
        }
        if advance(outcome: WorkoutSetOutcome(reps: 0, weightKilograms: weight)) {
            checkLiveRecord(for: newSet)
        }
    }

    // MARK: - Fin d'une seance libre

    /// Une seance libre ne se termine que sur demande : son deroule epuise
    /// attend l'exercice suivant.
    func requestEnd() {
        guard isFreeSession else { return }
        restTimer.endOvertime()
        restTimer.skip()
        endRequested = true
    }

    /// Annule la demande de fin (retour depuis le recapitulatif, avant
    /// d'avoir termine).
    func cancelEndRequest() {
        endRequested = false
    }

    // "Abandonner" : supprime la seance en cours et les series deja loggees
    // (cascade sur ActiveWorkout.loggedSets). Rien n'est ecrit a l'historique.
    @discardableResult
    func discard(outsideRunner: Bool = false) -> Bool {
        guard let workout = activeWorkout else { return false }
        restTimer.endOvertime()
        modelContext.delete(workout)
        guard PersistenceSupport.save(modelContext, action: "Abandon de la séance") else { return false }
        activeWorkout = nil
        isClosed = true
        endedOutsideRunner = outsideRunner
        // Un repos en cours n'a plus de raison d'etre : sa notification de
        // fin ne doit pas sonner apres l'abandon.
        restTimer.skip()
        LiveWorkoutRegistry.shared.unregister(self)
        // Abandonner doit faire disparaitre la Live Activity : la laisser
        // sur l'ecran verrouille apres une seance abandonnee serait un
        // defaut visible sans meme ouvrir l'application.
        Task { await WorkoutActivityController.end() }
        // Rien n'est enregistre dans Sante pour une seance abandonnee.
        Task { await LiveHealthWorkoutController.shared.discard() }
        // La montre en miroir revient a l'accueil.
        WatchMirrorPublisher.publishIdle()
        return true
    }

    // Fin de seance : bascule les series loggees vers une CompletedSession
    // (historique), supprime l'ActiveWorkout, sauvegarde.
    func finish(effortRating: Int? = nil, outsideRunner: Bool = false) -> CompletedSession? {
        guard !isClosed else { return nil }
        restTimer.endOvertime()
        let duration = Int(Date.now.timeIntervalSince(startedAt))
        // Une seance libre rejoint l'historique comme une autre, sans
        // programme : elle ne fait donc pas avancer la rotation.
        let completedSession = CompletedSession(
            date: .now,
            programId: programSession?.program?.id,
            programSessionId: programSession?.id,
            programName: programSession?.program?.name ?? "",
            sessionName: sessionTitle,
            durationSeconds: duration,
            bodyweightKilograms: knownBodyweightKilograms(),
            effortRating: effortRating.flatMap { SessionEffort.isValid($0) ? $0 : nil }
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
        isClosed = true
        endedOutsideRunner = outsideRunner
        if outsideRunner {
            // Terminee depuis Siri : aucun repos ne doit sonner ensuite.
            restTimer.skip()
        }
        LiveWorkoutRegistry.shared.unregister(self)
        Task { await WorkoutActivityController.end() }
        // La seance Sante en direct, s'il y en a une, sera reliee a cette
        // seance : la synchronisation ne doit plus l'ecrire apres coup.
        LiveHealthWorkoutController.shared.markFinished(completedSessionId: completedSession.id)
        WatchMirrorPublisher.publishIdle()
        return completedSession
    }

    // MARK: - Prive

    /// Exercice prevu avant substitution, par identifiant de prescription.
    /// L'historique conserve prevu ET realise (cf. CompletedSet.plannedExerciseId).
    private var substitutions: [UUID: String] = [:]

    /// Avance la position apres une validation, persiste, puis lance le repos
    /// decide par la machine a etats. Aucun repos n'est lance si la seance est
    /// terminee.
    @discardableResult
    private func advance(outcome: WorkoutSetOutcome) -> Bool {
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
            return false
        }

        if !isSessionComplete, let rest = result.rest, rest.seconds > 0 {
            restTimer.start(seconds: rest.seconds)
        }

        refreshLiveActivity()
        return true
    }

    // MARK: - Live Activity

    /// Serie validable d'un tap depuis la Live Activity, avec les valeurs
    /// que l'ecran de saisie pre-remplit. `nil` des qu'une saisie est
    /// necessaire (echauffement, palier, serie au temps, charge inconnue).
    func quickLogProposal() -> LiveActivityPlanning.SetProposal? {
        guard !isClosed, phase == .running, !isSessionComplete, let target = currentTarget else { return nil }
        let exercise = target.exercise
        return LiveActivityPlanning.quickLogProposal(
            for: target,
            proposedWeightKilograms: exercise.targetWeight ?? suggestedWeight(for: exercise),
            proposedReps: proposedReps(for: target),
            needsReferenceValue: needsOneRepMax(for: exercise) || needsMaxReps(for: exercise)
        )
    }

    /// Identite de la serie affichee : seance, position, nombre de series
    /// deja enregistrees. Elle change des que quoi que ce soit avance.
    var liveActivitySlotKey: String {
        let clamped = WorkoutStateMachine.clamp(position, in: plan)
        return [
            activeWorkout?.id.uuidString ?? "-",
            phase.rawValue,
            "\(clamped.nodeIndex).\(clamped.round).\(clamped.memberIndex).\(clamped.setIndex).\(clamped.subSetIndex)",
            "\(activeWorkout?.loggedSets.count ?? 0)",
        ].joined(separator: "|")
    }

    /// Valide la serie affichee par la Live Activity, par le MEME chemin que
    /// le bouton « Valider la série » de l'ecran de saisie (`logSet`) :
    /// persistance d'abord, repos ensuite, record celebre. Rien n'est fait si
    /// la serie affichee n'est plus la serie courante.
    @discardableResult
    func logProposedSet(slotKey: String) -> Bool {
        guard slotKey == liveActivitySlotKey, let proposal = quickLogProposal() else { return false }
        let before = position
        logSet(weight: proposal.weightKilograms, reps: proposal.reps)
        // Un echec d'ecriture laisse la position en place : rien n'a ete
        // valide, et la Live Activity continue d'afficher la meme serie.
        return position != before
    }

    /// Valide depuis la montre la serie affichee, avec la charge et les
    /// repetitions ajustees a la Digital Crown. Memes gardes que la Live
    /// Activity (identite de serie, serie entierement connue), meme chemin
    /// que l'ecran de saisie (`logSet`).
    @discardableResult
    func logAdjustedSet(slotKey: String, weightKilograms: Double, reps: Int) -> Bool {
        guard slotKey == liveActivitySlotKey, quickLogProposal() != nil else { return false }
        let before = position
        logSet(weight: weightKilograms, reps: reps)
        return position != before
    }

    /// Etat courant publie sur la Live Activity. Rien de plus que ce que
    /// l'ecran de saisie affiche deja.
    func liveActivityState() -> WorkoutActivityState {
        let target = currentTarget
        let unit = ProfileStore.massUnit(in: modelContext)
        let proposal = quickLogProposal()
        let restEnd = restTimer.endDate

        var plannedSetText: String?
        var nextStepText: String?
        if let target, phase == .running {
            let exercise = target.exercise
            let reps = proposedReps(for: target)
            if exercise.effectiveMeasure == .weightReps, let reps {
                let weight = exercise.targetWeight ?? suggestedWeight(for: exercise)
                if let weight, weight > 0 || exercise.loadKind == .bodyweight {
                    plannedSetText = LiveSessionText.set(weightKilograms: weight, reps: reps, unit: unit)
                } else {
                    plannedSetText = String(localized: "\(reps) reps")
                }
            }
            let outcome = WorkoutSetOutcome(
                reps: proposal?.reps ?? reps ?? 0,
                weightKilograms: proposal?.weightKilograms ?? 0
            )
            nextStepText = Self.nextStepText(
                LiveActivityPlanning.nextStep(after: position, in: plan, outcome: outcome),
                isFreeSession: isFreeSession
            )
        }

        return WorkoutActivityState(
            exerciseName: target?.exercise.displayName ?? currentExercise?.displayName ?? sessionTitle,
            setNumber: target?.setNumber ?? 0,
            totalSets: target?.totalSets ?? 0,
            // Conservee pendant le depassement : la Live Activity affiche
            // alors « +0:12 », comme le bandeau de l'application.
            restEndsAt: restEnd,
            completedSets: loggedSets.filter { $0.role.countsAsWorkingSet }.count,
            restStartedAt: restEnd.flatMap { end in
                restTimer.totalSeconds > 0 ? end.addingTimeInterval(-Double(restTimer.totalSeconds)) : nil
            },
            plannedSetText: plannedSetText,
            nextStepText: nextStepText,
            canQuickLog: proposal != nil,
            slotKey: liveActivitySlotKey
        )
    }

    static func nextStepText(_ step: LiveActivityPlanning.NextStep, isFreeSession: Bool) -> String? {
        switch step {
        case .set(let name, let setNumber, let totalSets, let isSameExercise):
            return isSameExercise
                ? String(localized: "Série \(setNumber)/\(totalSets)")
                : String(localized: "\(name) · série \(setNumber)/\(totalSets)")
        case .timedBlock(let name):
            return name
        case .finished:
            // Une seance libre attend l'exercice suivant : elle ne finit
            // que sur demande.
            return isFreeSession ? nil : String(localized: "Fin de la séance")
        }
    }

    func startLiveActivity() {
        WatchMirrorPublisher.publish(self)
        WorkoutActivityController.start(
            sessionName: sessionTitle,
            state: liveActivityState()
        )
    }

    /// Seance Sante en direct (iOS 26+, Sante active et autorisee) : demarree
    /// avec le deroule, reprise s'il etait en pause.
    func startHealthWorkout() {
        guard let id = activeWorkout?.id else { return }
        Task { await LiveHealthWorkoutController.shared.start(activeWorkoutId: id, store: AppServices.healthStore) }
    }

    /// Chaque transition est aussi poussee a la montre (lot 7), que la
    /// Live Activity tourne ou non : le miroir ne depend pas d'ActivityKit.
    func refreshLiveActivity() {
        guard !isClosed else { return }
        WatchMirrorPublisher.publish(self)
        guard WorkoutActivityController.isRunning else { return }
        let state = liveActivityState()
        Task { await WorkoutActivityController.update(state) }
    }

    /// Meme mise a jour, attendue jusqu'au bout : un bouton de la Live
    /// Activity ne rend la main qu'une fois l'ecran verrouille a jour.
    func refreshLiveActivityNow() async {
        guard !isClosed else { return }
        WatchMirrorPublisher.publish(self)
        guard WorkoutActivityController.isRunning else { return }
        await WorkoutActivityController.update(liveActivityState())
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
            let encodedPlan = try JSONEncoder().encode(plan)
            workout.planData = Self.withinSizeLimit(encodedPlan, code: "workout.plan.tooLarge")
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

    @discardableResult
    private func insertCompletedSet(
        target: WorkoutSetTarget,
        weight: Double,
        reps: Int,
        loadKind: LoadKind,
        role: SetRole = .working,
        effort: EffortRating? = nil,
        reachedFailure: Bool = false,
        notes: String = "",
        durationSeconds: Int? = nil,
        distanceMeters: Double? = nil
    ) -> CompletedSet {
        let orderIndex = exercises.firstIndex { $0.id == target.exercise.id } ?? 0
        return insertCompletedSet(
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
            distanceMeters: distanceMeters,
            plannedExerciseId: substitutions[target.exercise.id] ?? ""
        )
    }

    // Insere un CompletedSet et le rattache a l'ActiveWorkout courante
    // (creee au besoin, paresseusement). Ne fait ni avancer la position ni
    // sauvegarder : cf. `advance(outcome:)` pour la suite d'une validation,
    // et `logWarmupSet` pour l'echauffement (qui sauvegarde lui-meme).
    @discardableResult
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
        distanceMeters: Double? = nil,
        plannedExerciseId: String = ""
    ) -> CompletedSet {
        let now = Date.now
        // Repos reel : depuis la validation de la serie precedente de la
        // seance (quelle qu'elle soit), lue AVANT l'insertion.
        let previousSetEnd = (activeWorkout?.loggedSets ?? []).map(\.createdAt).max()
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
            distanceMeters: distanceMeters,
            plannedExerciseId: plannedExerciseId,
            formatRaw: SetFormat(rawValue: format.rawValue)?.rawValue ?? SetFormat.classic.rawValue,
            sequenceIndex: nextSequenceIndex(),
            actualRestSeconds: ActualRest.seconds(
                previousSetEnd: previousSetEnd,
                validatedAt: now,
                currentSetDurationSeconds: durationSeconds
            ),
            createdAt: now,
            updatedAt: now
        )
        modelContext.insert(newSet)
        let workout = activeWorkout ?? createActiveWorkout()
        newSet.activeWorkout = workout
        workout.loggedSets.append(newSet)
        return newSet
    }

    private func configureRestTimer() {
        restTimer.onStateChange = { [weak self] endDate, totalSeconds in
            guard let self else { return }
            self.runtimeState.restEndDate = endDate
            self.runtimeState.restTotalSeconds = totalSeconds
            self.persistRuntimeState(action: "Chronomètre de repos")
        }
    }

    /// Relit l'etat volatil persiste.
    ///
    /// Un echec ici n'est PAS anodin : il fait perdre le chrono de repos et
    /// l'etat AMRAP/intervalle en cours. Il etait auparavant avale par un
    /// `try?`, donc invisible. Il est desormais journalise, ce qui permet de
    /// comprendre apres coup pourquoi une seance est repartie a zero.
    private static func decodeRuntimeState(_ data: Data?) -> WorkoutRuntimeState {
        guard let data else { return WorkoutRuntimeState() }
        do {
            let decoded = try JSONDecoder().decode(WorkoutRuntimeState.self, from: data)
            guard decoded.isReadable else {
                DiagnosticsCenter.record(
                    .store,
                    .warning,
                    code: "workout.runtimeState.tooRecent",
                    detail: "version \(decoded.version)"
                )
                return WorkoutRuntimeState()
            }
            return decoded
        } catch {
            DiagnosticsCenter.record(.store, code: "workout.runtimeState.decodeFailed", error: error)
            return WorkoutRuntimeState()
        }
    }

    /// Taille maximale d'un instantane persiste.
    ///
    /// Une seance normale pese quelques kilo-octets ; au-dela, c'est qu'une
    /// donnee s'emballe. Ecrire sans borne remplirait le store et rendrait la
    /// reprise de plus en plus lente, sans que rien ne le signale.
    static let maximumSnapshotBytes = 1_000_000

    private static func withinSizeLimit(_ data: Data, code: String) -> Data? {
        guard data.count <= maximumSnapshotBytes else {
            DiagnosticsCenter.record(
                .store,
                .warning,
                code: code,
                detail: "\(data.count) octets"
            )
            return nil
        }
        return data
    }

    private func persistRuntimeState(action: String) {
        guard let workout = activeWorkout else { return }
        do {
            let encoded = try JSONEncoder().encode(runtimeState)
            workout.runtimeStateData = Self.withinSizeLimit(encoded, code: "workout.runtimeState.tooLarge")
            _ = PersistenceSupport.save(modelContext, action: action)
        } catch {
            PersistenceSupport.report(error, action: action)
        }
    }

    private func createActiveWorkout() -> ActiveWorkout {
        let workout = ActiveWorkout(
            startedAt: startedAt,
            // Une seance libre n'a pas de seance de programme : l'identifiant
            // ne designe rien, c'est `isFreeSession` qui fait foi.
            programSessionId: programSession?.id ?? UUID(),
            exerciseIndex: position.nodeIndex,
            setIndex: position.setIndex,
            phaseRaw: phase.rawValue,
            runtimeStateData: try? JSONEncoder().encode(runtimeState),
            planData: try? JSONEncoder().encode(plan),
            positionData: try? JSONEncoder().encode(position),
            isFreeSession: isFreeSession
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

    /// Pas des boutons +/- de la saisie pour cet exercice, en kg : pas du
    /// materiel dans le lieu par defaut, sinon palier du profil, sinon pas
    /// usuel de l'unite (cf. `LoadStep`).
    func loadStepKilograms(for exercise: WorkoutExercisePlan) -> Double {
        let profile = ProfileStore.currentProfile(in: modelContext)
        let unit = profile?.massUnit ?? .kilograms
        let equipmentIncrement = equipment(forExerciseId: exercise.exerciseId).flatMap { equipment in
            defaultPlace()?.inventory.availability(for: equipment)?.increment
        }
        return LoadStep.inputStepKilograms(
            equipmentIncrement: equipmentIncrement,
            profileIncrementsKilograms: profile?.availableIncrementsKilograms ?? [],
            unit: unit
        )
    }

    private func equipment(forExerciseId exerciseId: String) -> String? {
        WorkoutPlanBuilder.equipment(
            forExerciseId: exerciseId,
            catalogStore: catalogStore,
            customExercises: (try? modelContext.fetch(FetchDescriptor<CustomExercise>())) ?? []
        )
    }

    /// Lieu par defaut, meme regle que le choix de remplacement d'exercice.
    private func defaultPlace() -> PlaceProfile? {
        let places = ((try? modelContext.fetch(FetchDescriptor<PlaceProfile>())) ?? []).filter { $0.deletedAt == nil }
        return places.first { $0.isDefault } ?? places.first
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
