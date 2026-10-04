import Foundation

/// Instantane affiche par les widgets.
///
/// Les widgets ne lisent PAS la base : ils liraient un store SwiftData depuis
/// un autre processus, avec ses migrations et ses verrous, pour afficher
/// trois lignes. L'application ecrit plutot ce petit resume apres chaque
/// changement qui le concerne.
///
/// Ce fichier vit dans le groupe d'applications, donc hors du conteneur
/// prive : il ne doit contenir que ce que le widget montre deja.
struct WidgetSnapshot: Codable, Equatable, Sendable {
    /// Version du format : un widget plus ancien que l'application doit
    /// pouvoir refuser un instantane qu'il ne sait pas lire.
    static let currentVersion = 1

    var version: Int
    var generatedAt: Date

    /// Prochaine seance prevue, si elle est connue.
    var nextSessionName: String?
    var nextSessionDate: Date?
    /// Nom du programme actif.
    var programName: String?

    /// Seances terminees sur les sept derniers jours.
    var sessionsThisWeek: Int
    /// Series de travail sur les sept derniers jours.
    var workingSetsThisWeek: Int
    /// Semaines consecutives avec au moins une seance.
    var weeklyStreak: Int
    /// Unite de charge du profil (« kg » ou « lb »), pour que la montre
    /// affiche et saisisse dans la meme unite que l'iPhone. Facultative : un
    /// instantane plus ancien la laisse absente, et la montre reste en kg.
    var massUnitSymbol: String?
    /// Derniere seance terminee, pour le widget « Dernière séance ».
    /// Facultative : absente d'un instantane plus ancien.
    var lastSession: LastSessionSummary?

    init(
        version: Int = WidgetSnapshot.currentVersion,
        generatedAt: Date = .now,
        nextSessionName: String? = nil,
        nextSessionDate: Date? = nil,
        programName: String? = nil,
        sessionsThisWeek: Int = 0,
        workingSetsThisWeek: Int = 0,
        weeklyStreak: Int = 0,
        massUnitSymbol: String? = nil,
        lastSession: LastSessionSummary? = nil
    ) {
        self.version = version
        self.generatedAt = generatedAt
        self.nextSessionName = nextSessionName
        self.nextSessionDate = nextSessionDate
        self.programName = programName
        self.sessionsThisWeek = sessionsThisWeek
        self.workingSetsThisWeek = workingSetsThisWeek
        self.weeklyStreak = weeklyStreak
        self.massUnitSymbol = massUnitSymbol
        self.lastSession = lastSession
    }

    /// Instantane vide, affiche tant que rien n'a ete enregistre.
    static let empty = WidgetSnapshot()

    var hasContent: Bool {
        nextSessionName != nil || sessionsThisWeek > 0 || workingSetsThisWeek > 0 || lastSession != nil
    }
}

/// Derniere seance terminee, reduite a ce que le widget affiche.
///
/// Les valeurs chiffrees arrivent deja MISES EN FORME dans l'unite du
/// profil : l'extension n'a pas le moteur, et refaire une conversion ici
/// serait une seconde regle qui finirait par diverger. Une valeur absente
/// reste absente (`nil`), elle n'est jamais affichee comme un zero.
struct LastSessionSummary: Codable, Equatable, Sendable {
    /// Identifiant de la seance : le widget ouvre « Refaire » sur elle.
    var sessionId: UUID
    var name: String
    var date: Date
    var durationSeconds: Int
    var workingSets: Int
    /// « 4 520 kg », ou `nil` si aucune serie n'a de tonnage mesurable.
    var tonnageText: String?
    /// Une partie des series n'a pas pu etre comptee (poids de corps
    /// inconnu) : le tonnage affiche est un minimum.
    var tonnageIsPartial: Bool
    /// Exercice d'un record etabli pendant la seance, s'il y en a un.
    var recordExerciseName: String?
    /// Nombre de records etablis pendant la seance.
    var recordCount: Int

    init(
        sessionId: UUID,
        name: String,
        date: Date,
        durationSeconds: Int,
        workingSets: Int,
        tonnageText: String? = nil,
        tonnageIsPartial: Bool = false,
        recordExerciseName: String? = nil,
        recordCount: Int = 0
    ) {
        self.sessionId = sessionId
        self.name = name
        self.date = date
        self.durationSeconds = durationSeconds
        self.workingSets = workingSets
        self.tonnageText = tonnageText
        self.tonnageIsPartial = tonnageIsPartial
        self.recordExerciseName = recordExerciseName
        self.recordCount = recordCount
    }
}

/// Lecture et ecriture de l'instantane dans le groupe d'applications.
enum WidgetSnapshotStore {
    static let fileName = "widget-snapshot.json"

    static func write(_ snapshot: WidgetSnapshot) {
        guard let url = AppGroup.fileURL(named: fileName) else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        // Ecriture atomique : un widget qui lirait pendant l'ecriture ne doit
        // jamais tomber sur un fichier tronque.
        try? data.write(to: url, options: .atomic)
    }

    static func read() -> WidgetSnapshot {
        guard let url = AppGroup.fileURL(named: fileName),
              let data = try? Data(contentsOf: url) else { return .empty }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(WidgetSnapshot.self, from: data) else { return .empty }
        // Un instantane ecrit par une version plus recente est ignore plutot
        // qu'affiche de travers.
        guard snapshot.version <= WidgetSnapshot.currentVersion else { return .empty }
        return snapshot
    }

    static func clear() {
        guard let url = AppGroup.fileURL(named: fileName) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
