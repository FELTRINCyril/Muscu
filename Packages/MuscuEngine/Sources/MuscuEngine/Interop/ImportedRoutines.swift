import Foundation

/// Exercice d'une seance importee : identite et nombre de series de travail.
public struct ImportedRoutineExercise: Equatable, Sendable {
    /// Identifiant catalogue, vide quand l'exercice n'a pas ete reconnu.
    public var exerciseId: String
    public var displayName: String
    public var workingSetCount: Int

    public init(exerciseId: String, displayName: String, workingSetCount: Int) {
        self.exerciseId = exerciseId
        self.displayName = displayName
        self.workingSetCount = workingSetCount
    }

    /// Cle de rapprochement entre seances : l'identifiant catalogue, sinon
    /// le nom normalise.
    var key: String {
        exerciseId.isEmpty ? "name:" + TextMatching.normalize(displayName) : exerciseId
    }
}

/// Seance importee vue par la proposition de programmes.
public struct ImportedRoutineSession: Equatable, Sendable {
    public var title: String
    public var date: Date
    /// Exercices dans l'ordre de la seance.
    public var exercises: [ImportedRoutineExercise]

    public init(title: String, date: Date, exercises: [ImportedRoutineExercise]) {
        self.title = title
        self.date = date
        self.exercises = exercises
    }
}

/// Un titre de seance importe qui peut devenir une seance de programme.
public struct ImportedRoutineCandidate: Equatable, Sendable, Identifiable {
    /// Cle de regroupement (titre normalise). Pas pour l'affichage.
    public var key: String
    /// Nom affiche : l'orthographe de la seance la plus recente.
    public var name: String
    public var sessionCount: Int
    public var lastDate: Date
    /// Structure proposee : exercices de la seance la plus recente, avec le
    /// nombre de series USUEL de chacun sur toutes les seances du titre.
    public var exercises: [ImportedRoutineExercise]

    public var id: String { key }
}

/// Programmes a partir d'un historique importe.
///
/// Un import restaure des SEANCES, pas les programmes dont elles sont
/// issues. Ce module regroupe les seances importees par titre et propose,
/// pour chacun, une structure (exercices et nombre de series usuel), que
/// l'utilisateur choisit ou non de transformer en seance de programme ou en
/// modele. Inspire de `importedRoutines.ts` d'Ischys (MIT) : titre
/// insensible a la casse et aux espaces, tri par derniere seance, nom
/// jamais ecrase.
public enum ImportedRoutines {
    /// « Haut du corps » et «  haut   du Corps » sont un seul titre : retaper
    /// un titre ne voulait pas dire creer un second programme.
    public static func normalizeTitle(_ title: String) -> String {
        title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }

    /// Candidats, du plus recemment pratique au plus ancien ; a egalite, le
    /// titre le plus frequent, puis l'ordre alphabetique. Les seances sans
    /// titre ou sans exercice ne proposent rien.
    public static func candidates(from sessions: [ImportedRoutineSession]) -> [ImportedRoutineCandidate] {
        var byKey: [String: [ImportedRoutineSession]] = [:]
        for session in sessions {
            let key = normalizeTitle(session.title)
            guard !key.isEmpty, !session.exercises.isEmpty else { continue }
            byKey[key, default: []].append(session)
        }

        let candidates = byKey.map { key, group -> ImportedRoutineCandidate in
            // Strictement plus recente : a egalite, l'ordre d'arrivee gagne.
            var latest = group[0]
            for session in group.dropFirst() where session.date > latest.date {
                latest = session
            }
            let ordered = group.sorted { $0.date > $1.date }
            let exercises = latest.exercises.map { exercise in
                var usual = exercise
                usual.workingSetCount = usualSetCount(of: exercise.key, in: ordered) ?? exercise.workingSetCount
                return usual
            }
            return ImportedRoutineCandidate(
                key: key,
                name: latest.title.trimmingCharacters(in: .whitespacesAndNewlines),
                sessionCount: group.count,
                lastDate: latest.date,
                exercises: exercises
            )
        }

        return candidates.sorted { lhs, rhs in
            if lhs.lastDate != rhs.lastDate { return lhs.lastDate > rhs.lastDate }
            if lhs.sessionCount != rhs.sessionCount { return lhs.sessionCount > rhs.sessionCount }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    /// Nombre de series le plus frequent pour cet exercice sur les seances
    /// du titre (de la plus recente a la plus ancienne) ; a egalite, celui
    /// de la seance la plus recente. Jamais moins d'une serie.
    static func usualSetCount(of key: String, in sessions: [ImportedRoutineSession]) -> Int? {
        var counts: [Int: Int] = [:]
        var firstSeen: [Int: Int] = [:]
        var rank = 0
        for session in sessions {
            for exercise in session.exercises where exercise.key == key && exercise.workingSetCount > 0 {
                counts[exercise.workingSetCount, default: 0] += 1
                if firstSeen[exercise.workingSetCount] == nil { firstSeen[exercise.workingSetCount] = rank }
                rank += 1
            }
        }
        return counts.max { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            return (firstSeen[lhs.key] ?? .max) > (firstSeen[rhs.key] ?? .max)
        }?.key
    }

    /// Nom libre : suffixe plutot qu'ecrase. Creer une seance ne doit jamais
    /// en remplacer une existante, et deux « Haut du corps » identiques ne se
    /// distinguent plus dans une liste.
    public static func uniqueName(_ desired: String, taken: [String]) -> String {
        let base = desired.trimmingCharacters(in: .whitespacesAndNewlines)
        let used = Set(taken.map(normalizeTitle))
        guard used.contains(normalizeTitle(base)) else { return base }
        var number = 2
        while used.contains(normalizeTitle("\(base) (\(number))")) { number += 1 }
        return "\(base) (\(number))"
    }
}
