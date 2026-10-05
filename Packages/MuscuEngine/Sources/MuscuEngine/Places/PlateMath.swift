import Foundation

/// Disques et barre dont dispose l'athlete, exprimes dans UNE unite (kg ou
/// lb) : les disques en livres ne sont pas des disques en kilos convertis.
public struct PlateInventory: Codable, Equatable, Sendable {
    /// `pairs` = nombre de PAIRES possedees : on charge symetriquement.
    public struct Plate: Codable, Equatable, Sendable, Hashable {
        public var weight: Double
        public var pairs: Int

        public init(weight: Double, pairs: Int) {
            self.weight = weight
            self.pairs = pairs
        }
    }

    public var unit: MassUnit
    public var barWeight: Double
    public var plates: [Plate]

    public init(unit: MassUnit, barWeight: Double, plates: [Plate]) {
        self.unit = unit
        self.barWeight = barWeight
        self.plates = plates
    }

    /// Jeu commercial courant. Huit paires : assez pour ne jamais limiter.
    public static func standard(for unit: MassUnit) -> PlateInventory {
        switch unit {
        case .kilograms:
            return PlateInventory(
                unit: .kilograms,
                barWeight: 20,
                plates: [25, 20, 15, 10, 5, 2.5, 1.25].map { Plate(weight: $0, pairs: 8) }
            )
        case .pounds:
            return PlateInventory(
                unit: .pounds,
                barWeight: 45,
                plates: [45, 35, 25, 10, 5, 2.5].map { Plate(weight: $0, pairs: 8) }
            )
        }
    }

    /// Barres usuelles proposees dans la feuille, dans l'unite.
    public static func commonBarWeights(for unit: MassUnit) -> [Double] {
        switch unit {
        case .kilograms: return [20, 15, 10, 7, 25]
        case .pounds: return [45, 35, 25, 15, 55]
        }
    }

    /// Relecture prudente d'un inventaire saisi a la main et conserve d'une
    /// version a l'autre : une valeur inutilisable est ecartee plutot que
    /// de faire echouer le calcul en pleine seance. Une barre nulle rendrait
    /// toute charge « chargeable » : elle retombe sur le defaut. Une paire a
    /// zero survit (disque connu, mais absent de la salle).
    public func sanitized() -> PlateInventory {
        let fallback = Self.standard(for: unit)
        let bar = barWeight.isFinite && barWeight > 0 ? barWeight : fallback.barWeight
        var seen = Set<Int>()
        let cleaned = plates
            .filter { $0.weight.isFinite && $0.weight > 0 && $0.pairs >= 0 }
            .map { Plate(weight: $0.weight, pairs: min($0.pairs, 50)) }
            .sorted { $0.weight > $1.weight }
            .filter { seen.insert(PlateMath.milli($0.weight)).inserted }
        return PlateInventory(unit: unit, barWeight: bar, plates: cleaned)
    }

    /// Plus petit ecart chargeable : le plus petit disque, deux fois (un de
    /// chaque cote). Zero sans disque disponible.
    public var smallestStep: Double {
        (plates.filter { $0.pairs > 0 && $0.weight > 0 }.map(\.weight).min() ?? 0) * 2
    }
}

/// Une facon de charger la barre, dans l'unite de l'inventaire.
public struct PlateLoad: Equatable, Sendable {
    public struct Stack: Equatable, Sendable {
        public var weight: Double
        /// Nombre de disques de ce poids PAR COTE.
        public var count: Int
    }

    public var unit: MassUnit
    public var totalWeight: Double
    public var perSideWeight: Double
    /// Disques d'un cote, du plus lourd au plus leger.
    public var plates: [Stack]

    public var totalKilograms: Double { unit.toKilograms(totalWeight) }

    /// Chaque disque d'un cote, du plus lourd au plus leger (pour le dessin).
    public var eachPlate: [Double] { plates.flatMap { Array(repeating: $0.weight, count: $0.count) } }
}

public enum PlateSolution: Equatable, Sendable {
    /// La charge exacte est faisable.
    case exact(PlateLoad)
    /// Charge impossible : les deux plus proches faisables (absentes si la
    /// salle n'a rien dans cette direction) et le pas minimal.
    case rounded(below: PlateLoad?, above: PlateLoad?, step: Double)
    /// Charge sous le poids de la barre : aucun disque n'allege une barre.
    case belowBar(barWeight: Double)
}

