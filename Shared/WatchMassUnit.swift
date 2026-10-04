import Foundation

/// Unite d'affichage de la montre, recue de l'iPhone dans l'instantane.
///
/// La montre ne lie pas le moteur : la conversion est reprise ici, avec la
/// meme constante que `MuscuEngine.MassUnit`. Les series envoyees a
/// l'iPhone restent TOUJOURS en kilogrammes.
enum WatchMassUnit {
    case kilograms
    case pounds

    /// Meme valeur que `MassUnit.poundsPerKilogram` dans le moteur.
    static let poundsPerKilogram = 2.204_622_621_848_776

    init(symbol: String?) {
        self = symbol == "lb" ? .pounds : .kilograms
    }

    var symbol: String {
        switch self {
        case .kilograms: return "kg"
        case .pounds: return "lb"
        }
    }

    /// Pas du stepper, dans l'unite affichee : 2,5 kg ou 5 lb.
    var step: Double {
        switch self {
        case .kilograms: return 2.5
        case .pounds: return 5
        }
    }

    var maximum: Double {
        switch self {
        case .kilograms: return 400
        case .pounds: return 880
        }
    }

    func toKilograms(_ value: Double) -> Double {
        self == .pounds ? value / Self.poundsPerKilogram : value
    }

    func fromKilograms(_ kilograms: Double) -> Double {
        self == .pounds ? kilograms * Self.poundsPerKilogram : kilograms
    }
}
