import Foundation
import Testing
@testable import MuscuEngine

// Lot 6 : Live Activity interactive et reponses Siri.

private func classic(
    _ name: String,
    sets: Int = 3,
    loadKind: LoadKind = .external,
    format: WorkoutFormat = .classic
) -> WorkoutExercisePlan {
    WorkoutExercisePlan(
        exerciseId: name.lowercased(),
        displayName: name,
        format: format,
        loadKind: loadKind,
        setCount: sets,
        repsLower: 8,
        repsUpper: 12,
        restSeconds: 90
    )
}

private func target(for exercise: WorkoutExercisePlan, setNumber: Int = 1, subSetIndex: Int = 0) -> WorkoutSetTarget {
    WorkoutSetTarget(
        exercise: exercise,
        groupId: exercise.id,
        groupKind: .single,
        round: 1,
        totalRounds: 1,
        memberPosition: 1,
        totalMembers: 1,
        setNumber: setNumber,
        totalSets: exercise.setCount,
        subSetIndex: subSetIndex,
        targetRepsLower: 8,
        targetRepsUpper: 12
    )
}

@Suite("Live Activity : validation d'un tap")
struct LiveActivityQuickLogTests {
    @Test("Série classique : les valeurs pré-remplies par la saisie")
    func classicKnownSet() {
        let proposal = LiveActivityPlanning.quickLogProposal(
            for: target(for: classic("Squat")),
            prefillWeightKilograms: 100,
            prefillReps: 8
        )
        #expect(proposal == .init(weightKilograms: 100, reps: 8))
    }

    @Test("Charge laissée à zéro par la saisie : validée à zéro, comme dans l'application")
    func unknownLoadKeepsThePrefill() {
        let proposal = LiveActivityPlanning.quickLogProposal(
            for: target(for: classic("Squat")),
            prefillWeightKilograms: 0,
            prefillReps: 8
        )
        #expect(proposal == .init(weightKilograms: 0, reps: 8))
    }

    @Test("Poids du corps : zéro est une vraie charge")
    func bodyweightZeroIsAValue() {
        let proposal = LiveActivityPlanning.quickLogProposal(
            for: target(for: classic("Tractions", loadKind: .bodyweight)),
            prefillWeightKilograms: 0,
            prefillReps: 10
        )
        #expect(proposal == .init(weightKilograms: 0, reps: 10))
    }

    @Test("Valeurs invalides : rien à valider")
    func invalidValues() {
        let squat = target(for: classic("Squat"))
        #expect(LiveActivityPlanning.quickLogProposal(for: squat, prefillWeightKilograms: 100, prefillReps: 0) == nil)
        #expect(LiveActivityPlanning.quickLogProposal(for: squat, prefillWeightKilograms: -5, prefillReps: 8) == nil)
        #expect(LiveActivityPlanning.quickLogProposal(for: squat, prefillWeightKilograms: .nan, prefillReps: 8) == nil)
    }

    @Test("Dropset, rest-pause, myo-reps : paliers compris, avec la charge pré-remplie")
    func intensityFormatsAreValidated() {
        for format in [WorkoutFormat.dropset, .restPause, .myoReps] {
            let exercise = classic("Curl", format: format)
            #expect(LiveActivityPlanning.quickLogProposal(for: target(for: exercise), prefillWeightKilograms: 20, prefillReps: 10) == .init(weightKilograms: 20, reps: 10))
            #expect(LiveActivityPlanning.quickLogProposal(for: target(for: exercise, subSetIndex: 1), prefillWeightKilograms: 16, prefillReps: 10) == .init(weightKilograms: 16, reps: 10))
        }
    }

    @Test("Pyramide : les répétitions du palier courant, au poids du corps")
    func pyramidStepUsesTheStepReps() {
        var pyramid = classic("Pompes", loadKind: .bodyweight, format: .pyramid)
        pyramid.pyramidReps = [4, 6, 8]
        var step = target(for: pyramid, setNumber: 2)
        step.targetRepsLower = 6
        step.targetRepsUpper = 6
        // La saisie classique n'intervient pas : seul le palier compte.
        let proposal = LiveActivityPlanning.quickLogProposal(for: step, prefillWeightKilograms: 12, prefillReps: 1)
        #expect(proposal == .init(weightKilograms: 0, reps: 6, isPyramidStep: true))
        step.targetRepsLower = 0
        #expect(LiveActivityPlanning.quickLogProposal(for: step, prefillWeightKilograms: 0, prefillReps: 1) == nil)
    }

