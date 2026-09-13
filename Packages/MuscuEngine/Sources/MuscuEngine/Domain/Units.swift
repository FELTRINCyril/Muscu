import Foundation

/// Unite de masse. La valeur canonique stockee par l'application est
/// TOUJOURS en kilogrammes : `MassUnit` ne sert qu'a l'affichage et a la
/// saisie. Aucune conversion destructive n'est effectuee a l'export.
public enum MassUnit: String, Codable, CaseIterable, Sendable {
    case kilograms = "kg"
    case pounds = "lb"

    public static let poundsPerKilogram = 2.204_622_621_848_776

    /// Convertit une valeur canonique (kg) vers l'unite d'affichage.
    public func fromKilograms(_ kilograms: Double) -> Double {
        switch self {
        case .kilograms: return kilograms
        case .pounds: return kilograms * Self.poundsPerKilogram
        }
    }

    /// Convertit une valeur saisie dans cette unite vers la valeur canonique (kg).
    public func toKilograms(_ value: Double) -> Double {
        switch self {
        case .kilograms: return value
        case .pounds: return value / Self.poundsPerKilogram
        }
    }

    /// Increment de chargement usuel dans cette unite, exprime en kg canonique.
    public var defaultIncrementKilograms: Double {
        switch self {
        case .kilograms: return 2.5
        case .pounds: return 5.0 / Self.poundsPerKilogram
        }
    }

    public var symbol: String { rawValue }
}

/// Unite de longueur pour les mensurations et la taille.
public enum LengthUnit: String, Codable, CaseIterable, Sendable {
    case centimeters = "cm"
    case inches = "in"

    public static let centimetersPerInch = 2.54

    public func fromCentimeters(_ centimeters: Double) -> Double {
        switch self {
        case .centimeters: return centimeters
        case .inches: return centimeters / Self.centimetersPerInch
        }
    }

    public func toCentimeters(_ value: Double) -> Double {
        switch self {
        case .centimeters: return value
        case .inches: return value * Self.centimetersPerInch
        }
    }

    public var symbol: String { rawValue }
}

public enum Units {
    /// Arrondi d'affichage commun : au dixieme, sans notation scientifique.
    public static func roundedForDisplay(_ value: Double, fractionDigits: Int = 1) -> Double {
        guard value.isFinite else { return 0 }
        let factor = pow(10.0, Double(max(0, fractionDigits)))
        return (value * factor).rounded() / factor
    }

    /// Arrondi vers le bas sur un palier de chargement reel (barre + disques).
    public static func roundedToIncrement(_ value: Double, increment: Double) -> Double {
        guard value.isFinite, increment > 0 else { return 0 }
        return (value / increment).rounded(.down) * increment
    }
}
