import Foundation
import Testing
@testable import MuscuEngine

@Suite("Recalcul d'un record après correction")
struct RecordRevisionTests {
    private let edited = UUID()
    private let other = UUID()

    private func value(_ v: Double, _ session: UUID?) -> RecordValue {
        RecordValue(value: v, sessionId: session)
    }

    @Test("Un record venu d'ailleurs ne redescend jamais")
    func foreignRecordNeverRegresses() {
        let decision = RecordRevision.revise(
            current: value(140, other),
            attributedToEditedSession: false,
            editedSessionBest: value(100, edited),
            otherSessionsBest: value(140, other),
            lowerIsBetter: false
        )
        #expect(decision == .keep)
    }

    @Test("Une correction qui améliore un record l'applique")
    func editImprovesRecord() {
        let decision = RecordRevision.revise(
            current: value(140, other),
            attributedToEditedSession: false,
            editedSessionBest: value(150, edited),
            otherSessionsBest: value(140, other),
            lowerIsBetter: false
        )
        #expect(decision == .set(value(150, edited)))
    }

    @Test("Série abaissée : le record redescend à la meilleure valeur de l'historique")
    func loweredSetFallsBackToHistory() {
        let decision = RecordRevision.revise(
            current: value(150, edited),
            attributedToEditedSession: true,
            editedSessionBest: value(120, edited),
            otherSessionsBest: value(140, other),
            lowerIsBetter: false
        )
        #expect(decision == .set(value(140, other)))
    }

    @Test("Série supprimée sans autre historique : le record disparaît")
    func deletedSetWithoutHistoryRemovesRecord() {
        let decision = RecordRevision.revise(
            current: value(150, edited),
            attributedToEditedSession: true,
            editedSessionBest: nil,
            otherSessionsBest: nil,
            lowerIsBetter: false
        )
        #expect(decision == .remove)
    }

    @Test("Record de temps : plus bas est meilleur")
    func timeRecordLowerIsBetter() {
        let decision = RecordRevision.revise(
            current: value(180, edited),
            attributedToEditedSession: true,
            editedSessionBest: value(200, edited),
            otherSessionsBest: value(190, other),
            lowerIsBetter: true
        )
        #expect(decision == .set(value(190, other)))
    }

    @Test("Record validé à la main : l'historique ne le fait pas monter")
    func confirmedRecordIsNotRaisedFromOtherSessions() {
        let decision = RecordRevision.revise(
            current: value(140, nil),
            attributedToEditedSession: true,
            editedSessionBest: value(120, nil),
            otherSessionsBest: value(160, nil),
            lowerIsBetter: false,
            raisesFromOtherSessions: false
        )
        #expect(decision == .keep)
    }

    @Test("Séance toujours au niveau du record : rien ne change")
    func unchangedRecordIsKept() {
        let decision = RecordRevision.revise(
            current: value(150, edited),
            attributedToEditedSession: true,
            editedSessionBest: value(150, edited),
            otherSessionsBest: value(140, other),
            lowerIsBetter: false
        )
        #expect(decision == .keep)
    }

    @Test("Aucun record : seule la séance corrigée peut en créer un")
    func missingRecordIsCreatedOnlyFromEditedSession() {
        #expect(RecordRevision.revise(
            current: nil,
            attributedToEditedSession: false,
            editedSessionBest: nil,
            otherSessionsBest: value(100, other),
            lowerIsBetter: false
        ) == .keep)
        #expect(RecordRevision.revise(
            current: nil,
            attributedToEditedSession: false,
            editedSessionBest: value(90, edited),
            otherSessionsBest: nil,
            lowerIsBetter: false
        ) == .set(value(90, edited)))
    }
}

