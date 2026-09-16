import Foundation
import Testing
@testable import MuscuEngine

@Suite("Décharge réellement appliquée")
struct WeekScalingTests {
    private let deload = WeekScaling(
        volumeMultiplier: 0.5,
        intensityMultiplier: 0.9,
        loadIncrementKilograms: 2.5
    )

    private func exercise(
        format: WorkoutFormat = .classic,
        sets: Int = 4,
        weight: Double? = nil,
        percent: Double? = nil
    ) -> WorkoutExercisePlan {
        WorkoutExercisePlan(
            exerciseId: "squat",
            displayName: "Squat",
            format: format,
            setCount: sets,
            targetWeight: weight,
            percentOneRepMax: percent
        )
    }

    @Test("Une semaine ordinaire ne touche à rien")
    func neutralWeekChangesNothing() {
        let original = exercise(sets: 4, weight: 100)
        #expect(WeekScaling.neutral.applied(to: original) == original)
    }

    @Test("Une décharge réduit réellement le volume")
    func deloadReducesVolume() {
        #expect(deload.applied(to: exercise(sets: 4)).setCount == 2)
        #expect(deload.applied(to: exercise(sets: 5)).setCount == 3)
    }

    @Test("Le volume ne descend jamais sous une série")
    func volumeNeverReachesZero() {
        let severe = WeekScaling(volumeMultiplier: 0.1, intensityMultiplier: 1)
        #expect(severe.applied(to: exercise(sets: 2)).setCount == 1)
        #expect(severe.applied(to: exercise(sets: 1)).setCount == 1)
    }

    @Test("Une décharge réduit réellement la charge, arrondie au palier")
    func deloadReducesLoad() {
        let scaled = deload.applied(to: exercise(weight: 100))
        #expect(scaled.targetWeight == 90)
    }

    /// Le défaut que ce test protège : à 95 % sur 50 kg avec des paliers de
    /// 2,5 kg, l'arrondi ramène sur 50 kg — et la « décharge » n'allège rien.
    @Test("Si l'arrondi ramène sur la charge d'origine, on descend d'un palier")
    func roundingNeverCancelsTheDeload() {
        let gentle = WeekScaling(
            volumeMultiplier: 1,
            intensityMultiplier: 0.99,
            loadIncrementKilograms: 2.5
        )
        let scaled = gentle.applied(to: exercise(weight: 50))
        let weight = try! #require(scaled.targetWeight)
        #expect(weight < 50, "Une décharge qui n'allège pas n'est pas une décharge")
        #expect(weight == 47.5)
    }

    @Test("Le pourcentage de 1RM suit l'intensité et reste dans ses bornes")
    func percentIsScaledAndClamped() {
        #expect(deload.applied(to: exercise(percent: 80)).percentOneRepMax == 72)
        let extreme = WeekScaling(volumeMultiplier: 1, intensityMultiplier: 3)
        #expect(extreme.applied(to: exercise(percent: 80)).percentOneRepMax == 100)
    }

    /// Raccourcir un EMOM change la nature de l'exercice, pas sa dose.
    @Test("Les formats chronométrés ne sont pas mis à l'échelle")
    func timedFormatsAreLeftAlone() {
        for format in [WorkoutFormat.intervals, .emom, .amrap, .forTime] {
            let original = exercise(format: format, sets: 4)
            #expect(deload.applied(to: original).setCount == 4, "\(format) ne doit pas être réduit")
        }
    }

    @Test("Un multiplicateur absurde est ignoré plutôt qu'appliqué")
    func unusableScalingIsIgnored() {
        let original = exercise(sets: 4, weight: 100)
        for broken in [
            WeekScaling(volumeMultiplier: 0, intensityMultiplier: 1),
            WeekScaling(volumeMultiplier: .nan, intensityMultiplier: 1),
            WeekScaling(volumeMultiplier: 1, intensityMultiplier: .infinity),
            WeekScaling(volumeMultiplier: 50, intensityMultiplier: 1),
            WeekScaling(volumeMultiplier: 1, intensityMultiplier: -1),
        ] {
            #expect(broken.applied(to: original) == original)
        }
    }

    @Test("La mise à l'échelle traverse tout le déroulé, groupes compris")
    func scalingReachesEveryExerciseOfThePlan() {
        let plan = WorkoutPlan(nodes: [
            WorkoutNode(kind: .single, exercises: [exercise(sets: 4, weight: 100)]),
            WorkoutNode(
                kind: .superset,
                exercises: [exercise(sets: 4, weight: 60), exercise(sets: 4, percent: 80)],
                rounds: 3
            ),
        ])
        let scaled = deload.applied(to: plan)
        #expect(scaled.allExercises.allSatisfy { $0.setCount == 2 })
        #expect(scaled.nodes[0].exercises[0].targetWeight == 90)
        #expect(scaled.nodes[1].exercises[0].targetWeight == 55)
        #expect(scaled.nodes[1].exercises[1].percentOneRepMax == 72)
        // Le nombre de tours d'un groupe n'est pas une série de travail.
        #expect(scaled.nodes[1].rounds == 3)
    }
}

@Suite("Check-in de forme appliqué")
struct ReadinessScalingTests {
    /// Le défaut corrigé : `ReadinessAdvisor` proposait « réduire le volume
    /// d'environ 30 % » et **rien ne pouvait l'appliquer**. La suggestion
    /// était une phrase.
    @Test("Une réduction de volume devient une mise à l'échelle applicable")
    func volumeReductionBecomesScaling() throws {
        let scaling = try #require(WeekScaling(readiness: .reduceVolume(multiplier: 0.7)))
        #expect(scaling.volumeMultiplier == 0.7)
        #expect(scaling.intensityMultiplier == 1, "Réduire le volume ne touche pas aux charges")
    }

    @Test("Une réduction de charge n'enlève aucune série")
    func loadReductionOnlyTouchesTheLoad() throws {
        let scaling = try #require(WeekScaling(readiness: .reduceLoad(multiplier: 0.9)))
        #expect(scaling.volumeMultiplier == 1)
        #expect(scaling.intensityMultiplier == 0.9)
    }

    /// Une substitution ou du repos demandent une décision humaine, pas une
    /// multiplication : les traduire en chiffres serait inventer.
    @Test("Les suggestions non chiffrées ne produisent aucune mise à l'échelle")
    func nonNumericSuggestionsProduceNothing() {
        #expect(WeekScaling(readiness: .keepAsPlanned) == nil)
        #expect(WeekScaling(readiness: .suggestRest) == nil)
        #expect(WeekScaling(readiness: .suggestSubstitution(area: "épaule")) == nil)
    }

    /// Une semaine de décharge ET un check-in prudent répondent à deux
    /// raisons différentes d'alléger : ils doivent se cumuler.
    @Test("Une décharge et un check-in se cumulent")
    func deloadAndReadinessCombine() throws {
        let deload = WeekScaling(volumeMultiplier: 0.5, intensityMultiplier: 0.9)
        let readiness = try #require(WeekScaling(readiness: .reduceVolume(multiplier: 0.8)))
        let combined = deload.combined(with: readiness)
        #expect(combined.volumeMultiplier == 0.4)
        #expect(combined.intensityMultiplier == 0.9)
    }

    @Test("Se combiner avec le neutre ne change rien")
    func combiningWithNeutralChangesNothing() {
        let deload = WeekScaling(volumeMultiplier: 0.5, intensityMultiplier: 0.9)
        #expect(deload.combined(with: .neutral) == deload)
    }
}
