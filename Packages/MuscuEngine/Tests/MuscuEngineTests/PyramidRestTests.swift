import Foundation
import Testing
@testable import MuscuEngine

/// Repos d'une pyramide : une seule source de verite pour la machine a
/// etats, l'apercu du deroule et l'editeur.
@Suite
struct PyramidRestTests {
    private func pyramid(
        _ reps: [Int],
        rests: [Int] = [],
        minRest: Int = 30,
        maxRest: Int = 180
    ) -> WorkoutExercisePlan {
        WorkoutExercisePlan(
            exerciseId: "pullups",
            displayName: "Tractions",
            format: .pyramid,
            loadKind: .bodyweight,
            pyramidReps: reps,
            pyramidMinRest: minRest,
            pyramidMaxRest: maxRest,
            pyramidRestSeconds: rests
        )
    }

    private let nextExercise = WorkoutExercisePlan(exerciseId: "dips", displayName: "Dips", format: .classic, restSeconds: 90)

    /// Deroule complet : pour chaque palier, l'apercu calcule AVANT la
    /// validation (avec les reps reellement saisies) et le repos lance.
    private func previewsAndLaunched(
        _ exercise: WorkoutExercisePlan,
        followedByAnotherExercise: Bool = true,
        reps: (Int, Int) -> Int = { _, target in target }
    ) -> [(preview: Int?, launched: Int?)] {
        var nodes = [WorkoutNode.single(exercise)]
        if followedByAnotherExercise { nodes.append(.single(nextExercise)) }
        let plan = WorkoutPlan(nodes: nodes)
        var position = WorkoutPosition.start
        var result: [(Int?, Int?)] = []
        while case .logSet(let target) = WorkoutStateMachine.step(at: position, in: plan),
              target.exercise.id == exercise.id {
            let index = target.setNumber - 1
            let done = reps(index, target.targetRepsLower)
            let preview = target.exercise.pyramidRest(afterStep: index, repsDone: done)
            let advanced = WorkoutStateMachine.advance(from: position, in: plan, outcome: WorkoutSetOutcome(reps: done))
            result.append((preview, advanced.rest?.seconds))
            position = advanced.position
        }
        return result
    }

