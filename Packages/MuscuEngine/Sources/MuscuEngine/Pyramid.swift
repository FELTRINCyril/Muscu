import Foundation

public struct PyramidProposal: Equatable, Sendable {
    public let name: String
    public let reps: [Int]
    public var totalVolume: Int { reps.reduce(0, +) }
}

public enum Pyramid {
    /// Paliers exprimes en fraction du max, arrondis (minimum 1 rep).
    static func steps(_ fractions: [Double], maxReps: Int) -> [Int] {
        fractions.map { max(1, Int((Double(maxReps) * $0).rounded())) }
    }

    public static func proposals(maxReps: Int) -> [PyramidProposal] {
        guard maxReps >= 1 else { return [] }
        return [
            PyramidProposal(
                name: "Montante-descendante",
                reps: steps([0.2, 0.4, 0.6, 0.4, 0.2], maxReps: maxReps)),
            PyramidProposal(
                name: "Progressive",
                reps: steps([0.1, 0.2, 0.3, 0.4, 0.5, 0.4, 0.3, 0.2, 0.1], maxReps: maxReps)),
            PyramidProposal(
                name: "Descendante",
                reps: steps([0.6, 0.5, 0.4, 0.3, 0.2, 0.1], maxReps: maxReps)),
        ]
    }

    // MARK: - Pyramide libre

    /// Bornes d'un palier saisi a la main.
    public static let allowedStepReps = 1...100
    /// Au-dela, la seance devient un circuit plus qu'une pyramide, et
    /// l'estimation de duree perd son sens.
    public static let maximumSteps = 30

    /// Paliers d'une pyramide libre, rendus valides : chaque palier borne,
    /// liste tronquee a `maximumSteps`. Une liste vide reste vide — c'est a
    /// l'editeur de refuser l'enregistrement, pas d'inventer un palier.
    public static func normalizedSteps(_ reps: [Int]) -> [Int] {
        reps.prefix(maximumSteps).map {
            min(max($0, allowedStepReps.lowerBound), allowedStepReps.upperBound)
        }
    }

    /// Proposition correspondant exactement a ces paliers, ou `nil` pour une
    /// pyramide libre. Sert a afficher « Personnalisee » sans mentir sur la
    /// forme choisie.
    public static func matchingProposal(for reps: [Int], maxReps: Int) -> PyramidProposal? {
        proposals(maxReps: maxReps).first { $0.reps == reps }
    }

    /// Palier ajoute en fin de liste : on reprend le dernier, l'utilisateur
    /// l'ajuste ensuite. Sans palier, on part du max de reps.
    public static func appendingStep(to reps: [Int], maxReps: Int) -> [Int] {
        guard reps.count < maximumSteps else { return reps }
        let next = reps.last ?? max(allowedStepReps.lowerBound, maxReps)
        return normalizedSteps(reps + [next])
    }

    // MARK: - Repos apres un palier

    /// Bornes d'un repos choisi palier par palier (0 = enchainer).
    public static let allowedStepRest = 0...600
    /// Repos adaptatif par defaut, quand la prescription n'en porte pas
    /// (pyramide venue d'un modele ou d'une archive anterieure).
    public static let defaultMinRest = 30
    public static let defaultMaxRest = 180

    /// Reference d'intensite du repos adaptatif : le palier le plus haut de
    /// la pyramide ELLE-MEME. Le record de l'exercice n'entre pas en jeu :
    /// il peut manquer, changer pendant la seance ou differer d'un appareil
    /// a l'autre, et le repos annonce ne serait plus celui qui est lance.
    /// Le palier le plus dur obtient donc le repos maxi, le plus leger un
    /// repos proche du mini.
    public static func referenceMaxReps(for steps: [Int]) -> Int {
        max(1, steps.max() ?? 1)
    }

    /// Repos apres le palier `index` realise en `repsDone` repetitions.
    ///
    /// SEULE source du repos d'une pyramide : la machine a etats, l'apercu
    /// du deroule et l'editeur l'appellent tous, pour que le repos annonce
    /// soit exactement celui qui est lance.
    ///
    /// - `stepRests` vide : repos adaptatif entre `minRest` et `maxRest`.
    /// - Sinon : repos choisi pour ce palier (mode « Par palier »).
    ///
    /// `nil` apres le DERNIER palier (et pour un index hors bornes) : la
    /// pyramide est finie, il n'y a pas de repos a annoncer ni a lancer.
    public static func restAfterStep(
        at index: Int,
        repsDone: Int,
        steps: [Int],
        stepRests: [Int],
        minRest: Int,
        maxRest: Int
    ) -> Int? {
        guard index >= 0, index + 1 < steps.count else { return nil }
        if !stepRests.isEmpty {
            // Une liste mal alignee (archive retouchee a la main) ne doit
            // pas faire planter : on retombe sur l'adaptatif.
            if stepRests.indices.contains(index) {
                return clampedRest(stepRests[index])
            }
        }
        let bounds = adaptiveBounds(minRest: minRest, maxRest: maxRest)
        return adaptiveRest(
            repsDone: repsDone,
            maxReps: referenceMaxReps(for: steps),
            minRest: bounds.min,
            maxRest: bounds.max
        )
    }

