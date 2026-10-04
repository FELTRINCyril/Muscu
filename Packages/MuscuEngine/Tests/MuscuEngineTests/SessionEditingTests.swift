import Foundation
import Testing
@testable import MuscuEngine

private func exercise(_ name: String, sets: Int = 2) -> WorkoutExercisePlan {
    WorkoutExercisePlan(exerciseId: name, displayName: name, setCount: sets, restSeconds: 60)
}

@Suite("Séance libre et ajout d'exercice")
struct AppendExerciseTests {
    @Test("Une séance vide est terminée, l'ajout la relance sur le nouvel exercice")
    func emptyPlanResumesOnAppend() {
        let empty = WorkoutPlan(nodes: [])
        let position = WorkoutPosition(nodeIndex: 0)
        #expect(WorkoutStateMachine.step(at: position, in: empty) == .finished)

        let plan = WorkoutPlanEditing.appending(exercise("squat"), to: empty)
        guard case .logSet(let target) = WorkoutStateMachine.step(at: position, in: plan) else {
            Issue.record("Une série du nouvel exercice était attendue")
            return
        }
        #expect(target.exercise.exerciseId == "squat")
        #expect(target.setNumber == 1)
    }

    @Test("Après le dernier exercice, l'ajout reprend là où la séance s'était arrêtée")
    func appendAfterFinishedPlan() {
        var plan = WorkoutPlan(nodes: [.single(exercise("bench", sets: 1))])
        let advanced = WorkoutStateMachine.advance(from: .start, in: plan, outcome: WorkoutSetOutcome(reps: 8))
        #expect(WorkoutStateMachine.isFinished(advanced.position, in: plan))
        #expect(advanced.rest == nil)

        plan = WorkoutPlanEditing.appending(exercise("row"), to: plan)
        #expect(!WorkoutStateMachine.isFinished(advanced.position, in: plan))
        #expect(WorkoutStateMachine.step(at: advanced.position, in: plan) != .finished)
    }

    @Test("Le déroulé persisté avant la mesure se relit sans elle")
    func legacyPlanDecodes() throws {
        let plan = WorkoutPlan(nodes: [.single(exercise("bench"))])
        // Les champs facultatifs absents ne sont pas encodes : ce JSON a la
        // forme exacte d'un deroule ecrit avant l'ajout de la mesure.
        let json = try JSONEncoder().encode(plan)
        #expect(!String(decoding: json, as: UTF8.self).contains("measure"))
        let decoded = try JSONDecoder().decode(WorkoutPlan.self, from: json)
        #expect(decoded.allExercises.first?.effectiveMeasure == .weightReps)
    }
}

@Suite("Réordonner les exercices restants")
struct ReorderRemainingTests {
    private let a = exercise("a")
    private let b = exercise("b")
    private let c = exercise("c")
    private let d = exercise("d")

    private var plan: WorkoutPlan {
        WorkoutPlan(nodes: [.single(a), .single(b), .single(c), .single(d)])
    }

    @Test("Les exercices commencés et passés ne sont pas proposés")
    func startedNodesAreLocked() {
        let position = WorkoutPosition(nodeIndex: 1, setIndex: 1)
        let indices = WorkoutPlanEditing.reorderableNodeIndices(
            in: plan,
            position: position,
            startedExerciseIDs: [a.id, b.id]
        )
        #expect(indices == [2, 3])
    }

