import Foundation
import SwiftData
import MuscuEngine

/// Exercices habituels de l'utilisateur, pour la section du meme nom de la
/// bibliotheque et du selecteur d'exercice. Le classement lui-meme vit dans
/// le moteur (`ExerciseRanking`) ; ce service ne fait que lire l'historique.
@MainActor
enum HabitualExercises {
    /// Historique lu : au-dela d'un an, une seance pese moins de 1/4000 avec
    /// une demi-vie de 30 jours. La charger ne changerait aucun classement.
    static let lookbackDays = 365

    /// Identifiants des exercices habituels, du plus au moins habituel.
    ///
    /// - Parameter among: exercices proposables (catalogue et exercices
    ///   personnalises actifs) : un exercice fusionne ou supprime n'a rien a
    ///   faire en tete de liste.
    static func identifiers(
        in context: ModelContext,
        among: Set<String>,
        names: [String: String] = [:],
        limit: Int = ExerciseRanking.defaultLimit,
        now: Date = .now
    ) -> [String] {
        let since = now.addingTimeInterval(-Double(lookbackDays) * 86_400)
        let descriptor = FetchDescriptor<CompletedSession>(predicate: #Predicate { $0.date >= since })
        let sessions = (try? context.fetch(descriptor)) ?? []
        var occurrences: [ExerciseOccurrence] = []
        for session in sessions {
            for set in session.sets where set.role.countsAsWorkingSet && !set.exerciseId.isEmpty {
                occurrences.append(ExerciseOccurrence(exerciseId: set.exerciseId, sessionId: session.id, date: session.date))
            }
        }
        return ExerciseRanking.habitual(occurrences: occurrences, now: now, limit: limit, among: among, names: names)
    }
}
