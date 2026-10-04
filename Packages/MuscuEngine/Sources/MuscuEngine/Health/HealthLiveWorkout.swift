import Foundation

// Logique de la seance Sante en direct, du cardio d'une seance, de la note
// d'effort ecrite dans Sante et de l'import des mesures corporelles. Rien ici
// ne connait HealthKit : l'application lui passe des nombres et des dates,
// et applique ce qui est decide.

// MARK: - Cardio d'une seance

/// Frequence cardiaque et energie active d'une seance. Chaque valeur est
/// facultative : `nil` = non mesuree, jamais zero.
public struct SessionCardio: Equatable, Sendable {
    /// Bornes plausibles, les memes que celles de l'import d'archive : une
    /// valeur hors bornes trahit un capteur defaillant, pas un effort.
    public static let heartRateRange: ClosedRange<Double> = 20...300
    public static let energyRange: ClosedRange<Double> = 0...100_000

    public let averageHeartRate: Double?
    public let minimumHeartRate: Double?
    public let maximumHeartRate: Double?
    public let activeEnergyKilocalories: Double?

    public var isEmpty: Bool {
        averageHeartRate == nil && minimumHeartRate == nil && maximumHeartRate == nil && activeEnergyKilocalories == nil
    }

    /// Valeurs deja agregees (statistiques d'une seance en direct). Une
    /// valeur hors bornes ou non finie est ecartee ; les bpm sont arrondis a
    /// l'unite, l'energie au kcal.
    public init(
        averageHeartRate: Double?,
        minimumHeartRate: Double?,
        maximumHeartRate: Double?,
        activeEnergyKilocalories: Double?
    ) {
        func bpm(_ value: Double?) -> Double? {
            guard let value, value.isFinite, Self.heartRateRange.contains(value) else { return nil }
            return value.rounded()
        }
        self.averageHeartRate = bpm(averageHeartRate)
        self.minimumHeartRate = bpm(minimumHeartRate)
        self.maximumHeartRate = bpm(maximumHeartRate)
        if let energy = activeEnergyKilocalories, energy.isFinite, Self.energyRange.contains(energy) {
            self.activeEnergyKilocalories = energy.rounded()
        } else {
            self.activeEnergyKilocalories = nil
        }
    }

    /// Cardio calcule depuis des echantillons bruts lus dans Sante sur
    /// l'intervalle de la seance. Sans echantillon valide, aucune frequence :
    /// une moyenne de rien n'est pas zero.
    public static func from(heartRates: [Double], activeEnergyKilocalories: Double?) -> SessionCardio {
        let valid = heartRates.filter { $0.isFinite && heartRateRange.contains($0) }
        let average = valid.isEmpty ? nil : valid.reduce(0, +) / Double(valid.count)
        return SessionCardio(
            averageHeartRate: average,
            minimumHeartRate: valid.min(),
            maximumHeartRate: valid.max(),
            activeEnergyKilocalories: activeEnergyKilocalories
        )
    }
}

/// Seances dont le cardio peut encore etre lu dans Sante apres coup.
public enum HealthCardioBackfill {
    /// Au-dela, la seance est ancienne : relire Sante a chaque passage pour
    /// des seances sans montre couterait sans rien apporter.
    public static let lookbackDays = 7

    public struct Candidate: Equatable, Sendable {
        public let id: UUID
        public let start: Date
        public let end: Date
        public let hasCardio: Bool
        public let isDeleted: Bool

        public init(id: UUID, start: Date, end: Date, hasCardio: Bool, isDeleted: Bool = false) {
            self.id = id
            self.start = start
            self.end = end
            self.hasCardio = hasCardio
            self.isDeleted = isDeleted
        }
    }

    /// Seances a interroger : recentes, terminees, sans aucune valeur
    /// cardio deja connue (une valeur mesuree en direct n'est jamais
    /// ecrasee par une relecture).
    public static func sessionsToFetch(_ candidates: [Candidate], now: Date) -> [Candidate] {
        let limit = now.addingTimeInterval(-Double(lookbackDays) * 86_400)
        return candidates
            .filter { !$0.isDeleted && !$0.hasCardio && $0.end >= limit && $0.end <= now && $0.end > $0.start }
            .sorted { $0.start < $1.start }
    }
}