/// Quels disques mettre sur la barre pour une charge cible.
///
/// Adapte d'Ischys (`domain/plateMath.ts`, MIT). Les calculs sont faits en
/// milliemes d'unite entiers : en virgule flottante, 20 + 1,25 × 2 n'est
/// pas toujours 22,5, et un calculateur qui declare parfois infaisable une
/// charge faisable est pire que pas de calculateur.
public enum PlateMath {
    static func milli(_ value: Double) -> Int { Int((value * 1000).rounded()) }
    static func unmilli(_ value: Int) -> Double { Double(value) / 1000 }

    /// Resout une cible exprimee en kg canonique.
    public static func solve(targetKilograms: Double, inventory rawInventory: PlateInventory) -> PlateSolution {
        let inventory = rawInventory.sanitized()
        let target = inventory.unit.fromKilograms(max(0, targetKilograms.isFinite ? targetKilograms : 0))
        return solve(target: target, inventory: inventory)
    }

    /// Resout une cible exprimee dans l'unite de l'inventaire.
    public static func solve(target: Double, inventory rawInventory: PlateInventory) -> PlateSolution {
        let inventory = rawInventory.sanitized()
        let bar = milli(inventory.barWeight)
        // Arrondi au centieme : une conversion kg -> lb laisse des
        // residus (224,999 999 lb) qui ne doivent pas rendre 225 lb infaisable.
        let targetMilli = Int((target * 100).rounded()) * 10
        guard targetMilli >= bar else { return .belowBar(barWeight: inventory.barWeight) }

        let over = targetMilli - bar
        let perSideTarget = over / 2
        let sums = reachable(inventory)

        if over % 2 == 0, let stack = sums[perSideTarget] {
            return .exact(load(perSide: perSideTarget, stack: stack, bar: bar, unit: inventory.unit))
        }

        var below: Int?
        var above: Int?
        for sum in sums.keys {
            if sum <= perSideTarget, below.map({ sum > $0 }) ?? true { below = sum }
            if sum * 2 + bar > targetMilli, above.map({ sum < $0 }) ?? true { above = sum }
        }
        return .rounded(
            below: below.map { load(perSide: $0, stack: sums[$0]!, bar: bar, unit: inventory.unit) },
            above: above.map { load(perSide: $0, stack: sums[$0]!, bar: bar, unit: inventory.unit) },
            step: inventory.smallestStep
        )
    }

    /// Toutes les charges par cote realisables, avec la pile preferee pour
    /// chacune. Somme de sous-ensembles bornee, PAS un algorithme glouton :
    /// avec un seul 20, un 15 et un 10, le glouton prend le 20 pour 25 kg
    /// par cote et reste bloque, alors que 15 + 10 convient.
    static func reachable(_ inventory: PlateInventory) -> [Int: [Int]] {
        let plates = inventory.plates
            .filter { $0.pairs > 0 && $0.weight > 0 }
            .sorted { $0.weight > $1.weight }
        var sums: [Int: [Int]] = [0: []]
        for plate in plates {
            let weight = milli(plate.weight)
            var next = sums
            for (sum, stack) in sums {
                for count in 1...plate.pairs {
                    let total = sum + weight * count
                    let candidate = stack + Array(repeating: weight, count: count)
                    if let rival = next[total], !prefers(candidate, over: rival) { continue }
                    next[total] = candidate
                }
            }
            sums = next
        }
        return sums
    }

    /// Entre deux piles de meme poids, celle qu'un pratiquant chargerait :
    /// le plus gros disque d'abord (25 + 15 plutot que 20 + 20), puis le
    /// moins de disques.
    static func prefers(_ lhs: [Int], over rhs: [Int]) -> Bool {
        for (left, right) in zip(lhs, rhs) where left != right {
            return left > right
        }
        return lhs.count < rhs.count
    }

    private static func load(perSide: Int, stack: [Int], bar: Int, unit: MassUnit) -> PlateLoad {
        var grouped: [PlateLoad.Stack] = []
        for weight in stack {
            let value = unmilli(weight)
            if let last = grouped.last, last.weight == value {
                grouped[grouped.count - 1].count += 1
            } else {
                grouped.append(PlateLoad.Stack(weight: value, count: 1))
            }
        }
        return PlateLoad(
            unit: unit,
            totalWeight: unmilli(bar + perSide * 2),
            perSideWeight: unmilli(perSide),
            plates: grouped
        )
    }
}
