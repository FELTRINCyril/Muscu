import Foundation
import Testing
@testable import MuscuEngine

@Suite
struct WorkoutStateMachineTests {
    // MARK: - Fabriques

    private func classic(_ name: String, sets: Int = 3, rest: Int = 90) -> WorkoutExercisePlan {
        WorkoutExercisePlan(
            exerciseId: name.lowercased(),
            displayName: name,
            format: .classic,
            loadKind: .external,
            setCount: sets,
            repsLower: 8,
            repsUpper: 12,
            restSeconds: rest
        )
    }

    private func superset(rounds: Int = 3, betweenExercises: Int = 0, betweenRounds: Int = 90) -> WorkoutNode {
        WorkoutNode(
            kind: .superset,
            exercises: [classic("Développé"), classic("Rowing")],
            rounds: rounds,
            restBetweenExercisesSeconds: betweenExercises,
            restBetweenRoundsSeconds: betweenRounds
        )
    }

    /// Deroule la seance jusqu'au bout en validant chaque etape, et renvoie
    /// la suite des cibles rencontrees et des repos declenches.
    private func run(
        _ plan: WorkoutPlan,
        outcome: @escaping (WorkoutSetTarget) -> WorkoutSetOutcome = { _ in WorkoutSetOutcome(reps: 10) },
        limit: Int = 500
    ) -> (targets: [WorkoutSetTarget], rests: [RestInstruction]) {
        var position = WorkoutPosition.start
        var targets: [WorkoutSetTarget] = []
        var rests: [RestInstruction] = []
        var iterations = 0
        while iterations < limit {
            iterations += 1
            switch WorkoutStateMachine.step(at: position, in: plan) {
            case .finished:
                return (targets, rests)
            case .timedBlock:
                position = WorkoutStateMachine.advance(from: position, in: plan, outcome: WorkoutSetOutcome(reps: 0)).position
            case .logSet(let target):
                targets.append(target)
                let result = WorkoutStateMachine.advance(from: position, in: plan, outcome: outcome(target))
                if let rest = result.rest { rests.append(rest) }
                position = result.position
            }
        }
        Issue.record("La machine à états n'a pas terminé en \(limit) étapes")
        return (targets, rests)
    }

    // MARK: - Classique

    @Test
    func testSingleExerciseRunsEverySetThenFinishes() {
        let plan = WorkoutPlan(nodes: [.single(classic("Squat", sets: 3))])
        let result = run(plan)
        #expect(result.targets.count == 3)
        #expect(result.targets.map(\.setNumber) == [1, 2, 3])
        #expect(result.targets.allSatisfy { $0.totalSets == 3 })
        // Un repos apres chaque serie sauf la derniere : la seance est finie.
        #expect(result.rests.count == 2)
        #expect(result.rests.allSatisfy { $0.reason == .betweenSets && $0.seconds == 90 })
    }

    @Test
    func testRestIsProposedBetweenExercisesButNotAfterTheLastOne() {
        let plan = WorkoutPlan(nodes: [
            .single(classic("Squat", sets: 1)),
            .single(classic("Développé", sets: 1)),
        ])
        let result = run(plan)
        #expect(result.targets.count == 2)
        #expect(result.rests.count == 1)
    }

    @Test
    func testEmptyNodesAreSkippedNotBlocking() {
        let plan = WorkoutPlan(nodes: [
            WorkoutNode(kind: .superset, exercises: [], rounds: 3),
            .single(classic("Squat", sets: 1)),
        ])
        let result = run(plan)
        #expect(result.targets.count == 1)
        #expect(result.targets.first?.exercise.displayName == "Squat")
    }

    @Test
    func testEmptyPlanIsImmediatelyFinished() {
        let plan = WorkoutPlan(nodes: [])
        #expect(WorkoutStateMachine.step(at: .start, in: plan) == .finished)
        #expect(WorkoutStateMachine.isFinished(.start, in: plan))
    }

    // MARK: - Superset

