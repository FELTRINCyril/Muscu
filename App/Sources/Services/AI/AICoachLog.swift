import Foundation
import MuscuEngine

/// Journal technique du coach IA.
///
/// Il sert au diagnostic, pas a l'archivage : il ne contient NI la demande,
/// NI le contexte, NI la reponse — seulement ce qui permet de comprendre un
/// echec. Une ligne de journal ne doit jamais contenir de donnee personnelle
/// ni de fragment de cle.
struct AICoachLogEntry: Codable, Equatable, Identifiable, Sendable {
    enum Outcome: String, Codable, Sendable {
        case accepted
        case repaired
        case rejected
        case failed
        case fallback
    }

    var id: UUID = UUID()
    var date: Date
    var capabilityRaw: String
    var modelIdentifier: String
    var outcome: Outcome
    var durationMilliseconds: Int
    var repairCount: Int
    var violationCount: Int
    /// Message d'erreur DEJA destine a l'utilisateur, jamais une trace brute.
    var message: String

    var capability: AICoachCapability? { AICoachCapability(rawValue: capabilityRaw) }
}

@MainActor
enum AICoachLog {
    private static let key = "ai.log"
    /// Journal borne : un diagnostic n'a pas besoin de tout l'historique, et
    /// une liste sans limite finirait par peser.
    static let maximumEntries = 50

    static var entries: [AICoachLogEntry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let value = try? JSONDecoder().decode([AICoachLogEntry].self, from: data) else { return [] }
        return value
    }

    static func record(_ entry: AICoachLogEntry) {
        var all = entries
        all.insert(entry, at: 0)
        if all.count > maximumEntries { all = Array(all.prefix(maximumEntries)) }
        guard let data = try? JSONEncoder().encode(all) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// Diagnostic exportable. Verifie par un test : aucune donnee personnelle.
    static func diagnosticText() -> String {
        guard !entries.isEmpty else { return "Aucune demande enregistrée." }
        let formatter = ISO8601DateFormatter()
        return entries.map { entry in
            "\(formatter.string(from: entry.date)) · \(entry.capabilityRaw) · \(entry.modelIdentifier) · "
            + "\(entry.outcome.rawValue) · \(entry.durationMilliseconds) ms · "
            + "\(entry.repairCount) correction(s) · \(entry.violationCount) refus · \(entry.message)"
        }.joined(separator: "\n")
    }
}