    @Test("Série au temps et formats chronométrés : pas de validation sans saisie")
    func measuredAndTimedFormatsNeedTheApp() {
        var plank = classic("Gainage", loadKind: .bodyweight)
        plank.measure = .duration
        #expect(LiveActivityPlanning.quickLogProposal(for: target(for: plank), prefillWeightKilograms: 0, prefillReps: 1) == nil)
        for format in [WorkoutFormat.intervals, .emom, .amrap, .forTime] {
            let block = classic("Burpees", loadKind: .bodyweight, format: format)
            #expect(LiveActivityPlanning.quickLogProposal(for: target(for: block), prefillWeightKilograms: 0, prefillReps: 10) == nil)
        }
    }

    @Test("Échauffement : le premier palier de montée en charge non coché")
    func warmupRamp() {
        #expect(LiveActivityPlanning.nextWarmupRampIndex(rampCount: 3, loggedIndexes: []) == 0)
        #expect(LiveActivityPlanning.nextWarmupRampIndex(rampCount: 3, loggedIndexes: [0]) == 1)
        #expect(LiveActivityPlanning.nextWarmupRampIndex(rampCount: 3, loggedIndexes: [1]) == 0)
        #expect(LiveActivityPlanning.nextWarmupRampIndex(rampCount: 3, loggedIndexes: [0, 1, 2]) == nil)
        #expect(LiveActivityPlanning.nextWarmupRampIndex(rampCount: 0, loggedIndexes: []) == nil)
    }
}

@Suite("Repos : −15 s / +15 s")
struct RestAdjustmentTests {
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    @Test("+15 s et −15 s déplacent la fin et la durée totale")
    func stepsMoveTheEnd() {
        let end = now.addingTimeInterval(60)
        #expect(RestAdjustment.adjust(endDate: end, totalSeconds: 90, by: 15, now: now) == .running(endDate: now.addingTimeInterval(75), totalSeconds: 105))
        #expect(RestAdjustment.adjust(endDate: end, totalSeconds: 90, by: -15, now: now) == .running(endDate: now.addingTimeInterval(45), totalSeconds: 75))
    }

    @Test("−15 s ne descend jamais sous zéro : le repos se termine")
    func neverBelowZero() {
        #expect(RestAdjustment.adjust(endDate: now.addingTimeInterval(10), totalSeconds: 90, by: -15, now: now) == .finished)
        #expect(RestAdjustment.adjust(endDate: now.addingTimeInterval(15), totalSeconds: 90, by: -15, now: now) == .finished)
        #expect(RestAdjustment.adjust(endDate: now.addingTimeInterval(-3), totalSeconds: 90, by: -15, now: now) == .finished)
    }

    @Test("+15 s est borné")
    func boundedUpwards() {
        let end = now.addingTimeInterval(Double(RestAdjustment.maximumRemainingSeconds - 5))
        #expect(RestAdjustment.adjust(endDate: end, totalSeconds: 1_800, by: 15, now: now)
            == .running(endDate: now.addingTimeInterval(Double(RestAdjustment.maximumRemainingSeconds)), totalSeconds: 1_805))
    }

    @Test("Seul le pas de 15 s est accepté")
    func onlyTheStep() {
        #expect(RestAdjustment.isAllowed(15))
        #expect(RestAdjustment.isAllowed(-15))
        #expect(!RestAdjustment.isAllowed(30))
        #expect(!RestAdjustment.isAllowed(0))
    }
}

@Suite("Live Activity : série suivante")
struct LiveActivityNextStepTests {
    @Test("Série suivante du même exercice, puis exercice suivant, puis fin")
    func followsTheStateMachine() {
        let plan = WorkoutPlan(nodes: [.single(classic("Squat", sets: 2)), .single(classic("Rowing", sets: 1))])
        let outcome = WorkoutSetOutcome(reps: 8, weightKilograms: 100)

        var position = WorkoutPosition.start
        #expect(LiveActivityPlanning.nextStep(after: position, in: plan, outcome: outcome)
            == .set(exerciseName: "Squat", setNumber: 2, totalSets: 2, isSameExercise: true))