// MARK: - Note d'effort

/// Correspondance entre la note d'effort de Muscu et le score d'effort
/// d'entrainement de Sante. Les deux echelles vont de 1 a 10 avec les memes
/// paliers (facile, modere, difficile, maximal) : la valeur passe telle
/// quelle, sans conversion qui inventerait une precision.
public enum HealthEffortScore {
    public static func validRating(_ rating: Int?) -> Int? {
        guard let rating, SessionEffort.isValid(rating) else { return nil }
        return rating
    }

    /// Score Sante (`appleEffortScore`) pour une note Muscu ; `nil` = rien a
    /// ecrire.
    public static func appleEffortScore(for rating: Int?) -> Double? {
        validRating(rating).map(Double.init)
    }
}

// MARK: - Seance Sante en direct

/// Ce que l'application retient d'une seance Sante en direct pour la
/// retrouver apres un arret brutal.
public struct LiveWorkoutMarker: Codable, Equatable, Sendable {
    /// Seance en cours (`ActiveWorkout`) suivie par la seance Sante.
    public var activeWorkoutId: UUID
    /// Seance terminee a laquelle relier l'entrainement, une fois la fin
    /// demandee. `nil` = seance encore en cours.
    public var completedSessionId: UUID?

    public init(activeWorkoutId: UUID, completedSessionId: UUID? = nil) {
        self.activeWorkoutId = activeWorkoutId
        self.completedSessionId = completedSessionId
    }
}

/// Que faire d'une seance Sante retrouvee au lancement ?
public enum LiveWorkoutRecovery: Equatable, Sendable {
    /// La seance Muscu est toujours en cours : on la rattache, en pause
    /// jusqu'a la reprise par l'utilisateur.
    case reattachPaused(activeWorkoutId: UUID)
    /// La seance Muscu a ete terminee : on termine l'entrainement et on le
    /// relie a elle.
    case finish(completedSessionId: UUID)
    /// Seance abandonnee, ou impossible a rattacher : rien n'est enregistre.
    case discard

    /// - Parameters:
    ///   - marker: ce qui avait ete retenu avant l'arret, s'il existe.
    ///   - pendingActiveWorkoutIds: seances en cours encore en base.
    ///   - existingCompletedSessionIds: seances terminees encore en base
    ///     (non supprimees).
    public static func decide(
        marker: LiveWorkoutMarker?,
        pendingActiveWorkoutIds: Set<UUID>,
        existingCompletedSessionIds: Set<UUID>
    ) -> LiveWorkoutRecovery {
        guard let marker else { return .discard }
        if let completed = marker.completedSessionId {
            return existingCompletedSessionIds.contains(completed) ? .finish(completedSessionId: completed) : .discard
        }
        if pendingActiveWorkoutIds.contains(marker.activeWorkoutId) {
            return .reattachPaused(activeWorkoutId: marker.activeWorkoutId)
        }
        // Ni en cours ni terminee : la seance a ete abandonnee pendant que
        // l'application etait arretee. Enregistrer l'entrainement serait
        // ecrire dans Sante une seance qui n'existe pas.
        return .discard
    }

    /// Un entrainement plus court que le minimum de la synchronisation n'est
    /// pas enregistre : il serait refuse apres coup aussi.
    public static func shouldSave(durationSeconds: Int) -> Bool {
        durationSeconds >= HealthSyncPlanner.minimumDurationSeconds
    }
}

// MARK: - Mesures corporelles lues dans Sante

/// Mesures importables depuis Sante. Les valeurs brutes sont celles du type
/// de mesure de l'application (`BodyMeasurementKind`).
public enum HealthMeasurementKind: String, CaseIterable, Sendable {
    case bodyweight
    case bodyFatPercent
    case waist

