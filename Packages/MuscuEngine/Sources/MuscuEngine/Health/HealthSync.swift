import Foundation

/// Une seance terminee, vue par la synchronisation Sante.
public struct HealthSyncSession: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let startDate: Date
    public let durationSeconds: Int
    public let activeEnergyKilocalories: Double?
    /// Seance supprimee cote Muscu : son entrainement Sante doit suivre.
    public let isDeleted: Bool
    /// Derniere correction par l'utilisateur. `nil` = jamais corrigee.
    public let editedAt: Date?
    /// Note d'effort 1-10 saisie dans Muscu. `nil` = non notee.
    public let effortRating: Int?

    public init(
        id: UUID,
        startDate: Date,
        durationSeconds: Int,
        activeEnergyKilocalories: Double? = nil,
        isDeleted: Bool = false,
        editedAt: Date? = nil,
        effortRating: Int? = nil
    ) {
        self.id = id
        self.startDate = startDate
        self.durationSeconds = durationSeconds
        self.activeEnergyKilocalories = activeEnergyKilocalories
        self.isDeleted = isDeleted
        self.editedAt = editedAt
        self.effortRating = effortRating
    }
}

/// Lien deja etabli entre une seance et un entrainement Sante.
public struct HealthSyncLink: Equatable, Sendable {
    public let completedSessionId: UUID
    public let workoutIdentifier: String
    public let isDeleted: Bool
    /// Date d'ecriture de l'entrainement dans Sante. `nil` = inconnue.
    public let writtenAt: Date?
    /// Horaires de la seance tels qu'ecrits dans Sante. `nil` = lien
    /// anterieur a leur memorisation : seule `editedAt` peut alors dire si
    /// l'entrainement est perime.
    public let writtenStartDate: Date?
    public let writtenDurationSeconds: Int?
    /// Note d'effort ecrite dans Sante et identifiant de son echantillon.
    /// `nil` = aucune note ecrite.
    public let writtenEffortRating: Int?
    public let effortSampleIdentifier: String?

    public init(
        completedSessionId: UUID,
        workoutIdentifier: String,
        isDeleted: Bool = false,
        writtenAt: Date? = nil,
        writtenStartDate: Date? = nil,
        writtenDurationSeconds: Int? = nil,
        writtenEffortRating: Int? = nil,
        effortSampleIdentifier: String? = nil
    ) {
        self.completedSessionId = completedSessionId
        self.workoutIdentifier = workoutIdentifier
        self.isDeleted = isDeleted
        self.writtenAt = writtenAt
        self.writtenStartDate = writtenStartDate
        self.writtenDurationSeconds = writtenDurationSeconds
        self.writtenEffortRating = writtenEffortRating
        self.effortSampleIdentifier = effortSampleIdentifier
    }

    /// Les horaires ecrits correspondent-ils encore a la seance ? `nil` =
    /// impossible a dire (horaires non memorises).
    func timingMatches(_ session: HealthSyncSession) -> Bool? {
        guard let writtenStartDate, let writtenDurationSeconds else { return nil }
        return abs(writtenStartDate.timeIntervalSince(session.startDate)) < 1
            && writtenDurationSeconds == session.durationSeconds
    }
}

/// Note d'effort a (re)ecrire sur un entrainement deja dans Sante, sans
/// toucher a l'entrainement lui-meme : il peut porter la frequence cardiaque
/// d'une seance en direct, qu'un remplacement perdrait.
public struct HealthEffortUpdate: Equatable, Sendable {
    public let completedSessionId: UUID
    public let workoutIdentifier: String
    /// Echantillon a retirer d'abord. `nil` = aucune note precedente.
    public let previousSampleIdentifier: String?
    /// Nouvelle note, `nil` = la note a ete retiree dans Muscu.
    public let effortRating: Int?

    public init(completedSessionId: UUID, workoutIdentifier: String, previousSampleIdentifier: String?, effortRating: Int?) {
        self.completedSessionId = completedSessionId
        self.workoutIdentifier = workoutIdentifier
        self.previousSampleIdentifier = previousSampleIdentifier
        self.effortRating = effortRating
    }
}