    @Test
    func testSupersetAlternatesExercisesThenStartsNextRound() {
        let plan = WorkoutPlan(nodes: [superset(rounds: 3)])
        let result = run(plan)

        #expect(result.targets.count == 6)
        #expect(result.targets.map(\.exercise.displayName) == [
            "Développé", "Rowing", "Développé", "Rowing", "Développé", "Rowing",
        ])
        #expect(result.targets.map(\.round) == [1, 1, 2, 2, 3, 3])
        #expect(result.targets.map(\.memberPosition) == [1, 2, 1, 2, 1, 2])
        #expect(result.targets.allSatisfy { $0.totalRounds == 3 && $0.totalMembers == 2 })
    }

    // Le repos de fin de tour est lance apres le DERNIER exercice du tour,
    // jamais entre A1 et A2 quand il est configure a zero.
    @Test
    func testSupersetRestsBetweenRoundsOnly() {
        let plan = WorkoutPlan(nodes: [superset(rounds: 3, betweenExercises: 0, betweenRounds: 90)])
        let result = run(plan)
        #expect(result.rests.count == 2)
        #expect(result.rests.allSatisfy { $0.reason == .betweenRounds && $0.seconds == 90 })
    }

    @Test
    func testSupersetShortRestBetweenExercisesWhenConfigured() {
        let plan = WorkoutPlan(nodes: [superset(rounds: 2, betweenExercises: 15, betweenRounds: 120)])
        let result = run(plan)
        #expect(result.rests.map(\.reason) == [.betweenExercisesInGroup, .betweenRounds, .betweenExercisesInGroup])
        #expect(result.rests.map(\.seconds) == [15, 120, 15])
    }

    @Test
    func testSupersetRestIsNotProposedAfterTheLastRoundOfTheSession() {
        let plan = WorkoutPlan(nodes: [superset(rounds: 2, betweenExercises: 0, betweenRounds: 90)])
        let result = run(plan)
        #expect(result.rests.count == 1)
    }

    @Test
    func testSkippingOneExerciseKeepsTheGroupIntact() {
        let plan = WorkoutPlan(nodes: [superset(rounds: 2)])
        // On passe A1 du premier tour : on doit arriver sur A2, meme tour.
        let next = WorkoutStateMachine.skipExercise(from: .start, in: plan)
        guard case .logSet(let target) = WorkoutStateMachine.step(at: next, in: plan) else {
            Issue.record("Une série était attendue après avoir passé un exercice")
            return
        }
        #expect(target.exercise.displayName == "Rowing")
        #expect(target.round == 1)
    }

    // MARK: - Circuit

    @Test
    func testCircuitRunsEveryStationEachRound() {
        let node = WorkoutNode(
            kind: .circuit,
            exercises: [classic("Burpees"), classic("Kettlebell"), classic("Corde")],
            rounds: 4,
            restBetweenExercisesSeconds: 0,
            restBetweenRoundsSeconds: 60,
            transitionSeconds: 10
        )
        let result = run(WorkoutPlan(nodes: [node]))
        #expect(result.targets.count == 12)
        // La transition entre stations remplace le repos entre exercices.
        #expect(result.rests.filter { $0.reason == .stationTransition }.count == 8)
        #expect(result.rests.filter { $0.reason == .betweenRounds }.count == 3)
    }

    // MARK: - Reprise

    /// Critere de la roadmap : une seance doit reprendre EXACTEMENT au bon
    /// endroit apres fermeture de l'app, a chaque transition possible.
    @Test
    func testResumeAtEveryTransitionYieldsTheSameSequence() {
        let plan = WorkoutPlan(nodes: [
            superset(rounds: 2, betweenExercises: 15, betweenRounds: 90),
            .single(classic("Squat", sets: 2)),
        ])
        let reference = run(plan)

        // Pour chaque etape, on rejoue depuis le debut, on « coupe » l'app a
        // cette etape, puis on reprend depuis la position persistee.
        for cut in 0..<reference.targets.count {
            var position = WorkoutPosition.start
            for _ in 0..<cut {
                position = WorkoutStateMachine.advance(from: position, in: plan, outcome: WorkoutSetOutcome(reps: 10)).position
            }
            // Reprise : la position seule doit suffire a retrouver l'etape.
            let encoded = try? JSONEncoder().encode(position)
            let restored = encoded.flatMap { try? JSONDecoder().decode(WorkoutPosition.self, from: $0) }
            #expect(restored == position)

            guard case .logSet(let target) = WorkoutStateMachine.step(at: restored ?? position, in: plan) else {
                Issue.record("Reprise impossible à l'étape \(cut)")
                continue
            }
            #expect(target.exercise.displayName == reference.targets[cut].exercise.displayName)
            #expect(target.round == reference.targets[cut].round)
            #expect(target.memberPosition == reference.targets[cut].memberPosition)
            #expect(target.setNumber == reference.targets[cut].setNumber)
        }
    }

    @Test
    func testCorruptedPositionIsClampedIntoThePlan() {
        let plan = WorkoutPlan(nodes: [superset(rounds: 2)])
        let corrupted = WorkoutPosition(nodeIndex: 99, round: 99, memberIndex: 99, setIndex: 99, subSetIndex: -5)
        let clamped = WorkoutStateMachine.clamp(corrupted, in: plan)
        #expect(clamped.nodeIndex == plan.nodes.count)
        #expect(WorkoutStateMachine.isFinished(corrupted, in: plan))

        let negative = WorkoutPosition(nodeIndex: -3, round: -2, memberIndex: -1, setIndex: -4, subSetIndex: -1)
        let fixed = WorkoutStateMachine.clamp(negative, in: plan)
        #expect(fixed == WorkoutPosition.start)
    }

    // MARK: - Progression

    @Test
    func testProgressCountsRealSlots() {
        let plan = WorkoutPlan(nodes: [superset(rounds: 2), .single(classic("Squat", sets: 3))])
        #expect(WorkoutStateMachine.progress(at: .start, in: plan).total == 7)

        var position = WorkoutPosition.start
        for expected in 1...7 {
            position = WorkoutStateMachine.advance(from: position, in: plan, outcome: WorkoutSetOutcome(reps: 10)).position
            #expect(WorkoutStateMachine.progress(at: position, in: plan).completed == expected)
        }
        #expect(WorkoutStateMachine.isFinished(position, in: plan))
    }
}