    /// Ecart en dessous duquel deux mesures proches dans le temps decrivent
    /// la meme prise (rapprochement des mesures sans identifiant Sante).
    public var valueTolerance: Double {
        switch self {
        case .bodyweight: return 0.1 // kg
        case .bodyFatPercent: return 0.2 // points de %
        case .waist: return 0.5 // cm
        }
    }

    /// Bornes plausibles dans l'unite canonique (kg, %, cm).
    public var plausibleRange: ClosedRange<Double> {
        switch self {
        case .bodyweight: return 1...700
        case .bodyFatPercent: return 1...80
        case .waist: return 20...400
        }
    }
}

/// Echantillon lu dans Sante, deja converti dans l'unite canonique.
public struct HealthMeasurementSample: Equatable, Sendable {
    public let sampleIdentifier: String
    public let kind: HealthMeasurementKind
    public let value: Double
    public let date: Date
    /// Ecrit par Muscu : le reimporter doublerait notre propre saisie.
    public let isFromThisApp: Bool

    public init(sampleIdentifier: String, kind: HealthMeasurementKind, value: Double, date: Date, isFromThisApp: Bool) {
        self.sampleIdentifier = sampleIdentifier
        self.kind = kind
        self.value = value
        self.date = date
        self.isFromThisApp = isFromThisApp
    }
}

/// Mesure deja connue de Muscu.
public struct KnownMeasurement: Equatable, Sendable {
    public let kindRaw: String
    public let value: Double
    public let date: Date
    public let healthSampleIdentifier: String?
    public let isDeleted: Bool

    public init(kindRaw: String, value: Double, date: Date, healthSampleIdentifier: String?, isDeleted: Bool = false) {
        self.kindRaw = kindRaw
        self.value = value
        self.date = date
        self.healthSampleIdentifier = healthSampleIdentifier
        self.isDeleted = isDeleted
    }
}

public enum HealthMeasurementImporter {
    /// Fenetre lue au premier import d'une mesure.
    public static let initialLookbackDays = 90
    /// Recouvrement avec l'import precedent : un echantillon saisi en
    /// retard porte une date anterieure a ce passage. Le dedoublonnage par
    /// identifiant rend ce recouvrement sans risque.
    public static let overlapDays = 7
    /// Tolerance de date du rapprochement sans identifiant.
    public static let dateToleranceSeconds: TimeInterval = 3_600

    /// Debut de la lecture incrementale.
    public static func queryStart(lastImport: Date?, now: Date) -> Date {
        guard let lastImport else {
            return now.addingTimeInterval(-Double(initialLookbackDays) * 86_400)
        }
        return min(lastImport, now).addingTimeInterval(-Double(overlapDays) * 86_400)
    }

    /// Echantillons reellement nouveaux.
    ///
    /// 1. ce que Muscu a ecrit n'est jamais reimporte ;
    /// 2. un identifiant Sante deja connu ne l'est jamais non plus, meme si
    ///    la mesure a ete supprimee dans Muscu : la reimporter defierait la
    ///    suppression ;
    /// 3. une mesure sans identifiant (saisie a la main, import anterieur)
    ///    proche en date et en valeur est la meme prise ;
    /// 4. une valeur hors bornes est ecartee.
    public static func newSamples(
        _ samples: [HealthMeasurementSample],
        known: [KnownMeasurement]
    ) -> [HealthMeasurementSample] {
        var seen = Set(known.compactMap(\.healthSampleIdentifier))
        var accepted: [HealthMeasurementSample] = []
        for sample in samples.sorted(by: { $0.date < $1.date }) {
            guard !sample.isFromThisApp,
                  sample.value.isFinite,
                  sample.kind.plausibleRange.contains(sample.value),
                  !seen.contains(sample.sampleIdentifier) else { continue }
            let duplicate = known.contains { measurement in
                !measurement.isDeleted
                    && measurement.kindRaw == sample.kind.rawValue
                    && abs(measurement.date.timeIntervalSince(sample.date)) <= dateToleranceSeconds
                    && abs(measurement.value - sample.value) <= sample.kind.valueTolerance
            }
            guard !duplicate else { continue }
            seen.insert(sample.sampleIdentifier)
            accepted.append(sample)
        }
        return accepted
    }
}
