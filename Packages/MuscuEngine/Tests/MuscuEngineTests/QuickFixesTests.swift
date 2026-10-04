import Foundation
import Testing
@testable import MuscuEngine

@Suite("Pas de saisie de la charge")
struct LoadStepTests {
    @Test("Le pas du matériel dans le lieu l'emporte")
    func equipmentIncrementWins() {
        let step = LoadStep.inputStepKilograms(
            equipmentIncrement: 2,
            profileIncrementsKilograms: [1.25, 2.5, 5],
            unit: .kilograms
        )
        #expect(step == 2)
    }

    @Test("Sans inventaire, le palier du profil le plus proche du pas usuel")
    func profileIncrementNearestToUsualStep() {
        #expect(LoadStep.inputStepKilograms(equipmentIncrement: nil, profileIncrementsKilograms: [1.25, 2.5, 5], unit: .kilograms) == 2.5)
        #expect(LoadStep.inputStepKilograms(equipmentIncrement: 0, profileIncrementsKilograms: [1, 5], unit: .kilograms) == 1)
    }

    @Test("Un utilisateur en livres avance de 5 lb")
    func poundsUseFivePounds() {
        let step = LoadStep.inputStepKilograms(equipmentIncrement: nil, profileIncrementsKilograms: [], unit: .pounds)
        #expect(abs(MassUnit.pounds.fromKilograms(step) - 5) < 0.0001)
    }

    @Test("Les valeurs aberrantes sont ignorées et la charge ne passe jamais sous zéro")
    func ignoresInvalidValues() {
        #expect(LoadStep.inputStepKilograms(equipmentIncrement: .nan, profileIncrementsKilograms: [-1, 0], unit: .kilograms) == 2.5)
        #expect(LoadStep.stepped(1, by: 2.5, up: false) == 0)
        #expect(LoadStep.stepped(20, by: 1.25, up: true) == 21.25)
    }
}

@Suite("Repos par défaut et dépassement")
struct RestDefaultsTests {
    @Test("La barre et les autres matériels ont chacun leur repos")
    func barbellVersusOthers() {
        let defaults = RestDefaults(barbellSeconds: 180, otherSeconds: 75)
        #expect(defaults.seconds(forEquipment: "barbell") == 180)
        #expect(defaults.seconds(forEquipment: "e-z curl bar") == 180)
        #expect(defaults.seconds(forEquipment: "dumbbell") == 75)
        #expect(defaults.seconds(forEquipment: "machine") == 75)
        #expect(defaults.seconds(forEquipment: nil) == 75)
    }

    @Test("Seul un exercice sans repos prescrit est complété")
    func fillsOnlyMissingRest() {
        let defaults = RestDefaults(barbellSeconds: 180, otherSeconds: 75)
        let prescribed = WorkoutExercisePlan(exerciseId: "bench", displayName: "Développé", restSeconds: 120)
        #expect(defaults.filling(prescribed, equipment: "barbell").restSeconds == 120)

        let missing = WorkoutExercisePlan(exerciseId: "bench", displayName: "Développé", restSeconds: 0)
        #expect(defaults.filling(missing, equipment: "barbell").restSeconds == 180)
        #expect(defaults.filling(missing, equipment: "dumbbell").restSeconds == 75)
    }

    @Test("Le repos adaptatif de la pyramide et les formats chronométrés sont intacts")
    func leavesOtherFormatsAlone() {
        let defaults = RestDefaults(barbellSeconds: 180, otherSeconds: 75)
        for format in [WorkoutFormat.pyramid, .intervals, .emom, .amrap, .forTime] {
            let exercise = WorkoutExercisePlan(exerciseId: "x", displayName: "X", format: format, restSeconds: 0)
            #expect(defaults.filling(exercise, equipment: "barbell").restSeconds == 0)
        }
    }

    @Test("Les réglages hors bornes sont ramenés dans les limites")
    func clampsSettings() {
        let defaults = RestDefaults(barbellSeconds: 0, otherSeconds: 10_000)
        #expect(defaults.barbellSeconds == RestDefaults.allowedRange.lowerBound)
        #expect(defaults.otherSeconds == RestDefaults.allowedRange.upperBound)
    }

