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

    init(
        version: Int = WatchSessionPayload.currentVersion,
        id: UUID = UUID(),
        sessionName: String,
        startedAt: Date,
        durationSeconds: Int,
        sets: [WatchSetPayload]
    ) {
        self.version = version
        self.id = id
        self.sessionName = sessionName
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
        self.sets = sets
    }
}

/// Cles des messages echanges entre la montre et le telephone.
enum WatchTransferKey {
    /// Instantane envoye du telephone vers la montre.
    static let snapshot = "snapshot"
    /// Seance envoyee de la montre vers le telephone.
    static let session = "session"
}
