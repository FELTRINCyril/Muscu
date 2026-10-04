import Foundation

/// Mise en forme des durees et distances d'une serie mesuree. Le stockage
/// est toujours en secondes et en metres ; l'affichage passe au kilometre
/// a partir de 1 000 m. Systeme metrique uniquement, comme le stockage :
/// une conversion en miles demanderait un reglage d'unite de distance que
/// le profil n'a pas.
///
/// Non isole sur le MainActor, comme `WeightFormatter` : l'historique et
/// les exports formatent hors du fil principal.
enum MeasureFormatter {
    /// Distance lisible : « 400 m », « 1,25 km ».
    static func distance(meters: Double) -> String {
        guard meters.isFinite, meters >= 0 else { return "—" }
        if meters < 1_000 {
            return WeightFormatter.number(meters, maximumFractionDigits: meters < 10 ? 1 : 0) + " m"
        }
        return WeightFormatter.number(meters / 1_000, maximumFractionDigits: 2) + " km"
    }

    /// Chronometre « m:ss » (ou « h:mm:ss »), pour la saisie et les
    /// comptes a rebours.
    static func clock(seconds: Int) -> String {
        let total = max(0, seconds)
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let remainder = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainder)
        }
        return String(format: "%d:%02d", minutes, remainder)
    }
}