@Suite("Refaire une séance")
struct SessionReplayTests {
    private func set(
        _ id: String,
        order: Int,
        weight: Double = 0,
        reps: Int = 0,
        working: Bool = true,
        sub: Int = 0,
        duration: Int? = nil,
        distance: Double? = nil
    ) -> ReplaySourceSet {
        ReplaySourceSet(
            exerciseId: id,
            displayName: id,
            orderIndex: order,
            subSetIndex: sub,
            isPrescribedWorkingSet: working,
            weightKilograms: weight,
            reps: reps,
            durationSeconds: duration,
            distanceMeters: distance,
            loadKind: .external
        )
    }

    private var sets: [ReplaySourceSet] {
        [
            set("squat", order: 0, weight: 40, reps: 10, working: false),
            set("squat", order: 0, weight: 100, reps: 5),
            set("squat", order: 0, weight: 100, reps: 5),
            set("squat", order: 0, weight: 100, reps: 4),
            set("gainage", order: 1, duration: 45),
            set("gainage", order: 1, duration: 60),
            set("rowing", order: 2, weight: 60, reps: 10),
            set("rowing", order: 2, weight: 50, reps: 8, sub: 1),
        ]
    }

    @Test("Refaire reprend exercices, séries et valeurs comme cibles")
    func replayWithTargets() {
        let plan = SessionReplay.plan(from: sets, mode: .withTargets, restSeconds: { _ in 120 })
        let exercises = plan.allExercises
        #expect(exercises.map(\.exerciseId) == ["squat", "gainage", "rowing"])
        #expect(exercises[0].setCount == 3)
        #expect(exercises[0].targetWeight == 100)
        #expect(exercises[0].repsLower == 4)
        #expect(exercises[0].repsUpper == 5)
        #expect(exercises[0].restSeconds == 120)
        #expect(exercises[1].measure == .duration)
        #expect(exercises[1].targetDurationSeconds == 60)
        // Le palier de dropset n'est pas une serie de plus.
        #expect(exercises[2].setCount == 1)
        #expect(plan.nodes.allSatisfy { !$0.isGroup })
    }

    @Test("Refaire à vide ne reprend aucune valeur")
    func replayEmpty() {
        let plan = SessionReplay.plan(from: sets, mode: .empty)
        let exercises = plan.allExercises
        #expect(exercises[0].setCount == 3)
        #expect(exercises[0].targetWeight == nil)
        #expect(exercises[0].repsLower == SessionReplay.defaultRepsLower)
        #expect(exercises[1].targetDurationSeconds == SetMeasure.defaultTargetDurationSeconds)
    }

    @Test("Charge usuelle : la plus fréquente, puis la plus lourde")
    func usualWeight() {
        let mixed = [set("a", order: 0, weight: 80, reps: 5), set("a", order: 0, weight: 90, reps: 5)]
        #expect(SessionReplay.usualWeight(of: mixed) == 90)
        #expect(SessionReplay.usualWeight(of: [set("a", order: 0, reps: 10)]) == nil)
    }
}

@Suite("Différences de structure avec le programme")
struct SessionStructureDiffTests {
    private func entry(_ id: UUID, _ exercise: String, sets: Int? = 3, measure: SetMeasure = .weightReps) -> SessionStructureEntry {
        SessionStructureEntry(id: id, exerciseId: exercise, displayName: exercise, setCount: sets, measure: measure)
    }

    private let a = UUID()
    private let b = UUID()
    private let c = UUID()

    @Test("Rien n'a changé : aucune proposition")
    func noChange() {
        let baseline = [entry(a, "squat"), entry(b, "bench")]
        #expect(SessionStructureDiff.changes(baseline: baseline, final: baseline).isEmpty)
    }

    @Test("Ajout, retrait, remplacement, séries et mesure")
    func detectsEachKind() {
        let d = UUID()
        let baseline = [entry(a, "squat"), entry(b, "bench"), entry(c, "row"), entry(d, "plank")]
        let added = entry(UUID(), "curl")
        let final = [
            entry(a, "squat", sets: 4),
            entry(b, "dips"),
            entry(d, "plank", measure: .duration),
            added,
        ]
        let changes = SessionStructureDiff.changes(baseline: baseline, final: final)
        #expect(changes.contains(.added(added)))
        #expect(changes.contains(.removed(entry(c, "row"))))
        #expect(changes.contains(.replaced(from: entry(b, "bench"), to: entry(b, "dips"))))
        #expect(changes.contains(.setCount(entry(a, "squat", sets: 4), from: 3, to: 4)))
        #expect(changes.contains(.measure(entry(d, "plank", measure: .duration), from: .weightReps, to: .duration)))
        #expect(changes.count == 5)
    }

