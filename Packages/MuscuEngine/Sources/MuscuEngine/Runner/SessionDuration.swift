import Foundation

/// Estimation de la duree d'une seance, partagee par toutes les vues et par
/// le generateur : deux ecrans qui affichent la meme duree doivent utiliser
/// le meme calcul.
///
/// C'est une ESTIMATION : le temps reel depend de l'utilisateur. Les
/// constantes sont regroupees ici pour etre ajustables en un seul endroit.
public enum SessionDuration {
    /// Temps de travail estime d'une serie classique, hors repos.
    public static let workSecondsPerSet = 45
    /// Temps estime d'un palier de pyramide ou d'une sous-serie, hors repos.
    public static let workSecondsPerStep = 30
    /// Echauffement propose au debut de chaque seance.
    public static let warmupSeconds = 5 * 60

    /// Duree estimee d'un exercice, repos interne compris, en secondes.
    public static func estimatedSeconds(for exercise: WorkoutExercisePlan) -> Int {
        switch exercise.format {
        case .classic:
            let sets = max(1, exercise.setCount)
            return sets * workSecondsPerSet + max(0, sets - 1) * max(0, exercise.restSeconds)

        case .dropset:
            let sets = max(1, exercise.setCount)
            let drops = exercise.dropset?.drops.count ?? 0
            let dropRest = exercise.dropset?.restSeconds ?? 0
            let perSet = workSecondsPerSet + drops * (workSecondsPerStep + max(0, dropRest))
            return sets * perSet + max(0, sets - 1) * max(0, exercise.restSeconds)

        case .restPause:
            let sets = max(1, exercise.setCount)
            let miniSets = exercise.restPause?.maximumMiniSets ?? 0
            let microRest = exercise.restPause?.microRestSeconds ?? 0
            let perSet = workSecondsPerSet + miniSets * (workSecondsPerStep + max(0, microRest))
            return sets * perSet + max(0, sets - 1) * max(0, exercise.restSeconds)

        case .myoReps:
            let sets = max(1, exercise.setCount)
            let miniSets = exercise.myoReps?.maximumMiniSets ?? 0
            let miniRest = exercise.myoReps?.restSeconds ?? 0
            let perSet = workSecondsPerSet + miniSets * (workSecondsPerStep + max(0, miniRest))
            return sets * perSet + max(0, sets - 1) * max(0, exercise.restSeconds)

        case .pyramid:
            let steps = max(1, exercise.pyramidReps.count)
            let averageRest = max(0, (exercise.pyramidMinRest + exercise.pyramidMaxRest) / 2)
            return steps * workSecondsPerStep + max(0, steps - 1) * averageRest

        case .intervals, .emom:
            let rounds = max(1, exercise.intervalRounds)
            let work = max(1, exercise.intervalWorkSeconds)
            return rounds * work + max(0, rounds - 1) * max(0, exercise.intervalRestSeconds) + max(0, exercise.countdownSeconds)

        case .amrap:
            return max(1, exercise.amrapSeconds)

        case .forTime:
            // Sans plafond, on ne peut pas estimer honnetement : on retient
            // une borne prudente fondee sur le travail annonce.
            guard exercise.capSeconds > 0 else {
                return max(1, exercise.setCount) * workSecondsPerSet
            }
            return exercise.capSeconds
        }
    }

    /// Duree estimee d'un noeud, tours compris.
    public static func estimatedSeconds(for node: WorkoutNode) -> Int {
        guard node.isGroup else {
            return node.exercises.first.map(estimatedSeconds(for:)) ?? 0
        }
        // Dans un groupe, le nombre de tours pilote la repetition : le temps
        // de travail d'un exercice compte une fois par tour, pas `setCount`.
        let perRound = node.exercises.reduce(0) { partial, exercise in
            partial + singleRoundSeconds(for: exercise) + max(0, node.restBetweenExercisesSeconds) + max(0, node.transitionSeconds)
        }
        let rounds = max(1, node.rounds)
        return rounds * perRound + max(0, rounds - 1) * max(0, node.restBetweenRoundsSeconds)
    }

    /// Duree estimee d'une seance complete, echauffement compris.
    public static func estimatedSeconds(for plan: WorkoutPlan, includingWarmup: Bool = true) -> Int {
        let work = plan.nodes.reduce(0) { $0 + estimatedSeconds(for: $1) }
        return work + (includingWarmup ? warmupSeconds : 0)
    }

    /// Duree estimee en minutes, arrondie au multiple de 5 le plus proche,
    /// avec un plancher de 5 minutes.
    public static func estimatedMinutes(for plan: WorkoutPlan, includingWarmup: Bool = true) -> Int {
        roundedMinutes(estimatedSeconds(for: plan, includingWarmup: includingWarmup))
    }

    public static func roundedMinutes(_ seconds: Int) -> Int {
        let minutes = Double(max(0, seconds)) / 60.0
        return max(5, Int((minutes / 5.0).rounded()) * 5)
    }

    /// Travail d'un seul passage sur l'exercice, sans son repos propre :
    /// dans un groupe, c'est le groupe qui pilote les repos.
    private static func singleRoundSeconds(for exercise: WorkoutExercisePlan) -> Int {
        switch exercise.format {
        case .classic, .dropset, .restPause, .myoReps:
            return workSecondsPerSet
        case .pyramid:
            return workSecondsPerStep
        case .intervals, .emom, .amrap, .forTime:
            return estimatedSeconds(for: exercise)
        }
    }
}
