#if DEBUG
import Foundation
import SwiftData
import MuscuEngine

// Harnais de seed pour les tests UI (MuscuUITests). Actif uniquement en
// configuration DEBUG (jamais livre en release) et uniquement derriere des
// arguments de lancement explicites, pour ne jamais s'activer par accident :
// - "--uitest-reset" : vide entierement le store SwiftData au demarrage.
// - "--uitest-seed" : (necessite --uitest-reset) seede un jeu de donnees
//   deterministe couvrant les principaux flux de seance (classique, pyramide,
//   intervalles, AMRAP), l'historique, les records et un exercice perso.
// Les durees (repos, intervalles, AMRAP) sont volontairement tres courtes
// (quelques secondes) pour que les tests UI n'attendent jamais des minutes.
@MainActor
enum UITestSupport {
    // Identifiants FICTIFS (pas de vrai exerciseId du catalogue) : si l'id
    // seede correspondait a un vrai CatalogExercise, ExerciseImageView
    // tenterait de telecharger son image via ImageStore (URLSession) des
    // l'ouverture du runner - sans reseau dans cet environnement de test,
    // ce fetch peut mettre plusieurs dizaines de secondes a echouer et
    // retarde d'autant la detection "app idle" de XCUITest avant chaque
    // interaction. Un id absent du catalogue -> catalogStore.exercise(id:)
    // retourne nil -> ExerciseImageView recoit imagePath: nil -> aucun
    // reseau, placeholder immediat. Les noms restent realistes (affiches
    // tels quels dans l'UI), seul l'id change.
    static let benchId = "seed-classic-bench"
    static let benchName = "Développé couché à la barre - prise moyenne"
    static let pullupsId = "seed-pyramid-pullups"
    static let pullupsName = "Tractions"
    static let mountainClimbersId = "seed-intervals-mountain-climbers"
    static let mountainClimbersName = "Grimpeur (mountain climber)"
    static let pushupsId = "seed-amrap-pushups"
    static let pushupsName = "Pompes"

    // Séance C : formats avancés (superset + dropset), volontairement très
    // courts pour que les tests UI ne durent pas des minutes.
    static let rowId = "seed-superset-row"
    static let rowName = "Rowing haltère"
    static let curlId = "seed-dropset-curl"
    static let curlName = "Curl biceps"

    static let customExerciseName = "Exercice Perso Debug"

    /// Supprime le store local UNIQUEMENT si les tests UI le demandent
    /// (`--uitest-reset`) ET qu'il est devenu illisible avec le schema
    /// courant. Sans ce garde-fou, un store ecrit par une version
    /// intermediaire du schema pendant le developpement bloquerait toute la
    /// suite UI sur l'alerte « Base locale indisponible ».
    ///
    /// Jamais compile en Release, jamais declenche sans le drapeau.
    static func resetStoreIfUnreadable() {
        guard ProcessInfo.processInfo.arguments.contains("--uitest-reset") else { return }
        guard StoreRecovery.storeExists else { return }

        let schema = Schema(versionedSchema: MuscuCurrentSchema.self)
        if (try? ModelContainer(for: schema, migrationPlan: MuscuMigrationPlan.self)) != nil { return }

        for file in StoreRecovery.existingStoreFiles {
            try? FileManager.default.removeItem(at: file)
        }
    }

    static func configure(container: ModelContainer) {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--uitest-reset") else { return }

        // Aucune demande d'autorisation systeme pendant les tests UI : une
        // alerte de notification ou de calendrier bloquerait la suite.
        AppServices.useInMemoryServices()

        // Reglages du coach IA, de Sante et instantane des widgets : tout
        // cela vit dans UserDefaults, le Trousseau ou le groupe
        // d'applications, pas dans SwiftData. Sans cette remise a zero,
        // l'etat d'un test survit au suivant et « --uitest-reset » ment sur
        // ce qu'il reinitialise.
        AISettings.reset()
        AICoachLog.clear()
        HealthSettings.reset()
        WidgetSnapshotStore.clear()
        DiagnosticsCenter.reset()

        let context = ModelContext(container)
        wipe(context: context)

        if args.contains("--uitest-seed") {
            seed(context: context)
        }

        _ = PersistenceSupport.save(context, action: "Préparation des tests UI")
    }

    /// Modeles reellement purges par `--uitest-reset`. Expose pour qu'un
    /// test puisse verifier que la liste couvre tout le schema courant.
    static let wipedModelNames: [String] = [
        "Program", "ProgramSession", "ExerciseGroup", "PrescribedExercise",
        "CompletedSession", "CompletedSet", "ActiveWorkout",
        "ExerciseRecord", "PersonalBest", "CustomExercise",
        "AthleteProfile", "BodyMeasurement", "ReadinessEntry", "HealthWorkoutLink",
        "TrainingPlan", "TrainingBlock", "TrainingWeek", "ScheduledWorkout",
        "AdaptationEntry", "TrainingGoal", "SyncState",
        "PlaceProfile", "PlanningSchedule", "NotificationRecord", "CalendarLink",
        "SessionTemplate", "ExerciseLibraryEntry", "ExerciseCollection",
        "ImportQuarantineEntry", "ProgressPhoto",
    ]