    @Test("Le décompte passe en dépassement signé une fois la fin atteinte")
    func countdownBecomesOvertime() {
        let end = Date(timeIntervalSince1970: 1_000)
        let running = RestCountdown(endDate: end, now: end.addingTimeInterval(-65.2))
        #expect(running.remainingSeconds == 66)
        #expect(!running.isOvertime)
        #expect(running.label == "1:06")

        let atEnd = RestCountdown(endDate: end, now: end)
        #expect(atEnd.remainingSeconds == 0)
        #expect(!atEnd.isOvertime)
        #expect(atEnd.label == "0:00")

        let late = RestCountdown(endDate: end, now: end.addingTimeInterval(12.7))
        #expect(late.isOvertime)
        #expect(late.overtimeSeconds == 12)
        #expect(late.label == "+0:12")
    }
}

@Suite("Plafond de répétitions du 1RM estimé")
struct OneRepMaxCeilingTests {
    @Test("Le plafond par défaut reste 12 répétitions")
    func defaultIsTwelve() {
        #expect(SetMetrics.estimatedOneRepMax(SetMetricsInput(weightKilograms: 60, reps: 12, loadKind: .external)) != nil)
        #expect(SetMetrics.estimatedOneRepMax(SetMetricsInput(weightKilograms: 60, reps: 13, loadKind: .external)) == nil)
    }

    @Test("Un plafond abaissé exclut les séries plus longues")
    func lowerCeiling() {
        let eight = SetMetricsInput(weightKilograms: 80, reps: 8, loadKind: .external, maximumRepsForOneRepMax: 5)
        let five = SetMetricsInput(weightKilograms: 90, reps: 5, loadKind: .external, maximumRepsForOneRepMax: 5)
        #expect(SetMetrics.estimatedOneRepMax(eight) == nil)
        #expect(SetMetrics.estimatedOneRepMax(five) == OneRepMax.epley(weight: 90, reps: 5))
    }

    @Test("Un plafond relevé accepte des séries plus longues, dans la limite autorisée")
    func higherCeilingIsBounded() {
        let fifteen = SetMetricsInput(weightKilograms: 50, reps: 15, loadKind: .external, maximumRepsForOneRepMax: 15)
        #expect(SetMetrics.estimatedOneRepMax(fifteen) == OneRepMax.epley(weight: 50, reps: 15))

        let absurd = SetMetricsInput(weightKilograms: 20, reps: 25, loadKind: .external, maximumRepsForOneRepMax: 99)
        #expect(absurd.maximumRepsForOneRepMax == OneRepMaxEstimation.allowedMaximumReps.upperBound)
        #expect(SetMetrics.estimatedOneRepMax(absurd) == nil)
        #expect(SetMetricsInput(weightKilograms: 20, reps: 1, loadKind: .external, maximumRepsForOneRepMax: 0).maximumRepsForOneRepMax == 1)
    }

    @Test("La détection de plateau suit le même plafond")
    func plateauDetectorUsesCeiling() {
        // Trois séances de 10 répétitions : estimables à 12, pas à 5.
        let exposures = (0..<3).map { index in
            ExerciseExposure(
                date: Date(timeIntervalSince1970: Double(1_000 - index)),
                sets: [ExposureSet(weightKilograms: 100, reps: 10)]
            )
        }
        let byDefault = PlateauDetector.detect(exposures: exposures)
        #expect(byDefault.isPlateau)
        #expect(byDefault.factors.first?.contains("133") == true)

        // Avec un plafond de 5, la charge n'est plus estimée : la détection
        // retombe sur les répétitions, qui stagnent tout autant.
        let capped = PlateauDetector.detect(exposures: exposures, maximumRepsForOneRepMax: 5)
        #expect(capped.factors.first?.contains("133") == false)
    }

    @Test("La formule affichée dit le plafond réellement appliqué")
    func formulaMentionsCeiling() {
        #expect(ExerciseMetric.estimatedOneRepMax.formulaDescription.contains("1 à 12"))
        #expect(ExerciseMetric.estimatedOneRepMax.formulaDescription(maximumRepsForOneRepMax: 8).contains("1 à 8"))
    }
}