@Suite
struct WorkoutAdvancedFormatTests {
    private func base(_ format: WorkoutFormat, sets: Int = 2, rest: Int = 120) -> WorkoutExercisePlan {
        WorkoutExercisePlan(
            exerciseId: "curl",
            displayName: "Curl",
            format: format,
            loadKind: .external,
            setCount: sets,
            repsLower: 8,
            repsUpper: 12,
            restSeconds: rest
        )
    }

    private func sequence(
        _ plan: WorkoutPlan,
        outcome: @escaping (WorkoutSetTarget) -> WorkoutSetOutcome,
        limit: Int = 200
    ) -> (targets: [WorkoutSetTarget], rests: [RestInstruction]) {
        var position = WorkoutPosition.start
        var targets: [WorkoutSetTarget] = []
        var rests: [RestInstruction] = []
        var iterations = 0
        while iterations < limit {
            iterations += 1
            guard case .logSet(let target) = WorkoutStateMachine.step(at: position, in: plan) else {
                return (targets, rests)
            }
            targets.append(target)
            let result = WorkoutStateMachine.advance(from: position, in: plan, outcome: outcome(target))
            if let rest = result.rest { rests.append(rest) }
            position = result.position
        }
        Issue.record("La machine à états n'a pas terminé en \(limit) étapes")
        return (targets, rests)
    }

    // MARK: - Dropset

    @Test
    func testDropsetRunsPrincipalSetThenEveryDrop() {
        var exercise = base(.dropset, sets: 2)
        exercise.dropset = DropsetPlan(drops: [20, 20], usesPercent: true, restSeconds: 0)
        let result = sequence(WorkoutPlan(nodes: [.single(exercise)])) { _ in WorkoutSetOutcome(reps: 8, weightKilograms: 40) }

        // 2 series x (1 principale + 2 paliers) = 6 saisies.
        #expect(result.targets.count == 6)
        #expect(result.targets.map(\.subSetIndex) == [0, 1, 2, 0, 1, 2])
        #expect(result.targets.map(\.setNumber) == [1, 1, 1, 2, 2, 2])
        // Aucun repos entre paliers (0 s configure), un repos apres la
        // premiere serie complete, aucun apres la derniere.
        #expect(result.rests.count == 1)
        #expect(result.rests.first?.reason == .betweenSets)
    }

    @Test
    func testDropsetRestBetweenDropsWhenConfigured() {
        var exercise = base(.dropset, sets: 1)
        exercise.dropset = DropsetPlan(drops: [10], usesPercent: false, restSeconds: 15)
        let result = sequence(WorkoutPlan(nodes: [.single(exercise)])) { _ in WorkoutSetOutcome(reps: 8) }
        #expect(result.targets.count == 2)
        #expect(result.rests.map(\.reason) == [.betweenSubSets])
        #expect(result.rests.map(\.seconds) == [15])
    }

    @Test
    func testDropsetLoadsAreCumulativeAndRoundedToRealPlates() {
        let percent = DropsetPlan(drops: [20, 20], usesPercent: true)
        #expect(percent.loads(startingFrom: 100) == [80, 62.5])

        let kilos = DropsetPlan(drops: [10, 10], usesPercent: false)
        #expect(kilos.loads(startingFrom: 60) == [50, 40])

        // La charge ne descend jamais sous zero.
        let deep = DropsetPlan(drops: [50, 50, 50, 50, 50], usesPercent: false)
        #expect(deep.loads(startingFrom: 60).last == 0)
    }

    @Test
    func testInvalidDropsetIsIgnoredRatherThanApplied() {
        var exercise = base(.dropset, sets: 1)
        exercise.dropset = DropsetPlan(drops: [], usesPercent: true)
        let result = sequence(WorkoutPlan(nodes: [.single(exercise)])) { _ in WorkoutSetOutcome(reps: 8) }
        #expect(result.targets.count == 1)
    }