    /// Vide TOUTES les entites utilisateur. Cette liste doit couvrir chaque
    /// modele du schema courant : un type oublie ici survit d'un test a
    /// l'autre et rend la suite dependante de son ordre d'execution.
    private static func wipe(context: ModelContext) {
        // Les relations sont en cascade : supprimer le parent suffit, mais on
        // passe quand meme sur les enfants pour les donnees orphelines.
        deleteAll(Program.self, in: context)
        deleteAll(ProgramSession.self, in: context)
        deleteAll(ExerciseGroup.self, in: context)
        deleteAll(PrescribedExercise.self, in: context)
        deleteAll(CompletedSession.self, in: context)
        deleteAll(CompletedSet.self, in: context)
        deleteAll(ActiveWorkout.self, in: context)
        deleteAll(ExerciseRecord.self, in: context)
        deleteAll(PersonalBest.self, in: context)
        deleteAll(CustomExercise.self, in: context)
        deleteAll(AthleteProfile.self, in: context)
        deleteAll(BodyMeasurement.self, in: context)
        deleteAll(ReadinessEntry.self, in: context)
        deleteAll(HealthWorkoutLink.self, in: context)
        deleteAll(TrainingPlan.self, in: context)
        deleteAll(TrainingBlock.self, in: context)
        deleteAll(TrainingWeek.self, in: context)
        deleteAll(ScheduledWorkout.self, in: context)
        deleteAll(AdaptationEntry.self, in: context)
        deleteAll(TrainingGoal.self, in: context)
        deleteAll(SyncState.self, in: context)
        deleteAll(PlaceProfile.self, in: context)
        deleteAll(PlanningSchedule.self, in: context)
        deleteAll(NotificationRecord.self, in: context)
        deleteAll(CalendarLink.self, in: context)
        deleteAll(SessionTemplate.self, in: context)
        deleteAll(ExerciseLibraryEntry.self, in: context)
        deleteAll(ExerciseCollection.self, in: context)
        deleteAll(ImportQuarantineEntry.self, in: context)
        deleteAll(ProgressPhoto.self, in: context)
        _ = PersistenceSupport.save(context, action: "Préparation des tests UI")
    }

    private static func deleteAll<T: PersistentModel>(_ type: T.Type, in context: ModelContext) {
        guard let items = try? context.fetch(FetchDescriptor<T>()) else { return }
        for item in items { context.delete(item) }
    }