    @Test("Seul l'exercice réellement déplacé est signalé")
    func onlyMovedExerciseIsReported() {
        let baseline = [entry(a, "a"), entry(b, "b"), entry(c, "c")]
        let final = [entry(c, "c"), entry(a, "a"), entry(b, "b")]
        let changes = SessionStructureDiff.changes(baseline: baseline, final: final)
        #expect(changes == [.moved(entry(c, "c"))])
    }

    @Test("Un ajout ne fait pas croire à un déplacement")
    func insertionIsNotAMove() {
        let inserted = entry(UUID(), "x")
        let baseline = [entry(a, "a"), entry(b, "b")]
        let final = [entry(a, "a"), inserted, entry(b, "b")]
        #expect(SessionStructureDiff.changes(baseline: baseline, final: final) == [.added(inserted)])
    }

    @Test("Structure d'un déroulé : séries, tours de groupe, formats non comptés")
    func entriesOfPlan() {
        let single = WorkoutExercisePlan(exerciseId: "squat", displayName: "Squat", setCount: 4)
        let pyramid = WorkoutExercisePlan(exerciseId: "dips", displayName: "Dips", format: .pyramid)
        let groupID = UUID()
        let group = WorkoutNode(
            id: groupID,
            kind: .superset,
            exercises: [
                WorkoutExercisePlan(exerciseId: "curl", displayName: "Curl"),
                WorkoutExercisePlan(exerciseId: "ext", displayName: "Ext"),
            ],
            rounds: 5
        )
        let entries = SessionStructureDiff.entries(of: WorkoutPlan(nodes: [.single(single), .single(pyramid), group]))
        #expect(entries.map(\.setCount) == [4, nil, 5, 5])
        #expect(entries[2].groupId == groupID)
    }
}

@Suite("Temps actif et temps de repos")
struct SessionTimeBreakdownTests {
    @Test("Repos mesuré : répartition calculée")
    func measuredRest() {
        let breakdown = SessionTimeBreakdown.make(totalSeconds: 3_600, sets: [
            .init(sequenceIndex: 0, restSeconds: nil),
            .init(sequenceIndex: 1, restSeconds: 120),
            .init(sequenceIndex: 2, restSeconds: 180),
        ])
        #expect(breakdown == SessionTimeBreakdown(activeSeconds: 3_300, restSeconds: 300))
    }

    @Test("Un repos manquant : rien n'est affiché plutôt qu'inventé")
    func missingRestHidesBreakdown() {
        #expect(SessionTimeBreakdown.make(totalSeconds: 3_600, sets: [
            .init(sequenceIndex: 0, restSeconds: nil),
            .init(sequenceIndex: 1, restSeconds: nil),
        ]) == nil)
        #expect(SessionTimeBreakdown.make(totalSeconds: 3_600, sets: [.init(sequenceIndex: 0, restSeconds: nil)]) == nil)
    }

    @Test("Repos supérieur à la durée : incohérent, non affiché")
    func inconsistentRest() {
        #expect(SessionTimeBreakdown.make(totalSeconds: 100, sets: [
            .init(sequenceIndex: 0, restSeconds: nil),
            .init(sequenceIndex: 1, restSeconds: 200),
        ]) == nil)
    }
}

@Suite("Correction d'une séance passée")
struct PastSessionEditTests {
    private let now = Date(timeIntervalSince1970: 1_780_000_000)

