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

    init(
        version: Int = WidgetSnapshot.currentVersion,
        generatedAt: Date = .now,
        nextSessionName: String? = nil,
        nextSessionDate: Date? = nil,
        programName: String? = nil,
        sessionsThisWeek: Int = 0,
        workingSetsThisWeek: Int = 0,
        weeklyStreak: Int = 0,
        massUnitSymbol: String? = nil
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
    }

    /// Instantane vide, affiche tant que rien n'a ete enregistre.
    static let empty = WidgetSnapshot()

    var hasContent: Bool {
        nextSessionName != nil || sessionsThisWeek > 0 || workingSetsThisWeek > 0
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
