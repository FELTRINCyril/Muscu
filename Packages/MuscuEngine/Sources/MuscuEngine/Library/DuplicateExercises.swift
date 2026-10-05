import Foundation

/// Exercice vu par la detection de doublons : nom, materiel, muscles et
/// volume d'historique, sans rien savoir du stockage.
public struct DuplicateCandidate: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// Autre nom connu (nom anglais d'un exercice du catalogue). Vide sinon.
    public var alternateName: String
    /// Materiel, vocabulaire du catalogue. Vide = inconnu.
    public var equipment: String
    public var primaryMuscles: [String]
    /// Exercice du catalogue embarque : jamais fusionne, seulement cible.
    public var isCatalog: Bool
    /// Seances terminees contenant l'exercice.
    public var sessionCount: Int
    /// Series de travail enregistrees.
    public var setCount: Int
    public var firstUsedAt: Date?

    public init(
        id: String,
        name: String,
        alternateName: String = "",
        equipment: String = "",
        primaryMuscles: [String] = [],
        isCatalog: Bool,
        sessionCount: Int = 0,
        setCount: Int = 0,
        firstUsedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.alternateName = alternateName
        self.equipment = equipment
        self.primaryMuscles = primaryMuscles
        self.isCatalog = isCatalog
        self.sessionCount = sessionCount
        self.setCount = setCount
        self.firstUsedAt = firstUsedAt
    }

    public var hasHistory: Bool { sessionCount > 0 || setCount > 0 }
}

/// Raison pour laquelle deux exercices semblent etre le meme mouvement.
/// L'ordre est celui de la confiance : les cas surs d'abord.
public enum DuplicateReason: String, CaseIterable, Sendable, Comparable {
    /// Meme nom une fois normalise (accents, casse, ponctuation) et materiel
    /// compatible.
    case sameName
    /// Meme nom selon la convention des imports (« Deadlift (Barbell) ») :
    /// le materiel ecrit entre parentheses est celui de l'autre exercice.
    case sameImportName
    /// Noms proches (faute de frappe, mot en plus) : a juger par
    /// l'utilisateur, jamais evident.
    case similarName

    var rank: Int {
        switch self {
        case .sameName: return 0
        case .sameImportName: return 1
        case .similarName: return 2
        }
    }

    public static func < (lhs: DuplicateReason, rhs: DuplicateReason) -> Bool { lhs.rank < rhs.rank }
}

/// Paire de doublons proposee a l'utilisateur. `duplicate` est toujours un
/// exercice personnalise : c'est lui qui sera redirige vers `survivor`.
public struct DuplicatePair: Equatable, Sendable, Identifiable {
    public var survivor: DuplicateCandidate
    public var duplicate: DuplicateCandidate
    public var reason: DuplicateReason
    /// Similarite des noms, de 0 a 1 (1 = identiques une fois normalises).
    public var similarity: Double

    public init(survivor: DuplicateCandidate, duplicate: DuplicateCandidate, reason: DuplicateReason, similarity: Double) {
        self.survivor = survivor
        self.duplicate = duplicate
        self.reason = reason
        self.similarity = similarity
    }

    /// Identifiant stable, independant du sens : sert a memoriser une paire
    /// ecartee par l'utilisateur.
    public var id: String { DuplicatePair.key(survivor.id, duplicate.id) }

    public static func key(_ first: String, _ second: String) -> String {
        first < second ? "\(first)|\(second)" : "\(second)|\(first)"
    }

    /// Les deux exercices sont personnalises : l'utilisateur peut choisir
    /// lequel garder. Un exercice du catalogue, lui, est toujours conserve.
    public var canSwap: Bool { !survivor.isCatalog && !duplicate.isCatalog }

    public func swapped() -> DuplicatePair {
        guard canSwap else { return self }
        return DuplicatePair(survivor: duplicate, duplicate: survivor, reason: reason, similarity: similarity)
    }
}