    private static func seed(context: ModelContext) {
        let program = Program(name: "Programme Test", isActive: true)
        context.insert(program)

        // Séance A : 1 exercice classique (2 séries, repos 15 s, %1RM 75)
        // + 1 pyramide (2-4-6-4-2, repos très courts pour aller vite).
        let sessionA = ProgramSession(name: "Séance A", orderIndex: 0)
        sessionA.program = program
        program.sessions.append(sessionA)
        context.insert(sessionA)

        let classic = PrescribedExercise(
            exerciseId: benchId,
            displayName: benchName,
            orderIndex: 0,
            formatRaw: SetFormat.classic.rawValue,
            sets: 2,
            repsLower: 8,
            repsUpper: 8,
            restSeconds: 15,
            percentOneRepMax: 75,
            loadKindRaw: LoadKind.external.rawValue
        )
        classic.session = sessionA
        sessionA.exercises.append(classic)
        context.insert(classic)

        // « --uitest-long-pyramid » : pyramide de 18 paliers en PREMIER
        // exercice, repos reels, pour verifier a l'oeil la mise en page du
        // deroule d'une longue pyramide (captures, Dynamic Type).
        let longPyramid = ProcessInfo.processInfo.arguments.contains("--uitest-long-pyramid")
        if longPyramid { classic.orderIndex = 1 }
        let pyramid = PrescribedExercise(
            exerciseId: pullupsId,
            displayName: pullupsName,
            orderIndex: longPyramid ? 0 : 1,
            formatRaw: SetFormat.pyramid.rawValue,
            pyramidReps: longPyramid ? [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 9, 8, 7, 6, 5, 4, 3, 2] : [2, 4, 6, 4, 2],
            pyramidMinRest: longPyramid ? 30 : 2,
            pyramidMaxRest: longPyramid ? 180 : 3
        )
        pyramid.session = sessionA
        sessionA.exercises.append(pyramid)
        context.insert(pyramid)

        // Séance B : 1 bloc intervalles (3 s / 2 s x 2, au lieu de 30-30 pour
        // rester rapide) + 1 AMRAP de 5 s.
        let sessionB = ProgramSession(name: "Séance B", orderIndex: 1)
        sessionB.program = program
        program.sessions.append(sessionB)
        context.insert(sessionB)

        let intervals = PrescribedExercise(
            exerciseId: mountainClimbersId,
            displayName: mountainClimbersName,
            orderIndex: 0,
            formatRaw: SetFormat.intervals.rawValue,
            intervalWork: 3,
            intervalRest: 2,
            intervalRounds: 2
        )
        intervals.session = sessionB
        sessionB.exercises.append(intervals)
        context.insert(intervals)

        let amrap = PrescribedExercise(
            exerciseId: pushupsId,
            displayName: pushupsName,
            orderIndex: 1,
            formatRaw: SetFormat.amrap.rawValue,
            amrapSeconds: 5
        )
        amrap.session = sessionB
        sessionB.exercises.append(amrap)
        context.insert(amrap)

        // Séance C : un superset de 2 tours (repos entre tours très court)
        // et un dropset à 2 paliers, pour couvrir les formats avancés.
        let sessionC = ProgramSession(name: "Séance C", orderIndex: 2)
        sessionC.program = program
        program.sessions.append(sessionC)
        context.insert(sessionC)

        let supersetFirst = PrescribedExercise(
            exerciseId: pushupsId,
            displayName: pushupsName,
            orderIndex: 0,
            formatRaw: SetFormat.classic.rawValue,
            sets: 2,
            repsLower: 8,
            repsUpper: 8,
            restSeconds: 2
        )
        supersetFirst.session = sessionC
        sessionC.exercises.append(supersetFirst)
        context.insert(supersetFirst)

        let supersetSecond = PrescribedExercise(
            exerciseId: rowId,
            displayName: rowName,
            orderIndex: 1,
            formatRaw: SetFormat.classic.rawValue,
            sets: 2,
            repsLower: 10,
            repsUpper: 10,
            restSeconds: 2
        )
        supersetSecond.session = sessionC
        supersetSecond.groupOrderIndex = 1
        sessionC.exercises.append(supersetSecond)
        context.insert(supersetSecond)

        let superset = ExerciseGroup(
            kindRaw: ExerciseGroupKind.superset.rawValue,
            orderIndex: 0,
            rounds: 2,
            restBetweenExercisesSeconds: 0,
            restBetweenRoundsSeconds: 2
        )
        superset.session = sessionC
        sessionC.groups.append(superset)
        context.insert(superset)
        supersetFirst.group = superset
        supersetSecond.group = superset

        let dropset = PrescribedExercise(
            exerciseId: curlId,
            displayName: curlName,
            orderIndex: 2,
            formatRaw: SetFormat.dropset.rawValue,
            sets: 1,
            repsLower: 10,
            repsUpper: 10,
            restSeconds: 2,
            targetWeight: 20,
            dropsetDrops: [25, 25],
            dropsetUsesPercent: true,
            dropsetRestSeconds: 0
        )
        dropset.session = sessionC
        sessionC.exercises.append(dropset)
        context.insert(dropset)

        // Records : 1RM 100 kg pour l'exercice classique (%1RM 75 -> charge
        // proposée 75 kg), max de reps 10 pour la pyramide (Tractions).
        let benchRecord = ExerciseRecord(exerciseId: benchId, displayName: benchName, oneRepMax: 100)
        context.insert(benchRecord)

        let pullupsRecord = ExerciseRecord(exerciseId: pullupsId, displayName: pullupsName, maxReps: 10)
        context.insert(pullupsRecord)

        // Un record TYPE, pour que la section « Records par type » ait de
        // quoi s'afficher : ces records etaient enregistres en fin de seance
        // depuis des semaines sans qu'aucun ecran ne les montre.
        context.insert(
            PersonalBest(
                exerciseId: benchId,
                displayName: benchName,
                kindRaw: PersonalBestKind.maxWeight.rawValue,
                value: 92.5,
                reps: 3
            )
        )

        // Une séance déjà terminée dans l'historique (indépendante du
        // programme actif, pour tester Progression > Historique sans avoir à
        // dérouler une séance au préalable). programName volontairement
        // différent de "Programme Test" : HomeView.nextSession() fait
        // tourner la rotation des séances en cherchant la dernière
        // CompletedSession dont programName correspond au programme actif -
        // si ce seed matchait, "Lancer la séance" proposerait toujours
        // Séance B en premier (rotation), ce qui casserait la
        // reproductibilité des tests (Séance A doit être la première
        // proposée sur un store fraîchement seedé).
        let completed = CompletedSession(
            date: Date.now.addingTimeInterval(-86_400),
            programName: "Ancien programme (historique)",
            sessionName: "Séance A",
            durationSeconds: 600
        )
        context.insert(completed)

        // Deux series de travail au HAUT de la fourchette prescrite (2 x 8) :
        // le moteur de progression a donc de quoi proposer une montee de
        // charge des l'ecran de preparation de la seance.
        for setIndex in 0..<2 {
            let completedSet = CompletedSet(
                exerciseId: benchId,
                displayName: benchName,
                orderIndex: 0,
                setIndex: setIndex,
                weight: 70,
                reps: 8,
                loadTypeRaw: ExerciseLoadType.external.rawValue,
                roleRaw: SetRole.working.rawValue,
                sequenceIndex: setIndex
            )
            completedSet.session = completed
            completed.sets.append(completedSet)
            context.insert(completedSet)
        }

        // Exercice perso.
        let custom = CustomExercise(
            name: customExerciseName,
            primaryMuscles: ["chest"],
            equipment: "barbell"
        )
        context.insert(custom)
    }
}
#endif
