import Foundation

/// Une seance terminee, vue par la synchronisation Sante.
public struct HealthSyncSession: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let startDate: Date
    public let durationSeconds: Int
    public let activeEnergyKilocalories: Double?
    /// Seance supprimee cote Muscu : son entrainement Sante doit suivre.
    public let isDeleted: Bool

    public init(
        id: UUID,
        startDate: Date,
        durationSeconds: Int,
        activeEnergyKilocalories: Double? = nil,
        isDeleted: Bool = false
    ) {
        self.id = id
        self.startDate = startDate
        self.durationSeconds = durationSeconds
        self.activeEnergyKilocalories = activeEnergyKilocalories
        self.isDeleted = isDeleted
    }
}

/// Lien deja etabli entre une seance et un entrainement Sante.
public struct HealthSyncLink: Equatable, Sendable {
    public let completedSessionId: UUID
    public let workoutIdentifier: String
    public let isDeleted: Bool

    public init(completedSessionId: UUID, workoutIdentifier: String, isDeleted: Bool = false) {
        self.completedSessionId = completedSessionId
        self.workoutIdentifier = workoutIdentifier
        self.isDeleted = isDeleted
    }
}

/// Ce que la synchronisation Sante doit faire.
public struct HealthSyncPlan: Equatable, Sendable {
    /// Seances a ecrire dans Sante.
    public let toWrite: [HealthSyncSession]
    /// Entrainements Sante a retirer, parce que la seance a ete supprimee.
    public let toDelete: [String]
    /// Seances deja ecrites : rien a faire. Conserve pour rendre compte.
    public let alreadyWritten: [UUID]

    public var isEmpty: Bool { toWrite.isEmpty && toDelete.isEmpty }

    public init(toWrite: [HealthSyncSession], toDelete: [String], alreadyWritten: [UUID]) {
        self.toWrite = toWrite
        self.toDelete = toDelete
        self.alreadyWritten = alreadyWritten
    }
}

/// Decide quoi ecrire dans Sante, sans rien connaitre de HealthKit.
///
/// Toute la protection contre les doublons tient ici : une seance qui porte
/// deja un lien VIVANT n'est jamais reecrite. C'est ce qui garantit qu'une
/// seance faite a la montre puis synchronisee rejoint l'historique une seule
/// fois, quel que soit le nombre de passages de la synchronisation.
public enum HealthSyncPlanner {
    /// Duree minimale d'une seance ecrite dans Sante. En dessous, ce n'est
    /// pas un entrainement : l'ecrire polluerait l'app Sante.
    public static let minimumDurationSeconds = 60

    public static func plan(
        sessions: [HealthSyncSession],
        links: [HealthSyncLink]
    ) -> HealthSyncPlan {
        let liveLinks = links.filter { !$0.isDeleted }
        let linkBySession = Dictionary(
            liveLinks.map { ($0.completedSessionId, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var toWrite: [HealthSyncSession] = []
        var toDelete: [String] = []
        var alreadyWritten: [UUID] = []

        for session in sessions {
            let link = linkBySession[session.id]

            if session.isDeleted {
                // La seance a disparu cote Muscu : son entrainement Sante ne
                // doit pas lui survivre.
                if let link { toDelete.append(link.workoutIdentifier) }
                continue
            }

            if link != nil {
                alreadyWritten.append(session.id)
                continue
            }

            guard session.durationSeconds >= minimumDurationSeconds else { continue }
            toWrite.append(session)
        }

        // Un lien qui ne correspond a plus aucune seance connue pointe vers un
        // entrainement orphelin : on le retire aussi.
        let knownSessionIds = Set(sessions.map(\.id))
        for link in liveLinks where !knownSessionIds.contains(link.completedSessionId) {
            toDelete.append(link.workoutIdentifier)
        }

        return HealthSyncPlan(
            toWrite: toWrite.sorted { $0.startDate < $1.startDate },
            toDelete: toDelete.sorted(),
            alreadyWritten: alreadyWritten
        )
    }
}

/// Mesure de poids lue dans Sante.
public struct HealthBodyweightSample: Equatable, Sendable {
    public let kilograms: Double
    public let date: Date
    /// Vrai quand l'echantillon vient de Muscu : le reimporter creerait un
    /// doublon de ce que nous avons nous-memes ecrit.
    public let isFromThisApp: Bool

    public init(kilograms: Double, date: Date, isFromThisApp: Bool) {
        self.kilograms = kilograms
        self.date = date
        self.isFromThisApp = isFromThisApp
    }
}

public enum HealthBodyweightImporter {
    /// Tolerance de rapprochement : deux mesures a moins d'une heure et de
    /// 100 g l'une de l'autre decrivent la meme pesee.
    public static let dateToleranceSeconds: TimeInterval = 3_600
    public static let weightToleranceKilograms = 0.1

    /// Echantillons reellement nouveaux pour Muscu.
    public static func newSamples(
        _ samples: [HealthBodyweightSample],
        existing: [(kilograms: Double, date: Date)]
    ) -> [HealthBodyweightSample] {
        samples.filter { sample in
            guard !sample.isFromThisApp else { return false }
            return !existing.contains { known in
                abs(known.date.timeIntervalSince(sample.date)) <= dateToleranceSeconds
                    && abs(known.kilograms - sample.kilograms) <= weightToleranceKilograms
            }
        }
    }
}