    @Test("Horaires")
    func timing() {
        let start = now.addingTimeInterval(-3_600)
        #expect(PastSessionEdit.timingIssue(start: start, end: now, now: now) == nil)
        #expect(PastSessionEdit.timingIssue(start: now, end: start, now: now) == .endBeforeStart)
        #expect(PastSessionEdit.timingIssue(start: start.addingTimeInterval(-90_000), end: now, now: now) == .tooLong)
        #expect(PastSessionEdit.timingIssue(start: now, end: now.addingTimeInterval(3_600), now: now) == .inFuture)
        #expect(PastSessionEdit.durationSeconds(start: start, end: now) == 3_600)
    }

    @Test("Valeurs d'une série")
    func setValues() {
        #expect(PastSessionEdit.isValidSet(weightKilograms: 100, reps: 5, durationSeconds: nil, distanceMeters: nil))
        #expect(PastSessionEdit.isValidSet(weightKilograms: 0, reps: 0, durationSeconds: 60, distanceMeters: nil))
        #expect(!PastSessionEdit.isValidSet(weightKilograms: 100, reps: 0, durationSeconds: nil, distanceMeters: nil))
        #expect(!PastSessionEdit.isValidSet(weightKilograms: -1, reps: 5, durationSeconds: nil, distanceMeters: nil))
        #expect(!PastSessionEdit.isValidSet(weightKilograms: .nan, reps: 5, durationSeconds: nil, distanceMeters: nil))
        #expect(!PastSessionEdit.isValidSet(weightKilograms: 0, reps: 0, durationSeconds: 0, distanceMeters: nil))
    }
}

@Suite("Import : programmes et matériel")
struct ImportedRoutinesTests {
    private let base = Date(timeIntervalSince1970: 1_780_000_000)

    private func session(_ title: String, day: Int, _ exercises: [(String, Int)]) -> ImportedRoutineSession {
        ImportedRoutineSession(
            title: title,
            date: base.addingTimeInterval(Double(day) * 86_400),
            exercises: exercises.map { ImportedRoutineExercise(exerciseId: $0.0, displayName: $0.0, workingSetCount: $0.1) }
        )
    }

    @Test("Regroupement par titre, structure de la plus récente, séries usuelles")
    func groupsByTitle() {
        let candidates = ImportedRoutines.candidates(from: [
            session("Haut du corps", day: 0, [("bench", 4), ("row", 3)]),
            session("  haut   du Corps ", day: 1, [("bench", 4), ("row", 3)]),
            session("Haut du Corps", day: 2, [("bench", 3), ("row", 3), ("curl", 2)]),
            session("Jambes", day: 5, [("squat", 5)]),
            session("", day: 6, [("squat", 5)]),
        ])
        #expect(candidates.map(\.name) == ["Jambes", "Haut du Corps"])
        let upper = candidates[1]
        #expect(upper.sessionCount == 3)
        #expect(upper.exercises.map(\.exerciseId) == ["bench", "row", "curl"])
        // 4 series deux fois sur trois : c'est le nombre usuel.
        #expect(upper.exercises.map(\.workingSetCount) == [4, 3, 2])
    }

    @Test("Nom libre : suffixé, jamais écrasé")
    func uniqueName() {
        #expect(ImportedRoutines.uniqueName("Jambes", taken: ["Haut"]) == "Jambes")
        #expect(ImportedRoutines.uniqueName("Jambes", taken: ["jambes", "Jambes (2)"]) == "Jambes (3)")
    }

    @Test("Matériel déduit du nom entre parenthèses")
    func equipmentSuffix() {
        let deadlift = ExerciseNaming.equipmentSuffix(in: "Deadlift (Barbell)")
        #expect(deadlift?.baseName == "Deadlift")
        #expect(deadlift?.equipment == "barbell")
        #expect(ExerciseNaming.equipmentSuffix(in: "Curl (Haltères)")?.equipment == "dumbbell")
        #expect(ExerciseNaming.equipmentSuffix(in: "Curl (EZ Bar)")?.equipment == "e-z curl bar")
        #expect(ExerciseNaming.equipmentSuffix(in: "Squat (Pause)") == nil)
        #expect(ExerciseNaming.equipmentSuffix(in: "Squat") == nil)
        #expect(ExerciseNaming.equipmentSuffix(in: "(Barbell)") == nil)
    }
}