    // MARK: - Rest-pause

    @Test
    func testRestPauseStopsOnTheRepetitionThreshold() {
        var exercise = base(.restPause, sets: 1)
        exercise.restPause = RestPausePlan(microRestSeconds: 15, maximumMiniSets: 4, minimumReps: 3)
        var repsByCall = [10, 5, 2]
        let result = sequence(WorkoutPlan(nodes: [.single(exercise)])) { _ in
            WorkoutSetOutcome(reps: repsByCall.isEmpty ? 0 : repsByCall.removeFirst())
        }
        // Serie principale, puis deux mini-series : la derniere (2 reps) est
        // sous le seuil, le bloc s'arrete.
        #expect(result.targets.count == 3)
        #expect(result.rests.map(\.reason) == [.betweenSubSets, .betweenSubSets])
    }

    @Test
    func testRestPauseRespectsTheMaximumNumberOfMiniSets() {
        var exercise = base(.restPause, sets: 1)
        exercise.restPause = RestPausePlan(microRestSeconds: 10, maximumMiniSets: 2, minimumReps: 1)
        let result = sequence(WorkoutPlan(nodes: [.single(exercise)])) { _ in WorkoutSetOutcome(reps: 10) }
        #expect(result.targets.count == 3)
    }

    @Test
    func testUserCanStopRestPauseManually() {
        var exercise = base(.restPause, sets: 1)
        exercise.restPause = RestPausePlan(microRestSeconds: 10, maximumMiniSets: 5, minimumReps: 1)
        let result = sequence(WorkoutPlan(nodes: [.single(exercise)])) { target in
            WorkoutSetOutcome(reps: 10, stopsSubSets: target.subSetIndex == 1)
        }
        #expect(result.targets.count == 2)
    }

    // MARK: - Myo-reps

    @Test
    func testMyoRepsStopsWhenMiniSetsFallShort() {
        var exercise = base(.myoReps, sets: 1)
        exercise.myoReps = MyoRepsPlan(
            activationRepsLower: 12,
            activationRepsUpper: 15,
            targetRepsInReserve: 1,
            miniSetReps: 5,
            maximumMiniSets: 5,
            restSeconds: 20
        )
        var repsByCall = [15, 5, 5, 3]
        let result = sequence(WorkoutPlan(nodes: [.single(exercise)])) { _ in
            WorkoutSetOutcome(reps: repsByCall.isEmpty ? 0 : repsByCall.removeFirst())
        }
        #expect(result.targets.count == 4)
        // La serie d'activation vise la plage d'activation, les mini-series
        // le nombre de repetitions configure.
        #expect(result.targets[0].targetRepsLower == 12)
        #expect(result.targets[0].targetRepsUpper == 15)
        #expect(result.targets[1].targetRepsLower == 5)
    }

    // MARK: - Pyramide

    @Test
    func testPyramidUsesOneSlotPerStepAndAdaptiveRest() {
        var exercise = base(.pyramid)
        exercise.pyramidReps = [2, 4, 6, 4, 2]
        exercise.pyramidMinRest = 30
        exercise.pyramidMaxRest = 180
        let result = sequence(WorkoutPlan(nodes: [.single(exercise)])) { target in
            WorkoutSetOutcome(reps: target.targetRepsLower)
        }

        #expect(result.targets.count == 5)
        #expect(result.targets.map(\.targetRepsLower) == [2, 4, 6, 4, 2])
        // Un repos apres chaque palier sauf le dernier, calcule sur
        // l'intensite relative du palier realise.
        #expect(result.rests.count == 4)
        #expect(result.rests[2].seconds == Pyramid.adaptiveRest(repsDone: 6, maxReps: 6, minRest: 30, maxRest: 180))
        #expect(result.rests[0].seconds < result.rests[2].seconds)
    }

    // MARK: - Formats chronometres

    @Test
    func testTimedFormatsHandOverToTheirOwnScreen() {
        for format in [WorkoutFormat.intervals, .emom, .amrap, .forTime] {
            let plan = WorkoutPlan(nodes: [.single(base(format))])
            guard case .timedBlock(let exercise) = WorkoutStateMachine.step(at: .start, in: plan) else {
                Issue.record("Un bloc chronométré était attendu pour \(format)")
                continue
            }
            #expect(exercise.format == format)
            // Un bloc chronometre occupe un seul creneau.
            #expect(exercise.slotCount == 1)
            let after = WorkoutStateMachine.advance(from: .start, in: plan, outcome: WorkoutSetOutcome(reps: 0))
            #expect(WorkoutStateMachine.isFinished(after.position, in: plan))
            #expect(after.rest == nil)
        }
    }
}