    /// Repos prevus entre les paliers, en supposant chaque palier realise
    /// tel que prescrit (`steps.count - 1` valeurs). Sert a l'editeur et a
    /// l'estimation de duree.
    public static func plannedRests(steps: [Int], stepRests: [Int], minRest: Int, maxRest: Int) -> [Int] {
        steps.indices.dropLast().compactMap { index in
            restAfterStep(at: index, repsDone: steps[index], steps: steps,
                          stepRests: stepRests, minRest: minRest, maxRest: maxRest)
        }
    }

    /// Bornes du repos adaptatif. Une prescription sans bornes (0/0, par
    /// exemple issue d'un modele) prendrait sinon un repos nul a chaque
    /// palier.
    static func adaptiveBounds(minRest: Int, maxRest: Int) -> (min: Int, max: Int) {
        guard minRest > 0 || maxRest > 0 else { return (defaultMinRest, defaultMaxRest) }
        let lower = max(0, minRest)
        return (lower, max(lower, maxRest))
    }

    public static func clampedRest(_ seconds: Int) -> Int {
        min(max(seconds, allowedStepRest.lowerBound), allowedStepRest.upperBound)
    }

    /// Pas du reglage d'un repos par palier : 5 s sous la minute, ou la
    /// precision compte, 15 s au-dela pour atteindre vite plusieurs minutes.
    public static func increasedRest(_ seconds: Int) -> Int {
        let value = clampedRest(seconds)
        let step = value < 60 ? 5 : 15
        return clampedRest((value / step + 1) * step)
    }

    public static func decreasedRest(_ seconds: Int) -> Int {
        let value = clampedRest(seconds)
        let step = value <= 60 ? 5 : 15
        // Une valeur hors grille redescend sur la grille, pas d'un pas entier.
        let snapped = (value / step) * step
        return clampedRest(snapped < value ? snapped : value - step)
    }

    /// Repos d'une pyramide valides : vide reste vide (mode adaptatif) ;
    /// sinon une valeur par palier, bornee. Une liste trop courte est
    /// completee avec sa derniere valeur.
    public static func normalizedRests(_ rests: [Int], stepCount: Int) -> [Int] {
        guard !rests.isEmpty, stepCount > 0 else { return [] }
        var aligned = Array(rests.prefix(stepCount)).map(clampedRest)
        while aligned.count < stepCount {
            aligned.append(aligned.last ?? defaultMinRest)
        }
        return aligned
    }

    /// Passage au mode « Par palier » : chaque palier part du repos que
    /// l'adaptatif lui donnait, pour ne rien changer tant que l'utilisateur
    /// n'a rien touche. Valeurs arrondies a 5 s.
    public static func perStepRests(fromAdaptive steps: [Int], minRest: Int, maxRest: Int) -> [Int] {
        guard !steps.isEmpty else { return [] }
        let bounds = adaptiveBounds(minRest: minRest, maxRest: maxRest)
        let reference = referenceMaxReps(for: steps)
        return steps.map {
            clampedRest(adaptiveRest(repsDone: $0, maxReps: reference, minRest: bounds.min, maxRest: bounds.max))
        }
    }

    /// Repos apres une serie, base sur l'intensite relative (reps faites / max).
    /// Formule de la spec : repos = min + intensite^1.5 * (max - min), arrondi a 5 s.
    public static func adaptiveRest(repsDone: Int, maxReps: Int,
                                    minRest: Int = 30, maxRest: Int = 180) -> Int {
        guard maxReps > 0, repsDone > 0, maxRest > minRest else { return minRest }
        let intensity = min(1.0, Double(repsDone) / Double(maxReps))
        let rest = Double(minRest) + pow(intensity, 1.5) * Double(maxRest - minRest)
        return Int((rest / 5.0).rounded()) * 5
    }
}

/// Paliers d'une pyramide et leurs repos, edites ENSEMBLE : un repos
/// appartient a son palier (il suit l'effort de ce palier), donc ajouter,
/// supprimer ou deplacer un palier emporte son repos avec lui.
///
/// `restSeconds` vide = repos adaptatif. Sinon il compte exactement un repos
/// par palier ; celui du dernier palier est conserve (il reapparait si le
/// palier est deplace ou si un palier est ajoute apres lui) mais jamais
/// lance ni affiche.
public struct PyramidSteps: Equatable, Sendable {
    public private(set) var reps: [Int]
    public private(set) var restSeconds: [Int]

