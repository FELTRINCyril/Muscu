import Foundation

/// Une serie enregistree a la montre.
struct WatchSetPayload: Codable, Equatable, Sendable {
    var exerciseName: String
    var setIndex: Int
    var weightKilograms: Double
    var reps: Int

    init(exerciseName: String, setIndex: Int, weightKilograms: Double, reps: Int) {
        self.exerciseName = exerciseName
        self.setIndex = setIndex
        self.weightKilograms = weightKilograms
        self.reps = reps
    }
}

/// Seance terminee a la montre, transmise au telephone.
///
/// L'identifiant est genere A LA MONTRE et ne change jamais : c'est lui qui
/// garantit qu'une seance rejoint l'historique une seule fois, meme si le
/// transfert est rejoue apres une coupure.
struct WatchSessionPayload: Codable, Equatable, Sendable, Identifiable {
    static let currentVersion = 1

    var version: Int
    var id: UUID
    var sessionName: String
    var startedAt: Date
    var durationSeconds: Int
    var sets: [WatchSetPayload]
    /// Entrainement enregistre dans Sante par la montre pendant cette
    /// seance (lot 7). Facultatif : absent d'une montre plus ancienne, ou
    /// sans seance Sante. L'iPhone le relie a la seance importee pour ne
    /// jamais l'ecrire une seconde fois.
    var healthWorkoutIdentifier: String?
    var cardio: WatchCardio?

    init(
        version: Int = WatchSessionPayload.currentVersion,
        id: UUID = UUID(),
        sessionName: String,
        startedAt: Date,
        durationSeconds: Int,
        sets: [WatchSetPayload],
        healthWorkoutIdentifier: String? = nil,
        cardio: WatchCardio? = nil
    ) {
        self.version = version
        self.id = id
        self.sessionName = sessionName
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
        self.sets = sets
        self.healthWorkoutIdentifier = healthWorkoutIdentifier
        self.cardio = cardio
    }
}

/// Cles des messages echanges entre la montre et le telephone.
enum WatchTransferKey {
    /// Instantane envoye du telephone vers la montre.
    static let snapshot = "snapshot"
    /// Seance envoyee de la montre vers le telephone.
    static let session = "session"
    /// Etat de la seance en cours (`WatchMirrorState`), telephone vers
    /// montre, dans le contexte et en message.
    static let mirror = "mirror"
    /// Prochaine seance et ses exercices (`WatchPlanSummary`), dans le
    /// contexte.
    static let plan = "plan"
    /// Commande de la montre (`WatchCommandEnvelope`).
    static let command = "command"
    /// Reponse a une commande (`WatchCommandReply`).
    static let reply = "reply"
    /// Commande Sante du telephone a la montre hote (`WatchHealthCommand`).
    static let healthCommand = "healthCommand"
    /// Confirmation d'un entrainement enregistre par la montre
    /// (`WatchHealthResult`).
    static let healthResult = "healthResult"
    /// Mesures en direct de la montre (`WatchLiveMetrics`).
    static let metrics = "metrics"
}
