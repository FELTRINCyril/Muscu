import Foundation

/// Une seance terminee ou figure un exercice : la seule chose dont le
/// classement des exercices habituels a besoin.
public struct ExerciseOccurrence: Equatable, Sendable {
    public var exerciseId: String
    public var sessionId: UUID
    public var date: Date

    public init(exerciseId: String, sessionId: UUID, date: Date) {
        self.exerciseId = exerciseId
        self.sessionId = sessionId
        self.date = date
    }
}

/// Exercices « habituels » : ceux qu'on pratique vraiment, en tete de la
/// bibliotheque et du selecteur.
///
/// Un catalogue de plusieurs centaines d'exercices est surtout fait des
/// exercices des autres. Ceux qu'on travaille meritent une section a part,
/// au-dessus de l'ordre alphabetique, qui reste inchange pour trouver le
/// reste. Inspire de `exerciseRanking.ts` d'Ischys (MIT).
///
/// Score = somme, sur chaque seance contenant l'exercice, de
/// `2^(-anciennete / demi-vie)`. La FREQUENCE (nombre de seances) et la
/// RECENCE (anciennete de chacune) comptent ensemble : un programme suivi
/// trois mois puis abandonne ne doit pas devancer ce qu'on a fait mardi.
public enum ExerciseRanking {
    /// Anciennete, en jours, au-dela de laquelle une seance compte pour
    /// moitie.
    public static let halfLifeDays = 30.0
    /// Nombre d'exercices habituels affiches.
    public static let defaultLimit = 8

    /// Score de chaque exercice. Un exercice jamais pratique n'a pas de
    /// score : il n'entre pas dans la section, plutot que d'y figurer a zero.
    public static func scores(
        occurrences: [ExerciseOccurrence],
        now: Date,
        halfLifeDays: Double = halfLifeDays
    ) -> [String: Double] {
        // Une seance compte une fois par exercice, quel que soit son nombre
        // de series : on mesure une habitude, pas un volume.
        var seen: Set<String> = []
        var result: [String: Double] = [:]
        for occurrence in occurrences where !occurrence.exerciseId.isEmpty {
            let key = "\(occurrence.exerciseId)|\(occurrence.sessionId.uuidString)"
            guard seen.insert(key).inserted else { continue }
            result[occurrence.exerciseId, default: 0] += weight(of: occurrence.date, now: now, halfLifeDays: halfLifeDays)
        }
        return result
    }

    /// Poids d'une seance selon son anciennete. Une date future (horloge
    /// decalee, fuseau) compte comme aujourd'hui, jamais plus.
    public static func weight(of date: Date, now: Date, halfLifeDays: Double = halfLifeDays) -> Double {
        let days = max(0, now.timeIntervalSince(date) / 86_400)
        guard halfLifeDays > 0 else { return 1 }
        return pow(2, -days / halfLifeDays)
    }

    /// Identifiants des exercices habituels, du plus au moins habituel.
    ///
    /// - Parameter among: exercices encore proposables (un exercice fusionne
    ///   ou supprime n'a rien a faire en tete de liste). `nil` = tous.
    /// - Parameter names: noms pour departager deux scores egaux, afin que
    ///   l'ordre ne change pas d'un affichage a l'autre.
    public static func habitual(
        occurrences: [ExerciseOccurrence],
        now: Date,
        limit: Int = defaultLimit,
        among: Set<String>? = nil,
        names: [String: String] = [:]
    ) -> [String] {
        scores(occurrences: occurrences, now: now)
            .filter { $0.value > 0 && (among?.contains($0.key) ?? true) }
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                let left = names[lhs.key] ?? lhs.key
                let right = names[rhs.key] ?? rhs.key
                return left.localizedStandardCompare(right) == .orderedAscending
            }
            .prefix(max(0, limit))
            .map(\.key)
    }
}