    @Test("L'exercice courant non commencé peut céder sa place")
    func currentUnstartedNodeMoves() throws {
        let plan = self.plan
        let position = WorkoutPosition(nodeIndex: 1)
        let ids = [plan.nodes[3].id, plan.nodes[1].id, plan.nodes[2].id]
        let result = try #require(WorkoutPlanEditing.reordering(
            plan,
            position: position,
            startedExerciseIDs: [a.id],
            newOrder: ids
        ))
        #expect(result.plan.allExercises.map(\.exerciseId) == ["a", "d", "b", "c"])
        #expect(result.position == WorkoutPosition(nodeIndex: 1))
    }

    @Test("Un exercice commencé plus loin (aperçu) garde sa place")
    func startedLaterNodeKeepsItsSlot() throws {
        let plan = self.plan
        let position = WorkoutPosition(nodeIndex: 1)
        // « c » a déjà une série : seuls b et d bougent, c reste en 3e.
        let ids = [plan.nodes[3].id, plan.nodes[1].id]
        let result = try #require(WorkoutPlanEditing.reordering(
            plan,
            position: position,
            startedExerciseIDs: [a.id, c.id],
            newOrder: ids
        ))
        #expect(result.plan.allExercises.map(\.exerciseId) == ["a", "d", "c", "b"])
    }

    @Test("Un ordre qui n'est pas une permutation est refusé")
    func invalidOrderIsRejected() {
        let plan = self.plan
        let position = WorkoutPosition(nodeIndex: 1)
        #expect(WorkoutPlanEditing.reordering(plan, position: position, startedExerciseIDs: [a.id], newOrder: [plan.nodes[0].id]) == nil)
        #expect(WorkoutPlanEditing.reordering(
            plan,
            position: position,
            startedExerciseIDs: [a.id],
            newOrder: [plan.nodes[1].id, plan.nodes[1].id, plan.nodes[2].id]
        ) == nil)
    }

    @Test("Les index à plat suivent les exercices quand des groupes changent de place")
    func flatIndicesFollowExercises() throws {
        let group = WorkoutNode(kind: .superset, exercises: [b, c], rounds: 3)
        let plan = WorkoutPlan(nodes: [.single(a), group, .single(d)])
        let result = try #require(WorkoutPlanEditing.reordering(
            plan,
            position: WorkoutPosition(nodeIndex: 1),
            startedExerciseIDs: [a.id],
            newOrder: [plan.nodes[2].id, group.id]
        ))
        let mapping = WorkoutPlanEditing.flatIndexMapping(from: plan, to: result.plan)
        #expect(mapping == [0: 0, 1: 2, 2: 3, 3: 1])
    }
}

@Suite("Séries au temps et à la distance")
struct SetMeasureTests {
    @Test("La mesure se déduit des cibles strictement positives")
    func measureFromTargets() {
        #expect(SetMeasure(targetDurationSeconds: 0, targetDistanceMeters: 0) == .weightReps)
        #expect(SetMeasure(targetDurationSeconds: 45, targetDistanceMeters: 0) == .duration)
        #expect(SetMeasure(targetDurationSeconds: 0, targetDistanceMeters: 400) == .distance)
        #expect(SetMeasure(targetDurationSeconds: 300, targetDistanceMeters: 1_000) == .durationAndDistance)
        #expect(SetMeasure(targetDurationSeconds: 0, targetDistanceMeters: .nan) == .weightReps)
    }

    @Test("Seul le format classique porte une mesure")
    func onlyClassicMeasures() {
        var plan = WorkoutExercisePlan(exerciseId: "plank", displayName: "Gainage", measure: .duration)
        #expect(plan.effectiveMeasure == .duration)
        plan.format = .dropset
        #expect(plan.effectiveMeasure == .weightReps)
    }

    @Test("Validation : chaque grandeur demandée, dans ses bornes, et rien d'autre")
    func validation() {
        #expect(MeasuredSetResult(durationSeconds: 45, distanceMeters: nil).isValid(for: .duration))
        #expect(!MeasuredSetResult(durationSeconds: 0, distanceMeters: nil).isValid(for: .duration))
        #expect(!MeasuredSetResult(durationSeconds: nil, distanceMeters: nil).isValid(for: .duration))
        #expect(!MeasuredSetResult(durationSeconds: 45, distanceMeters: 100).isValid(for: .duration))
        #expect(MeasuredSetResult(durationSeconds: nil, distanceMeters: 2_000).isValid(for: .distance))
        #expect(!MeasuredSetResult(durationSeconds: nil, distanceMeters: .infinity).isValid(for: .distance))
        #expect(MeasuredSetResult(durationSeconds: 600, distanceMeters: 2_000).isValid(for: .durationAndDistance))
        #expect(!MeasuredSetResult(durationSeconds: 600, distanceMeters: nil).isValid(for: .durationAndDistance))
        #expect(!MeasuredSetResult(durationSeconds: 60, distanceMeters: nil).isValid(for: .weightReps))
    }