    @Test("L'aperçu du repos est exactement le repos lancé, palier par palier")
    func previewMatchesLaunchedRest() {
        let long = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 9, 8, 7, 6, 5, 4, 3, 2]
        let runs = previewsAndLaunched(pyramid(long)) { index, target in
            // Reps ajustees au stepper : jamais exactement la cible.
            index.isMultiple(of: 3) ? target + 1 : max(1, target - 1)
        }
        #expect(runs.count == long.count)
        for run in runs.dropLast() {
            #expect(run.preview != nil)
            #expect(run.preview == run.launched)
        }
    }

    @Test("Mode par palier : l'aperçu et le repos lancé sont la durée choisie")
    func perStepPreviewMatchesLaunchedRest() {
        let runs = previewsAndLaunched(pyramid([2, 4, 6, 4, 2], rests: [20, 45, 125, 0, 999]))
        #expect(runs.map(\.preview) == [20, 45, 125, 0, nil])
        // 0 s = enchainer : rien n'est lance.
        #expect(runs.map(\.launched) == [20, 45, 125, nil, nil])
    }

    @Test("Aucun repos après le dernier palier, même si un exercice suit")
    func noRestAfterLastStep() {
        for exercise in [pyramid([2, 4, 6, 4, 2]), pyramid([2, 4, 6], rests: [30, 60, 90])] {
            let runs = previewsAndLaunched(exercise, followedByAnotherExercise: true)
            #expect(runs.last?.preview == nil)
            #expect(runs.last?.launched == nil)
        }
    }

    @Test("La référence d'intensité est le palier le plus haut de la pyramide")
    func referenceIsPyramidTop() {
        let exercise = pyramid([2, 4, 6, 8, 6, 4, 2])
        // Palier le plus dur : repos maxi ; plus leger : proche du mini.
        #expect(exercise.pyramidRest(afterStep: 3, repsDone: 8) == 180)
        #expect(exercise.pyramidRest(afterStep: 0, repsDone: 2) == Pyramid.adaptiveRest(repsDone: 2, maxReps: 8))
        // Depasser la cible ne depasse pas le repos maxi.
        #expect(exercise.pyramidRest(afterStep: 2, repsDone: 12) == 180)
    }

    @Test("Une pyramide sans bornes de repos garde un repos adaptatif par défaut")
    func missingBoundsFallBackToDefaults() {
        let exercise = pyramid([2, 4, 6, 4, 2], minRest: 0, maxRest: 0)
        #expect(exercise.pyramidRest(afterStep: 2, repsDone: 6) == Pyramid.defaultMaxRest)
        #expect((exercise.pyramidRest(afterStep: 0, repsDone: 2) ?? 0) >= Pyramid.defaultMinRest)
    }

    @Test("Des repos par palier mal alignés retombent sur l'adaptatif")
    func misalignedRestsFallBack() {
        let exercise = pyramid([2, 4, 6, 4, 2], rests: [40])
        #expect(exercise.pyramidRest(afterStep: 0, repsDone: 2) == 40)
        #expect(exercise.pyramidRest(afterStep: 2, repsDone: 6) == 180)
    }

    @Test("L'estimation de durée compte les repos réellement prévus")
    func durationUsesPlannedRests() {
        let perStep = pyramid([2, 4, 6], rests: [60, 120, 300])
        #expect(SessionDuration.estimatedSeconds(for: perStep) == 3 * SessionDuration.workSecondsPerStep + 180)
        let adaptive = pyramid([2, 4, 6])
        let planned = Pyramid.plannedRests(steps: [2, 4, 6], stepRests: [], minRest: 30, maxRest: 180)
        #expect(planned.count == 2)
        #expect(SessionDuration.estimatedSeconds(for: adaptive) == 3 * SessionDuration.workSecondsPerStep + planned.reduce(0, +))
    }

    @Test("Un déroulé persisté sans repos par palier reste lisible, en adaptatif")
    func legacyPlanDecodes() throws {
        let current = pyramid([2, 4, 6], rests: [30, 60, 90])
        var object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(current)) as? [String: Any])
        object.removeValue(forKey: "pyramidRestSeconds")
        let legacy = try JSONDecoder().decode(WorkoutExercisePlan.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(legacy.pyramidRestSeconds.isEmpty)
        #expect(legacy.pyramidReps == [2, 4, 6])
        var expected = current
        expected.pyramidRestSeconds = []
        #expect(legacy == expected)
        // Aller-retour complet avec la nouvelle cle.
        let roundTrip = try JSONDecoder().decode(WorkoutExercisePlan.self, from: JSONEncoder().encode(current))
        #expect(roundTrip == current)
    }

    // MARK: - Reglage

    @Test("Pas de réglage : 5 s sous la minute, 15 s au-delà, bornés à 0-10 min")
    func restIncrements() {
        #expect(Pyramid.increasedRest(0) == 5)
        #expect(Pyramid.increasedRest(55) == 60)
        #expect(Pyramid.increasedRest(60) == 75)
        #expect(Pyramid.increasedRest(57) == 60)
        #expect(Pyramid.increasedRest(600) == 600)
        #expect(Pyramid.decreasedRest(75) == 60)
        #expect(Pyramid.decreasedRest(60) == 55)
        #expect(Pyramid.decreasedRest(62) == 60)
        #expect(Pyramid.decreasedRest(5) == 0)
        #expect(Pyramid.decreasedRest(0) == 0)
        #expect(Pyramid.clampedRest(900) == 600)
    }

    @Test("Passer en mode par palier part des valeurs de l'adaptatif")
    func switchingToPerStepKeepsAdaptiveValues() {
        var steps = PyramidSteps(reps: [2, 4, 6, 4, 2])
        #expect(!steps.usesPerStepRest)
        steps.usePerStepRest(minRest: 30, maxRest: 180)
        #expect(steps.restSeconds.count == 5)
        let adaptive = Pyramid.plannedRests(steps: [2, 4, 6, 4, 2], stepRests: [], minRest: 30, maxRest: 180)
        #expect(Array(steps.restSeconds.dropLast()) == adaptive)
        // Pas de champ pour le dernier palier.
        #expect(steps.editableRest(at: 4) == nil)
        #expect(steps.editableRest(at: 3) == steps.restSeconds[3])
        steps.useAdaptiveRest()
        #expect(steps.restSeconds.isEmpty)
    }

    @Test("Ajouter, supprimer et déplacer un palier emporte son repos")
    func restsStayAlignedWithSteps() {
        var steps = PyramidSteps(reps: [2, 4, 6], restSeconds: [20, 40, 60])
        steps.appendStep(maxReps: 10, minRest: 30, maxRest: 180)
        #expect(steps.reps == [2, 4, 6, 6])
        #expect(steps.restSeconds == [20, 40, 60, 60])

        steps.setReps(8, at: 3)
        steps.setRest(90, at: 3)
        #expect(steps.restSeconds == [20, 40, 60, 90])

        // Le palier 6 (repos 60) passe en tete : son repos le suit.
        steps.moveSteps(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(steps.reps == [6, 2, 4, 8])
        #expect(steps.restSeconds == [60, 20, 40, 90])

        // Deplacement vers la fin (destination exprimee avant retrait).
        steps.moveSteps(fromOffsets: IndexSet(integer: 0), toOffset: 4)
        #expect(steps.reps == [2, 4, 8, 6])
        #expect(steps.restSeconds == [20, 40, 90, 60])

        steps.removeSteps(atOffsets: IndexSet([0, 2]))
        #expect(steps.reps == [4, 6])
        #expect(steps.restSeconds == [40, 60])

        steps.setAllRests(45)
        #expect(steps.restSeconds == [45, 45])
        steps.setAllRests(9_999)
        #expect(steps.restSeconds == [600, 600])
    }

    @Test("En mode adaptatif, éditer les paliers ne crée aucun repos")
    func adaptiveEditingKeepsRestsEmpty() {
        var steps = PyramidSteps(reps: [2, 4])
        steps.appendStep(maxReps: 10, minRest: 30, maxRest: 180)
        steps.moveSteps(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        steps.removeSteps(atOffsets: IndexSet(integer: 0))
        steps.setAllRests(60)
        steps.setRest(60, at: 0)
        #expect(steps.restSeconds.isEmpty)
        #expect(steps.reps == [4, 2])
    }

    @Test("Normalisation : vide reste vide, sinon un repos borné par palier")
    func normalization() {
        #expect(Pyramid.normalizedRests([], stepCount: 5).isEmpty)
        #expect(Pyramid.normalizedRests([30, 700], stepCount: 4) == [30, 600, 600, 600])
        #expect(Pyramid.normalizedRests([30, 40, 50], stepCount: 2) == [30, 40])
        #expect(Pyramid.normalizedRests([-5], stepCount: 1) == [0])
        let steps = PyramidSteps(reps: [2, 4, 6], restSeconds: [10])
        #expect(steps.restSeconds == [10, 10, 10])
    }

    @Test("Choisir une proposition recalcule les repos par palier")
    func replacingStepsRecomputesPerStepRests() {
        var steps = PyramidSteps(reps: [2, 4], restSeconds: [15, 15])
        steps.replaceSteps([1, 2, 3, 2, 1], minRest: 30, maxRest: 180)
        #expect(steps.restSeconds == Pyramid.perStepRests(fromAdaptive: [1, 2, 3, 2, 1], minRest: 30, maxRest: 180))
        var adaptive = PyramidSteps(reps: [2, 4])
        adaptive.replaceSteps([1, 2, 1], minRest: 30, maxRest: 180)
        #expect(adaptive.restSeconds.isEmpty)
    }
}