    public init(reps: [Int], restSeconds: [Int] = []) {
        let steps = Pyramid.normalizedSteps(reps)
        self.reps = steps
        self.restSeconds = Pyramid.normalizedRests(restSeconds, stepCount: steps.count)
    }

    public var usesPerStepRest: Bool { !restSeconds.isEmpty }

    /// Repos reglable du palier `index`, ou `nil` pour le dernier palier
    /// (et en mode adaptatif).
    public func editableRest(at index: Int) -> Int? {
        guard usesPerStepRest, index + 1 < reps.count, restSeconds.indices.contains(index) else { return nil }
        return restSeconds[index]
    }

    public mutating func setReps(_ value: Int, at index: Int) {
        guard reps.indices.contains(index) else { return }
        reps[index] = value
        reps = Pyramid.normalizedSteps(reps)
    }

    public mutating func setRest(_ seconds: Int, at index: Int) {
        guard usesPerStepRest, restSeconds.indices.contains(index) else { return }
        restSeconds[index] = Pyramid.clampedRest(seconds)
    }

    /// « Appliquer la meme duree a tous ».
    public mutating func setAllRests(_ seconds: Int) {
        guard usesPerStepRest else { return }
        restSeconds = Array(repeating: Pyramid.clampedRest(seconds), count: reps.count)
    }

    /// Remplace les paliers (proposition choisie). En mode « Par palier »,
    /// les repos sont recalcules depuis l'adaptatif : l'ancienne liste
    /// decrivait une autre forme.
    public mutating func replaceSteps(_ newReps: [Int], minRest: Int, maxRest: Int) {
        reps = Pyramid.normalizedSteps(newReps)
        if usesPerStepRest {
            restSeconds = Pyramid.perStepRests(fromAdaptive: reps, minRest: minRest, maxRest: maxRest)
        }
    }

    /// Ajoute un palier en fin de liste ; son repos reprend celui du palier
    /// precedent.
    public mutating func appendStep(maxReps: Int, minRest: Int, maxRest: Int) {
        let appended = Pyramid.appendingStep(to: reps, maxReps: maxReps)
        guard appended.count > reps.count else { return }
        reps = appended
        if usesPerStepRest {
            let rest = restSeconds.last
                ?? Pyramid.perStepRests(fromAdaptive: reps, minRest: minRest, maxRest: maxRest).last
                ?? Pyramid.defaultMinRest
            restSeconds.append(rest)
        }
    }

    public mutating func removeSteps(atOffsets offsets: IndexSet) {
        reps = reps.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        if usesPerStepRest {
            restSeconds = restSeconds.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        }
    }

    /// Meme semantique que `move(fromOffsets:toOffset:)` de SwiftUI :
    /// `destination` est exprime AVANT le retrait des elements deplaces.
    public mutating func moveSteps(fromOffsets source: IndexSet, toOffset destination: Int) {
        reps = Self.moved(reps, fromOffsets: source, toOffset: destination)
        if usesPerStepRest {
            restSeconds = Self.moved(restSeconds, fromOffsets: source, toOffset: destination)
        }
    }

    public mutating func useAdaptiveRest() {
        restSeconds = []
    }

    public mutating func usePerStepRest(minRest: Int, maxRest: Int) {
        guard !usesPerStepRest else { return }
        restSeconds = Pyramid.perStepRests(fromAdaptive: reps, minRest: minRest, maxRest: maxRest)
    }

    static func moved<Element>(_ items: [Element], fromOffsets source: IndexSet, toOffset destination: Int) -> [Element] {
        let valid = source.filter { items.indices.contains($0) }
        guard !valid.isEmpty else { return items }
        let moving = valid.map { items[$0] }
        var remaining = items.enumerated().filter { !valid.contains($0.offset) }.map(\.element)
        let shift = valid.filter { $0 < destination }.count
        let insertion = min(max(0, destination - shift), remaining.count)
        remaining.insert(contentsOf: moving, at: insertion)
        return remaining
    }
}

extension WorkoutExercisePlan {
    /// Repos apres le palier `index` de cette pyramide (voir
    /// `Pyramid.restAfterStep`). `nil` apres le dernier palier.
    public func pyramidRest(afterStep index: Int, repsDone: Int) -> Int? {
        Pyramid.restAfterStep(
            at: index,
            repsDone: repsDone,
            steps: pyramidReps,
            stepRests: pyramidRestSeconds,
            minRest: pyramidMinRest,
            maxRest: pyramidMaxRest
        )
    }
}
