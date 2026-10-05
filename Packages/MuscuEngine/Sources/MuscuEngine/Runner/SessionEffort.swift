import Foundation

/// Note d'effort global d'une seance, de 1 a 10, saisie en fin de seance.
///
/// Distincte de `EffortRating` (RPE / RIR d'une SERIE) : celle-ci decrit la
/// seance entiere, telle que ressentie. Facultative : `nil` = non notee,
/// jamais 0.
///
/// Les paliers et leur progression de couleur s'inspirent d'UpLift
/// (`Services/EffortScale.swift`, licence MIT) ; le decoupage est affine
/// ici en six libelles, du « très facile » au « maximal ».
public enum SessionEffort {
    public static let range = 1...10

    public static func isValid(_ rating: Int) -> Bool { range.contains(rating) }

    public enum Band: String, CaseIterable, Sendable {
        case veryEasy
        case easy
        case moderate
        case hard
        case veryHard
        case maximal
    }

    /// Palier d'une note, `nil` hors bornes.
    public static func band(for rating: Int) -> Band? {
        switch rating {
        case 1, 2: return .veryEasy
        case 3, 4: return .easy
        case 5, 6: return .moderate
        case 7, 8: return .hard
        case 9: return .veryHard
        case 10: return .maximal
        default: return nil
        }
    }

    /// Note designee par une position horizontale sur la rangee de barres
    /// (glisser le doigt sur les barres). Toujours dans les bornes.
    public static func rating(atFraction fraction: Double) -> Int {
        guard fraction.isFinite else { return range.lowerBound }
        let index = Int(fraction * Double(range.count)) + 1
        return min(max(index, range.lowerBound), range.upperBound)
    }
}