/// Detection des exercices enregistres deux fois.
///
/// Un meme mouvement saisi sous deux noms coupe son historique en deux : la
/// moitie des seances, des records divises. La detection ne fait que
/// PROPOSER des paires ; chaque fusion est confirmee par l'utilisateur.
/// Inspire de `mergeDuplicates.ts` d'Ischys (MIT), adapte : un exercice du
/// catalogue n'est jamais fusionne (il est en lecture seule et commun a
/// tous), il peut seulement etre la cible.
public enum DuplicateExercises {
    /// Seuil de similarite des noms (1 - distance d'edition / longueur).
    public static let similarityThreshold = 0.8
    /// Paires proposees au plus par exercice personnalise : au-dela, un nom
    /// trop generique (« Curl ») rapprocherait la moitie du catalogue.
    public static let maximumPairsPerExercise = 3

    /// Paires candidates, des plus sures aux plus incertaines.
    ///
    /// - Parameters:
    ///   - custom: exercices personnalises ACTIFS (ni supprimes, ni deja
    ///     fusionnes).
    ///   - catalog: exercices du catalogue (cibles possibles).
    ///   - dismissed: cles (`DuplicatePair.key`) ecartees par l'utilisateur.
    public static func pairs(
        custom: [DuplicateCandidate],
        catalog: [DuplicateCandidate],
        dismissed: Set<String> = []
    ) -> [DuplicatePair] {
        var found: [String: DuplicatePair] = [:]
        // Noms normalises une seule fois : le catalogue compte des centaines
        // d'exercices, compares a chaque exercice personnalise.
        let all = custom + catalog
        var namesById: [String: Set<String>] = [:]
        for candidate in all { namesById[candidate.id] = names(of: candidate) }

        for exercise in custom {
            var forExercise: [DuplicatePair] = []
            for other in all where other.id != exercise.id {
                guard let match = reason(
                    exercise,
                    other,
                    leftNames: namesById[exercise.id] ?? [],
                    rightNames: namesById[other.id] ?? []
                ) else { continue }
                let pair = oriented(exercise, other, reason: match.reason, similarity: match.similarity)
                guard !dismissed.contains(pair.id) else { continue }
                forExercise.append(pair)
            }
            forExercise.sort(by: isOrderedBefore)
            for pair in forExercise.prefix(maximumPairsPerExercise) where found[pair.id] == nil {
                found[pair.id] = pair
            }
        }

        return found.values.sorted(by: isOrderedBefore)
    }

    /// Raison la plus forte qui rapproche deux exercices, ou nil.
    public static func reason(
        _ lhs: DuplicateCandidate,
        _ rhs: DuplicateCandidate
    ) -> (reason: DuplicateReason, similarity: Double)? {
        reason(lhs, rhs, leftNames: names(of: lhs), rightNames: names(of: rhs))
    }

    private static func reason(
        _ lhs: DuplicateCandidate,
        _ rhs: DuplicateCandidate,
        leftNames: Set<String>,
        rightNames: Set<String>
    ) -> (reason: DuplicateReason, similarity: Double)? {
        guard lhs.id != rhs.id, !(lhs.isCatalog && rhs.isCatalog) else { return nil }
        guard !leftNames.isEmpty, !rightNames.isEmpty else { return nil }
        let equipmentCompatible = isCompatible(lhs.equipment, rhs.equipment)

        if equipmentCompatible, !leftNames.isDisjoint(with: rightNames) {
            return (.sameName, 1)
        }

        if importNameMatches(lhs, rhs) || importNameMatches(rhs, lhs) {
            return (.sameImportName, 1)
        }

        guard equipmentCompatible, musclesCompatible(lhs.primaryMuscles, rhs.primaryMuscles) else { return nil }
        var best = 0.0
        var subset = false
        for left in leftNames {
            for right in rightNames {
                if tokenSubset(left, right) { subset = true }
                // Borne gratuite avant la distance d'edition : deux noms de
                // longueurs trop differentes ne peuvent pas etre assez proches.
                let longest = Double(max(left.count, right.count))
                let lengthBound = 1 - Double(abs(left.count - right.count)) / longest
                guard lengthBound >= similarityThreshold else { continue }
                best = max(best, similarity(left, right))
            }
        }
        if subset || best >= similarityThreshold {
            return (.similarName, best)
        }
        return nil
    }

    /// Similarite de deux noms deja normalises, de 0 a 1.
    public static func similarity(_ lhs: String, _ rhs: String) -> Double {
        let length = max(lhs.count, rhs.count)
        guard length > 0 else { return 1 }
        return 1 - Double(TextMatching.editDistance(lhs, rhs)) / Double(length)
    }

