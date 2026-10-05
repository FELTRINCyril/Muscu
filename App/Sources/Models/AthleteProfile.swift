import Foundation
import SwiftData
import MuscuEngine

/// Profil de l'athlete. Une seule instance au plus doit exister ; les
/// donnees de sante sensibles (taille, poids, zones a menager) sont toutes
/// facultatives et separees des informations necessaires au fonctionnement
/// de base de l'application, qui reste utilisable sans profil.
@Model
final class AthleteProfile {
    @Attribute(.unique) var id: UUID = UUID()

    // MARK: - Identite (facultative)

    var firstName: String = ""
    var birthDate: Date?

    // MARK: - Mesures de reference (facultatives, valeurs canoniques)

    /// Taille en centimetres. `nil` = non renseignee, jamais 0.
    var heightCentimeters: Double?
    /// Poids de reference en kilogrammes, utilise par les calculs de charge
    /// effective (poids du corps, lest, assistance) quand aucune mesure
    /// datee n'existe. `nil` = inconnu : les vues affichent alors
    /// « donnee manquante » plutot que zero.
    var bodyweightKilograms: Double?

    // MARK: - Preferences d'affichage

    var massUnitRaw: String = MassUnit.kilograms.rawValue
    var lengthUnitRaw: String = LengthUnit.centimeters.rawValue
    /// Increments de chargement disponibles, en kg canonique, tries.
    var availableIncrementsKilograms: [Double] = [1.25, 2.5, 5]

    // MARK: - Entrainement

    var experienceRaw: String = Experience.beginner.rawValue
    var primaryGoalRaw: String = Goal.hypertrophy.rawValue
    var secondaryGoalsRaw: [String] = []
    /// Jours de la semaine disponibles, convention `Calendar.weekday` (1 = dimanche).
    var availableWeekdays: [Int] = []
    var sessionMinutesMinimum: Int = 45
    var sessionMinutesMaximum: Int = 75
    var equipmentRaw: String = TrainingEquipment.fullGym.rawValue
    var priorityMuscles: [String] = []
    var excludedExerciseIds: [String] = []
    /// Zones a menager. Jamais un diagnostic : l'interface rappelle de
    /// consulter un professionnel en cas de douleur.
    var avoidAreas: [String] = []
    /// Frequence hebdomadaire souhaitee par groupe musculaire (cle EN du catalogue).
    var weeklyFrequencyByMuscleData: Data?
    var defaultProgressionRuleData: Data?

    // MARK: - Metadonnees de synchronisation

    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        firstName: String = "",
        birthDate: Date? = nil,
        heightCentimeters: Double? = nil,
        bodyweightKilograms: Double? = nil,
        massUnitRaw: String = MassUnit.kilograms.rawValue,
        lengthUnitRaw: String = LengthUnit.centimeters.rawValue,
        availableIncrementsKilograms: [Double] = [1.25, 2.5, 5],
        experienceRaw: String = Experience.beginner.rawValue,
        primaryGoalRaw: String = Goal.hypertrophy.rawValue,
        secondaryGoalsRaw: [String] = [],
        availableWeekdays: [Int] = [],
        sessionMinutesMinimum: Int = 45,
        sessionMinutesMaximum: Int = 75,
        equipmentRaw: String = TrainingEquipment.fullGym.rawValue,
        priorityMuscles: [String] = [],
        excludedExerciseIds: [String] = [],
        avoidAreas: [String] = [],
        weeklyFrequencyByMuscleData: Data? = nil,
        defaultProgressionRuleData: Data? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.firstName = firstName
        self.birthDate = birthDate
        self.heightCentimeters = heightCentimeters
        self.bodyweightKilograms = bodyweightKilograms
        self.massUnitRaw = massUnitRaw
        self.lengthUnitRaw = lengthUnitRaw
        self.availableIncrementsKilograms = availableIncrementsKilograms
        self.experienceRaw = experienceRaw
        self.primaryGoalRaw = primaryGoalRaw
        self.secondaryGoalsRaw = secondaryGoalsRaw
        self.availableWeekdays = availableWeekdays
        self.sessionMinutesMinimum = sessionMinutesMinimum
        self.sessionMinutesMaximum = sessionMinutesMaximum
        self.equipmentRaw = equipmentRaw
        self.priorityMuscles = priorityMuscles
        self.excludedExerciseIds = excludedExerciseIds
        self.avoidAreas = avoidAreas
        self.weeklyFrequencyByMuscleData = weeklyFrequencyByMuscleData
        self.defaultProgressionRuleData = defaultProgressionRuleData
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

extension AthleteProfile {
    var massUnit: MassUnit {
        get { MassUnit(rawValue: massUnitRaw) ?? .kilograms }
        set { massUnitRaw = newValue.rawValue }
    }

    var lengthUnit: LengthUnit {
        get { LengthUnit(rawValue: lengthUnitRaw) ?? .centimeters }
        set { lengthUnitRaw = newValue.rawValue }
    }

    var experience: Experience {
        get { Experience(rawValue: experienceRaw) ?? .beginner }
        set { experienceRaw = newValue.rawValue }
    }

    var primaryGoal: Goal {
        get { Goal(rawValue: primaryGoalRaw) ?? .hypertrophy }
        set { primaryGoalRaw = newValue.rawValue }
    }

    var secondaryGoals: [Goal] {
        get { secondaryGoalsRaw.compactMap(Goal.init(rawValue:)) }
        set { secondaryGoalsRaw = newValue.map(\.rawValue) }
    }

    var equipment: TrainingEquipment {
        get { TrainingEquipment(rawValue: equipmentRaw) ?? .fullGym }
        set { equipmentRaw = newValue.rawValue }
    }

    /// Regle de progression appliquee par defaut aux nouvelles prescriptions.
    /// Un blob illisible (ecrit par une version plus recente) retombe sur la
    /// regle par defaut plutot que de faire echouer tout le profil.
    var defaultProgressionRule: ProgressionRule {
        get {
            guard let data = defaultProgressionRuleData,
                  let rule = try? JSONDecoder().decode(ProgressionRule.self, from: data),
                  rule.isValid else { return .default }
            return rule
        }
        set { defaultProgressionRuleData = try? JSONEncoder().encode(newValue) }
    }

    var weeklyFrequencyByMuscle: [String: Int] {
        get {
            guard let data = weeklyFrequencyByMuscleData,
                  let value = try? JSONDecoder().decode([String: Int].self, from: data) else { return [:] }
            return value
        }
        set { weeklyFrequencyByMuscleData = try? JSONEncoder().encode(newValue) }
    }

    var syncMetadata: SyncMetadata {
        SyncMetadata(identifier: id, createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt)
    }

    func touch(now: Date = .now) { updatedAt = now }

    /// Increment de chargement le plus proche disponible pour cet athlete,
    /// sans jamais retourner zero.
    func nearestAvailableIncrement(to desired: Double) -> Double {
        let candidates = availableIncrementsKilograms.filter { $0 > 0 }.sorted()
        guard let first = candidates.first else { return massUnit.defaultIncrementKilograms }
        return candidates.min(by: { abs($0 - desired) < abs($1 - desired) }) ?? first
    }
}