        position = WorkoutStateMachine.advance(from: position, in: plan, outcome: outcome).position
        #expect(LiveActivityPlanning.nextStep(after: position, in: plan, outcome: outcome)
            == .set(exerciseName: "Rowing", setNumber: 1, totalSets: 1, isSameExercise: false))

        position = WorkoutStateMachine.advance(from: position, in: plan, outcome: outcome).position
        #expect(LiveActivityPlanning.nextStep(after: position, in: plan, outcome: outcome) == .finished)
    }

    @Test("La simulation ne déplace rien")
    func simulationIsPure() {
        let plan = WorkoutPlan(nodes: [.single(classic("Squat", sets: 2))])
        let position = WorkoutPosition.start
        _ = LiveActivityPlanning.nextStep(after: position, in: plan, outcome: WorkoutSetOutcome(reps: 8))
        #expect(position == .start)
        #expect(LiveActivityPlanning.nextStep(after: position, in: WorkoutPlan(nodes: []), outcome: WorkoutSetOutcome(reps: 8)) == .finished)
    }
}

@Suite("Fin de séance depuis Siri")
struct SessionEndCheckTests {
    @Test("Pas de séance, séance vide, séance terminable")
    func decisions() {
        #expect(SessionEndCheck.evaluate(hasActiveSession: false, workingSetsLogged: 0, progress: (0, 0), isFreeSession: false) == .noSession)
        #expect(SessionEndCheck.evaluate(hasActiveSession: true, workingSetsLogged: 0, progress: (0, 9), isFreeSession: false) == .nothingLogged)
        #expect(SessionEndCheck.evaluate(hasActiveSession: true, workingSetsLogged: 4, progress: (4, 9), isFreeSession: false)
            == .canFinish(workingSets: 4, remainingSlots: 5))
        #expect(SessionEndCheck.evaluate(hasActiveSession: true, workingSetsLogged: 4, progress: (4, 4), isFreeSession: true)
            == .canFinish(workingSets: 4, remainingSlots: 0))
    }
}

@Suite("Réponses Siri sur les records")
struct RecordAnswersTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    @Test("1RM : meilleure estimation, référence à part, rien d'inventé")
    func oneRepMax() {
        let older = now.addingTimeInterval(-86_400 * 30)
        let answer = RecordAnswers.oneRepMax(
            estimatedCandidates: [
                .init(value: 110, date: older),
                .init(value: 115, date: now),
                .init(value: .nan, date: now),
            ],
            reference: .init(value: 120, date: older)
        )
        #expect(answer.estimated == .init(value: 115, date: now))
        #expect(answer.reference == .init(value: 120, date: older))

        let empty = RecordAnswers.oneRepMax(estimatedCandidates: [], reference: .init(value: 0, date: now))
        #expect(empty.isEmpty)
    }

    @Test("Records récents : du plus récent au plus ancien, bornés")
    func recentRecords() {
        func entry(_ name: String, daysAgo: Double, value: Double = 100) -> RecordAnswers.RecordEntry {
            .init(id: UUID(), exerciseName: name, kindKey: "maxWeight", value: value, achievedAt: now.addingTimeInterval(-daysAgo * 86_400))
        }
        let entries = [
            entry("Squat", daysAgo: 2),
            entry("Développé", daysAgo: 1),
            entry("Ancien", daysAgo: 200),
            entry("Futur", daysAgo: -3),
            entry("Vide", daysAgo: 1, value: 0),
            entry("A", daysAgo: 5), entry("B", daysAgo: 6), entry("C", daysAgo: 7), entry("D", daysAgo: 8),
        ]
        let recent = RecordAnswers.recent(entries, now: now)
        #expect(recent.map(\.exerciseName) == ["Développé", "Squat", "A", "B", "C"])
        #expect(RecordAnswers.recent([], now: now).isEmpty)
    }
}
