import Foundation

/// La STRUCTURE d'un exercice dans un deroule : quoi, combien de series,
/// mesure en quoi. Jamais de charge ni de repetitions — ni prescrites ni
/// realisees.
public struct SessionStructureEntry: Codable, Equatable, Sendable, Identifiable {
    /// Identifiant de l'exercice dans le deroule : celui de la prescription
    /// du programme quand il en vient, ce qui permet de suivre un exercice
    /// remplace.
    public var id: UUID
    public var exerciseId: String
    public var displayName: String
    /// Series (exercice seul) ou tours (groupe). `nil` quand le format ne se
    /// compte pas en series (pyramide, formats chronometres).
    public var setCount: Int?
    public var measure: SetMeasure
    /// Noeud de groupe d'appartenance, `nil` pour un exercice seul.
    public var groupId: UUID?

    public init(
        id: UUID,
        exerciseId: String,
        displayName: String,
        setCount: Int?,
        measure: SetMeasure = .weightReps,
        groupId: UUID? = nil
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.displayName = displayName
        self.setCount = setCount
        self.measure = measure
        self.groupId = groupId
    }
}

/// Un ecart de structure entre la seance du programme et la seance faite.
public enum SessionStructureChange: Equatable, Sendable {
    case added(SessionStructureEntry)
    case removed(SessionStructureEntry)
    case replaced(from: SessionStructureEntry, to: SessionStructureEntry)
    case setCount(SessionStructureEntry, from: Int, to: Int)
    case measure(SessionStructureEntry, from: SetMeasure, to: SetMeasure)
    case moved(SessionStructureEntry)

    /// Exercice concerne, dans sa version finale quand elle existe.
    public var entry: SessionStructureEntry {
        switch self {
        case .added(let entry), .removed(let entry), .moved(let entry): return entry
        case .replaced(_, let to): return to
        case .setCount(let entry, _, _), .measure(let entry, _, _): return entry
        }
    }
}

/// Compare la structure d'une seance de programme a celle de la seance
/// effectivement deroulee, pour proposer de mettre le programme a jour.
///
/// Structure seulement : exercices ajoutes, retires, remplaces ou deplaces,
/// nombre de series et mesure. Les charges et repetitions different presque
/// a chaque seance ; les comparer ferait apparaitre la proposition a chaque
/// fois, et elle finirait ignoree par reflexe. L'approche (structure seule,
/// plus longue sous-sequence commune pour ne signaler que les exercices
/// REELLEMENT deplaces) s'inspire de `routineDiff.ts` d'Ischys (MIT).
public enum SessionStructureDiff {
    /// Structure d'un deroule, dans l'ordre d'execution.
    public static func entries(of plan: WorkoutPlan) -> [SessionStructureEntry] {
        plan.nodes.flatMap { node in
            node.exercises.map { exercise in
                SessionStructureEntry(
                    id: exercise.id,
                    exerciseId: exercise.exerciseId,
                    displayName: exercise.displayName,
                    setCount: node.isGroup ? node.rounds : countedSets(of: exercise),
                    measure: exercise.effectiveMeasure,
                    groupId: node.isGroup ? node.id : nil
                )
            }
        }
    }

    static func countedSets(of exercise: WorkoutExercisePlan) -> Int? {
        switch exercise.format {
        case .classic, .dropset, .restPause, .myoReps: return exercise.setCount
        case .pyramid, .intervals, .emom, .amrap, .forTime: return nil
        }
    }

    /// Ecarts, dans l'ordre : ajouts, retraits, puis modifications dans
    /// l'ordre de la seance faite. Un exercice ne produit qu'un ecart :
    /// remplacement d'abord, puis series, mesure et deplacement.
    public static func changes(
        baseline: [SessionStructureEntry],
        final: [SessionStructureEntry]
    ) -> [SessionStructureChange] {
        let baselineByID = Dictionary(baseline.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let finalIDs = Set(final.map(\.id))

        let commonBaseline = baseline.map(\.id).filter { finalIDs.contains($0) }
        let commonFinal = final.map(\.id).filter { baselineByID[$0] != nil }
        let kept = longestCommonSubsequence(commonBaseline, commonFinal)

        var added: [SessionStructureChange] = []
        var changed: [SessionStructureChange] = []
        for entry in final {
            guard let original = baselineByID[entry.id] else {
                added.append(.added(entry))
                continue
            }
            if original.exerciseId != entry.exerciseId {
                changed.append(.replaced(from: original, to: entry))
            } else if let from = original.setCount, let to = entry.setCount, from != to {
                changed.append(.setCount(entry, from: from, to: to))
            } else if original.measure != entry.measure {
                changed.append(.measure(entry, from: original.measure, to: entry.measure))
            } else if !kept.contains(entry.id) {
                changed.append(.moved(entry))
            }
        }
        let removed = baseline.filter { !finalIDs.contains($0.id) }.map(SessionStructureChange.removed)
        return added + removed + changed
    }

    /// Identifiants conserves par une plus longue sous-sequence commune :
    /// ceux qui n'en font pas partie ont reellement change de place, les
    /// autres n'ont ete que decales par un ajout ou un retrait.
    static func longestCommonSubsequence(_ lhs: [UUID], _ rhs: [UUID]) -> Set<UUID> {
        let rows = lhs.count
        let columns = rhs.count
        guard rows > 0, columns > 0 else { return [] }
        var lengths = Array(repeating: Array(repeating: 0, count: columns + 1), count: rows + 1)
        for row in stride(from: rows - 1, through: 0, by: -1) {
            for column in stride(from: columns - 1, through: 0, by: -1) {
                lengths[row][column] = lhs[row] == rhs[column]
                    ? lengths[row + 1][column + 1] + 1
                    : max(lengths[row + 1][column], lengths[row][column + 1])
            }
        }
        var kept: Set<UUID> = []
        var row = 0
        var column = 0
        while row < rows, column < columns {
            if lhs[row] == rhs[column] {
                kept.insert(lhs[row])
                row += 1
                column += 1
            } else if lengths[row + 1][column] >= lengths[row][column + 1] {
                row += 1
            } else {
                column += 1
            }
        }
        return kept
    }
}