@Suite("Santé et synchronisation d'une séance corrigée")
struct EditedSessionPropagationTests {
    private let base = Date(timeIntervalSince1970: 1_780_000_000)

    @Test("Une séance corrigée après son écriture est remplacée dans Santé")
    func editedSessionIsReplaced() {
        let id = UUID()
        let session = HealthSyncSession(
            id: id,
            startDate: base,
            durationSeconds: 3_600,
            editedAt: base.addingTimeInterval(7_200)
        )
        let link = HealthSyncLink(completedSessionId: id, workoutIdentifier: "hk-1", writtenAt: base.addingTimeInterval(3_600))
        let plan = HealthSyncPlanner.plan(sessions: [session], links: [link])
        #expect(plan.toReplace == [HealthSyncReplacement(session: session, previousWorkoutIdentifier: "hk-1")])
        #expect(plan.toWrite.isEmpty)
        #expect(plan.alreadyWritten.isEmpty)

        // Corrigee AVANT l'ecriture : deja a jour.
        let early = HealthSyncLink(completedSessionId: id, workoutIdentifier: "hk-1", writtenAt: base.addingTimeInterval(9_000))
        #expect(HealthSyncPlanner.plan(sessions: [session], links: [early]).alreadyWritten == [id])
    }

    @Test("Corrigée sous la durée minimale : l'entraînement est retiré")
    func shortenedSessionIsDeleted() {
        let id = UUID()
        let session = HealthSyncSession(id: id, startDate: base, durationSeconds: 10, editedAt: base.addingTimeInterval(100))
        let link = HealthSyncLink(completedSessionId: id, workoutIdentifier: "hk-1", writtenAt: base)
        let plan = HealthSyncPlanner.plan(sessions: [session], links: [link])
        #expect(plan.toDelete == ["hk-1"])
        #expect(plan.toReplace.isEmpty)
    }

    private func record(id: UUID, updated: TimeInterval, edited: TimeInterval?, payload: String) -> SyncRecord {
        SyncRecord(
            kind: .completedSession,
            metadata: SyncMetadata(identifier: id, createdAt: base, updatedAt: base.addingTimeInterval(updated)),
            payload: Data(payload.utf8),
            editedAt: edited.map { base.addingTimeInterval($0) }
        )
    }

    @Test("Séance terminée : la correction la plus récente gagne")
    func latestCorrectionWins() {
        let id = UUID()
        let original = record(id: id, updated: 0, edited: nil, payload: "origine")
        let corrected = record(id: id, updated: 50, edited: 50, payload: "corrigée")
        let later = record(id: id, updated: 80, edited: 80, payload: "re-corrigée")

        #expect(SyncReconciler.decide(local: original, remote: corrected) == .applyRemote)
        #expect(SyncReconciler.decide(local: corrected, remote: original) == .keepLocal)
        #expect(SyncReconciler.decide(local: corrected, remote: later) == .applyRemote)
        #expect(SyncReconciler.decide(local: later, remote: corrected) == .keepLocal)
        // Sans correction, l'immuabilite d'origine tient toujours.
        let touched = record(id: id, updated: 99, edited: nil, payload: "autre")
        #expect(SyncReconciler.decide(local: original, remote: touched) == .noChange)
    }

    @Test("Ordre d'arrivée indifférent")
    func orderInsensitive() {
        let id = UUID()
        let original = record(id: id, updated: 0, edited: nil, payload: "origine")
        let first = record(id: id, updated: 50, edited: 50, payload: "A")
        let second = record(id: id, updated: 80, edited: 80, payload: "B")
        let forward = SyncReconciler.apply(remote: [first, second], to: [id: original], now: base).state
        let backward = SyncReconciler.apply(remote: [second, first], to: [id: original], now: base).state
        #expect(forward[id]?.payload == Data("B".utf8))
        #expect(backward[id]?.payload == Data("B".utf8))
    }
}