/// Entrainement Sante a remplacer : la seance a ete corrigee apres son
/// ecriture (horaires, duree). HealthKit ne permet pas de modifier un
/// entrainement enregistre ; on retire l'ancien et on ecrit le nouveau.
public struct HealthSyncReplacement: Equatable, Sendable {
    public let session: HealthSyncSession
    public let previousWorkoutIdentifier: String

    public init(session: HealthSyncSession, previousWorkoutIdentifier: String) {
        self.session = session
        self.previousWorkoutIdentifier = previousWorkoutIdentifier
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
    /// Seances corrigees apres leur ecriture : entrainement a remplacer.
    public let toReplace: [HealthSyncReplacement]
    /// Notes d'effort a mettre a jour sur un entrainement conserve.
    public let effortUpdates: [HealthEffortUpdate]

    public var isEmpty: Bool { toWrite.isEmpty && toDelete.isEmpty && toReplace.isEmpty && effortUpdates.isEmpty }

    public init(
        toWrite: [HealthSyncSession],
        toDelete: [String],
        alreadyWritten: [UUID],
        toReplace: [HealthSyncReplacement] = [],
        effortUpdates: [HealthEffortUpdate] = []
    ) {
        self.toWrite = toWrite
        self.toDelete = toDelete
        self.alreadyWritten = alreadyWritten
        self.toReplace = toReplace
        self.effortUpdates = effortUpdates
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

    /// - Parameter excluding: seances dont l'entrainement est en cours
    ///   d'enregistrement par une seance Sante en direct. Les ecrire apres
    ///   coup en ferait un doublon ; elles seront liees par la seance en
    ///   direct, ou ecrites au passage suivant si elle echoue.
    public static func plan(
        sessions: [HealthSyncSession],
        links: [HealthSyncLink],
        excluding: Set<UUID> = []
    ) -> HealthSyncPlan {
        let liveLinks = links.filter { !$0.isDeleted }
        let linkBySession = Dictionary(
            liveLinks.map { ($0.completedSessionId, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var toWrite: [HealthSyncSession] = []
        var toDelete: [String] = []
        var alreadyWritten: [UUID] = []
        var toReplace: [HealthSyncReplacement] = []
        var effortUpdates: [HealthEffortUpdate] = []

        for session in sessions {
            let link = linkBySession[session.id]

            if excluding.contains(session.id), link == nil, !session.isDeleted { continue }

            if session.isDeleted {
                // La seance a disparu cote Muscu : son entrainement Sante ne
                // doit pas lui survivre.
                if let link { toDelete.append(link.workoutIdentifier) }
                continue
            }

            if let link {
                // Corrigee APRES l'ecriture : l'entrainement Sante ne decrit
                // plus la seance. Une correction anterieure a l'ecriture est
                // deja dedans.
                // Quand les horaires ecrits sont connus et inchanges, seule la
                // note d'effort a pu changer : l'entrainement est garde.
                if let editedAt = session.editedAt, let writtenAt = link.writtenAt, editedAt > writtenAt,
                   link.timingMatches(session) != true {
                    if session.durationSeconds >= minimumDurationSeconds {
                        toReplace.append(HealthSyncReplacement(
                            session: session,
                            previousWorkoutIdentifier: link.workoutIdentifier
                        ))
                    } else {
                        // Devenue trop courte pour etre un entrainement.
                        toDelete.append(link.workoutIdentifier)
                    }
                    continue
                }
                alreadyWritten.append(session.id)
                let effort = HealthEffortScore.validRating(session.effortRating)
                if effort != link.writtenEffortRating {
                    effortUpdates.append(HealthEffortUpdate(
                        completedSessionId: session.id,
                        workoutIdentifier: link.workoutIdentifier,
                        previousSampleIdentifier: link.effortSampleIdentifier,
                        effortRating: effort
                    ))
                }
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
            alreadyWritten: alreadyWritten,
            toReplace: toReplace.sorted { $0.session.startDate < $1.session.startDate },
            effortUpdates: effortUpdates
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
