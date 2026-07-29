#if DEBUG
import Foundation
import SwiftData

// Harnais de seed pour les tests UI (MuscuUITests). Actif uniquement en
// configuration DEBUG (jamais livre en release) et uniquement derriere des
// arguments de lancement explicites, pour ne jamais s'activer par accident :
// - "--uitest-reset" : vide entierement le store SwiftData au demarrage.
// - "--uitest-seed" : (necessite --uitest-reset) seede un jeu de donnees
//   deterministe couvrant les principaux flux de seance (classique, pyramide,
//   intervalles, AMRAP), l'historique, les records et un exercice perso.
// Les durees (repos, intervalles, AMRAP) sont volontairement tres courtes
// (quelques secondes) pour que les tests UI n'attendent jamais des minutes.
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

    static let customExerciseName = "Exercice Perso Debug"

    static func configure(container: ModelContainer) {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--uitest-reset") else { return }

        let context = ModelContext(container)
        wipe(context: context)

        if args.contains("--uitest-seed") {
            seed(context: context)
        }

        try? context.save()
    }

    private static func wipe(context: ModelContext) {
        deleteAll(Program.self, in: context)
        deleteAll(CompletedSession.self, in: context)
        deleteAll(ExerciseRecord.self, in: context)
        deleteAll(CustomExercise.self, in: context)
        deleteAll(ActiveWorkout.self, in: context)
        try? context.save()
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
            percentOneRepMax: 75
        )
        classic.session = sessionA
        sessionA.exercises.append(classic)
        context.insert(classic)

        let pyramid = PrescribedExercise(
            exerciseId: pullupsId,
            displayName: pullupsName,
            orderIndex: 1,
            formatRaw: SetFormat.pyramid.rawValue,
            pyramidReps: [2, 4, 6, 4, 2],
            pyramidMinRest: 2,
            pyramidMaxRest: 3
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

        // Records : 1RM 100 kg pour l'exercice classique (%1RM 75 -> charge
        // proposée 75 kg), max de reps 10 pour la pyramide (Tractions).
        let benchRecord = ExerciseRecord(exerciseId: benchId, displayName: benchName, oneRepMax: 100)
        context.insert(benchRecord)

        let pullupsRecord = ExerciseRecord(exerciseId: pullupsId, displayName: pullupsName, maxReps: 10)
        context.insert(pullupsRecord)

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

        let completedSet = CompletedSet(
            exerciseId: benchId,
            displayName: benchName,
            orderIndex: 0,
            setIndex: 0,
            weight: 70,
            reps: 8
        )
        completedSet.session = completed
        completed.sets.append(completedSet)
        context.insert(completedSet)

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