    @Test("Une série au temps ne compte pas de tonnage, et n'est pas une donnée manquante")
    func timedSetHasNoTonnage() {
        let plank = SetMetricsInput(weightKilograms: 10, reps: 0, loadKind: .weighted, durationSeconds: 60)
        let bench = SetMetricsInput(weightKilograms: 100, reps: 5, loadKind: .external)
        let total = SetMetrics.totalTonnage([plank, bench])
        #expect(total.total == 500)
        #expect(total.unknownSets == 0)
        #expect(SetMetrics.estimatedOneRepMax(plank) == nil)
    }

    @Test("La durée estimée d'une série au temps suit sa cible")
    func durationEstimateUsesTarget() {
        let plank = WorkoutExercisePlan(
            exerciseId: "plank", displayName: "Gainage", setCount: 3, restSeconds: 60,
            measure: .duration, targetDurationSeconds: 120
        )
        #expect(SessionDuration.estimatedSeconds(for: plank) == 3 * 120 + 2 * 60)
    }
}

@Suite("Repos réel")
struct ActualRestTests {
    private let end = Date(timeIntervalSince1970: 1_000_000)

    @Test("Écart entre la série précédente et la validation")
    func measuresGap() {
        #expect(ActualRest.seconds(previousSetEnd: end, validatedAt: end.addingTimeInterval(125)) == 125)
    }

    @Test("La durée d'une série chronométrée est retirée")
    func subtractsTimedWork() {
        #expect(ActualRest.seconds(previousSetEnd: end, validatedAt: end.addingTimeInterval(150), currentSetDurationSeconds: 60) == 90)
        #expect(ActualRest.seconds(previousSetEnd: end, validatedAt: end.addingTimeInterval(30), currentSetDurationSeconds: 60) == 0)
    }

    @Test("Première série, interruption longue ou horloge incohérente : non mesuré")
    func unmeasuredCases() {
        #expect(ActualRest.seconds(previousSetEnd: nil, validatedAt: end) == nil)
        #expect(ActualRest.seconds(previousSetEnd: end, validatedAt: end.addingTimeInterval(3_601)) == nil)
        #expect(ActualRest.seconds(previousSetEnd: end, validatedAt: end.addingTimeInterval(3_600)) == 3_600)
        #expect(ActualRest.seconds(previousSetEnd: end, validatedAt: end.addingTimeInterval(-5)) == nil)
    }
}

@Suite("Note d'effort de séance")
struct SessionEffortTests {
    @Test("Paliers du très facile au maximal")
    func bands() {
        #expect(SessionEffort.band(for: 1) == .veryEasy)
        #expect(SessionEffort.band(for: 4) == .easy)
        #expect(SessionEffort.band(for: 6) == .moderate)
        #expect(SessionEffort.band(for: 8) == .hard)
        #expect(SessionEffort.band(for: 9) == .veryHard)
        #expect(SessionEffort.band(for: 10) == .maximal)
        #expect(SessionEffort.band(for: 0) == nil)
        #expect(SessionEffort.band(for: 11) == nil)
    }

    @Test("Position du doigt sur les barres, toujours bornée")
    func ratingAtFraction() {
        #expect(SessionEffort.rating(atFraction: 0) == 1)
        #expect(SessionEffort.rating(atFraction: 0.55) == 6)
        #expect(SessionEffort.rating(atFraction: 0.999) == 10)
        #expect(SessionEffort.rating(atFraction: 1.5) == 10)
        #expect(SessionEffort.rating(atFraction: -1) == 1)
        #expect(SessionEffort.rating(atFraction: .nan) == 1)
    }
}
