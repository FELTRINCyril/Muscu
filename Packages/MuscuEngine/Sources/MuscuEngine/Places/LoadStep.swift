import Foundation

/// Pas des boutons +/- de la saisie d'une charge.
///
/// Un pas code en dur (2,5 kg) est faux dans trois cas courants : une salle
/// dont les halteres vont de 2 en 2 kg, un athlete qui a declare des disques
/// de 1,25 kg, et un utilisateur en livres (5 lb ≈ 2,27 kg). Le pas suit donc
/// ce que l'utilisateur a declare, du plus precis au plus general.
public enum LoadStep {
    /// Pas en kg canonique, par ordre de priorite :
    /// 1. le pas du materiel dans le lieu (inventaire), s'il est renseigne ;
    /// 2. le palier du profil le plus proche du pas usuel de l'unite ;
    /// 3. le pas usuel de l'unite (2,5 kg ou 5 lb).
    public static func inputStepKilograms(
        equipmentIncrement: Double?,
        profileIncrementsKilograms: [Double],
        unit: MassUnit
    ) -> Double {
        if let equipmentIncrement, equipmentIncrement.isFinite, equipmentIncrement > 0 {
            return equipmentIncrement
        }
        let usual = unit.defaultIncrementKilograms
        let candidates = profileIncrementsKilograms.filter { $0.isFinite && $0 > 0 }
        return candidates.min(by: { abs($0 - usual) < abs($1 - usual) }) ?? usual
    }

    /// Applique un pas a une charge, sans jamais descendre sous zero.
    public static func stepped(_ kilograms: Double, by stepKilograms: Double, up: Bool) -> Double {
        guard kilograms.isFinite, stepKilograms.isFinite, stepKilograms > 0 else { return max(0, kilograms) }
        return max(0, up ? kilograms + stepKilograms : kilograms - stepKilograms)
    }
}