    // MARK: - Interne

    private static func names(of candidate: DuplicateCandidate) -> Set<String> {
        Set([candidate.name, candidate.alternateName].map(TextMatching.normalize).filter { !$0.isEmpty })
    }

    /// Materiel compatible : identique, ou inconnu d'un cote (un champ vide
    /// ne contredit rien). Une barre et des halteres sont deux mouvements
    /// aux records differents : jamais rapproches par le nom.
    private static func isCompatible(_ lhs: String, _ rhs: String) -> Bool {
        lhs.isEmpty || rhs.isEmpty || lhs == rhs
    }

    private static func musclesCompatible(_ lhs: [String], _ rhs: [String]) -> Bool {
        lhs.isEmpty || rhs.isEmpty || !Set(lhs).isDisjoint(with: rhs)
    }

    /// `imported` s'ecrit « Nom (Materiel) » et designe `other` : meme nom de
    /// base, et le materiel entre parentheses est celui de `other` (ou celui-
    /// ci est inconnu).
    private static func importNameMatches(_ imported: DuplicateCandidate, _ other: DuplicateCandidate) -> Bool {
        guard let suffix = ExerciseNaming.equipmentSuffix(in: imported.name) else { return false }
        guard other.equipment.isEmpty || other.equipment == suffix.equipment else { return false }
        let base = TextMatching.normalize(suffix.baseName)
        var otherNames = names(of: other)
        if let otherSuffix = ExerciseNaming.equipmentSuffix(in: other.name), otherSuffix.equipment == suffix.equipment {
            otherNames.insert(TextMatching.normalize(otherSuffix.baseName))
        }
        return otherNames.contains(base)
    }

    /// Tous les mots du nom le plus court figurent dans l'autre, et le plus
    /// court en compte au moins deux : « curl » seul n'est pas un indice.
    private static func tokenSubset(_ lhs: String, _ rhs: String) -> Bool {
        let left = lhs.split(separator: " ").map(String.init)
        let right = rhs.split(separator: " ").map(String.init)
        let (small, big) = left.count <= right.count ? (left, right) : (right, left)
        guard small.count >= 2, small.count < big.count else { return false }
        return Set(small).isSubset(of: Set(big))
    }

    /// Sens de la paire : le catalogue est conserve ; entre deux exercices
    /// personnalises, celui qui a le plus d'historique (moins de series a
    /// deplacer, nom generalement le mieux forme).
    private static func oriented(
        _ lhs: DuplicateCandidate,
        _ rhs: DuplicateCandidate,
        reason: DuplicateReason,
        similarity: Double
    ) -> DuplicatePair {
        if rhs.isCatalog { return DuplicatePair(survivor: rhs, duplicate: lhs, reason: reason, similarity: similarity) }
        if lhs.isCatalog { return DuplicatePair(survivor: lhs, duplicate: rhs, reason: reason, similarity: similarity) }
        return hasMoreHistory(lhs, than: rhs)
            ? DuplicatePair(survivor: lhs, duplicate: rhs, reason: reason, similarity: similarity)
            : DuplicatePair(survivor: rhs, duplicate: lhs, reason: reason, similarity: similarity)
    }

    private static func hasMoreHistory(_ lhs: DuplicateCandidate, than rhs: DuplicateCandidate) -> Bool {
        if lhs.sessionCount != rhs.sessionCount { return lhs.sessionCount > rhs.sessionCount }
        if lhs.setCount != rhs.setCount { return lhs.setCount > rhs.setCount }
        switch (lhs.firstUsedAt, rhs.firstUsedAt) {
        case let (left?, right?) where left != right: return left < right
        case (.some, nil): return true
        case (nil, .some): return false
        default: return lhs.id < rhs.id
        }
    }

    private static func isOrderedBefore(_ lhs: DuplicatePair, _ rhs: DuplicatePair) -> Bool {
        if lhs.reason != rhs.reason { return lhs.reason < rhs.reason }
        if lhs.similarity != rhs.similarity { return lhs.similarity > rhs.similarity }
        let leftSets = lhs.survivor.setCount + lhs.duplicate.setCount
        let rightSets = rhs.survivor.setCount + rhs.duplicate.setCount
        if leftSets != rightSets { return leftSets > rightSets }
        return lhs.id < rhs.id
    }
}
