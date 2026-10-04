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
    @Test("Série classique connue : validable avec les valeurs proposées")
    func classicKnownSet() {
        let proposal = LiveActivityPlanning.quickLogProposal(
            for: target(for: classic("Squat")),
            proposedWeightKilograms: 100,
            proposedReps: 8,
            needsReferenceValue: false
        )
        #expect(proposal == .init(weightKilograms: 100, reps: 8))
    }

    @Test("Charge inconnue : jamais validée à zéro")
    func unknownLoadIsNotZero() {
        let proposal = LiveActivityPlanning.quickLogProposal(
            for: target(for: classic("Squat")),
            proposedWeightKilograms: nil,
            proposedReps: 8,
            needsReferenceValue: false
        )
        #expect(proposal == nil)
        let zero = LiveActivityPlanning.quickLogProposal(
            for: target(for: classic("Squat")),
            proposedWeightKilograms: 0,
            proposedReps: 8,
            needsReferenceValue: false
        )
        #expect(zero == nil)
    }

    @Test("Poids du corps : zéro est une vraie charge")
    func bodyweightZeroIsAValue() {
        let proposal = LiveActivityPlanning.quickLogProposal(
            for: target(for: classic("Tractions", loadKind: .bodyweight)),
            proposedWeightKilograms: nil,
            proposedReps: 10,
            needsReferenceValue: false
        )
        #expect(proposal == .init(weightKilograms: 0, reps: 10))
    }

    @Test("Répétitions inconnues, 1RM manquant : ouvrir l'application")
    func missingValuesNeedTheApp() {
        let squat = target(for: classic("Squat"))
        #expect(LiveActivityPlanning.quickLogProposal(for: squat, proposedWeightKilograms: 100, proposedReps: nil, needsReferenceValue: false) == nil)
        #expect(LiveActivityPlanning.quickLogProposal(for: squat, proposedWeightKilograms: 100, proposedReps: 0, needsReferenceValue: false) == nil)
        #expect(LiveActivityPlanning.quickLogProposal(for: squat, proposedWeightKilograms: 100, proposedReps: 8, needsReferenceValue: true) == nil)
    }

    @Test("Palier, format spécial, série au temps : pas de validation d'un tap")
    func onlyPlainClassicSets() {
        let dropset = classic("Curl", format: .dropset)
        #expect(LiveActivityPlanning.quickLogProposal(for: target(for: dropset), proposedWeightKilograms: 20, proposedReps: 10, needsReferenceValue: false) == nil)
        let squat = classic("Squat")
        #expect(LiveActivityPlanning.quickLogProposal(for: target(for: squat, subSetIndex: 1), proposedWeightKilograms: 20, proposedReps: 10, needsReferenceValue: false) == nil)
        var plank = classic("Gainage", loadKind: .bodyweight)
        plank.measure = .duration
        #expect(LiveActivityPlanning.quickLogProposal(for: target(for: plank), proposedWeightKilograms: 0, proposedReps: 1, needsReferenceValue: false) == nil)
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
