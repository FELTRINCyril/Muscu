import Foundation

/// Reponses aux questions posees a Siri sur les records.
///
/// Le choix de CE QUI est repondu vit ici, sans SwiftData : l'application ne
/// fait que lire les records et mettre la reponse en mots. Deux regles :
/// une estimation n'est jamais presentee comme une performance mesuree, et
/// une valeur absente n'est jamais remplacee par zero.
public enum RecordAnswers {
    /// Une valeur et le jour ou elle a ete obtenue (ou saisie).
    public struct DatedValue: Equatable, Sendable {
        public var value: Double
        public var date: Date

        public init(value: Double, date: Date) {
            self.value = value
            self.date = date
        }

        var isUsable: Bool { value.isFinite && value > 0 }
    }

    /// 1RM d'un exercice : l'estimation tiree de l'historique et, s'il
    /// existe, le 1RM de reference (saisi ou teste) qui pilote les charges
    /// en pourcentage.
    public struct OneRepMax: Equatable, Sendable {
        public var estimated: DatedValue?
        public var reference: DatedValue?

        public var isEmpty: Bool { estimated == nil && reference == nil }
    }

    /// Meilleure estimation (la plus recente a valeur egale) et reference.
    public static func oneRepMax(
        estimatedCandidates: [DatedValue],
        reference: DatedValue?
    ) -> OneRepMax {
        let best = estimatedCandidates
            .filter(\.isUsable)
            .max { lhs, rhs in
                lhs.value != rhs.value ? lhs.value < rhs.value : lhs.date < rhs.date
            }
        return OneRepMax(estimated: best, reference: reference.flatMap { $0.isUsable ? $0 : nil })
    }

    /// Un record, reduit a ce que Siri en dit.
    public struct RecordEntry: Equatable, Sendable, Identifiable {
        public var id: UUID
        public var exerciseName: String
        /// Nature du record (cle stable, mise en mots par l'application).
        public var kindKey: String
        public var value: Double
        public var achievedAt: Date

        public init(id: UUID, exerciseName: String, kindKey: String, value: Double, achievedAt: Date) {
            self.id = id
            self.exerciseName = exerciseName
            self.kindKey = kindKey
            self.value = value
            self.achievedAt = achievedAt
        }
    }

    /// Fenetre par defaut de « mes records récents ».
    public static let recentWindowDays = 90
    /// Une reponse parlee doit rester courte.
    public static let recentLimit = 5

    /// Records les plus recents, du plus recent au plus ancien. Une date
    /// future (horloge faussee, import) est ignoree plutot que placee en
    /// tete ; une valeur inutilisable aussi.
    public static func recent(
        _ entries: [RecordEntry],
        now: Date,
        withinDays days: Int = recentWindowDays,
        limit: Int = recentLimit
    ) -> [RecordEntry] {
        let since = now.addingTimeInterval(-Double(max(0, days)) * 86_400)
        return entries
            .filter { $0.value.isFinite && $0.value > 0 && $0.achievedAt <= now && $0.achievedAt >= since }
            .sorted { lhs, rhs in
                lhs.achievedAt != rhs.achievedAt
                    ? lhs.achievedAt > rhs.achievedAt
                    : lhs.exerciseName.localizedStandardCompare(rhs.exerciseName) == .orderedAscending
            }
            .prefix(max(0, limit))
            .map { $0 }
    }
}
