import Foundation
import MuscuEngine

/// Mise en forme partagee d'une serie terminee. L'historique et le
/// recapitulatif de fin de seance affichent la meme chose : ce type evite que
/// deux ecrans decrivent differemment la meme serie.
enum CompletedSetPresentation {
    /// Libelle de gauche : distingue explicitement echauffement, approche,
    /// back-off, tour d'un groupe, serie et sous-serie (palier de dropset,
    /// mini-serie).
    ///
    /// Une serie qui ne consomme pas de serie prescrite porte son role et
    /// non un numero : « Série 3 » deux fois de suite serait faux.
    static func label(for set: CompletedSet, inGroup: Bool) -> String {
        if set.role == .warmup { return String(localized: "Échauffement") }
        if set.role == .approach { return String(localized: "Approche") }
        if set.role == .backoff { return String(localized: "Back-off") }

        var parts: [String] = []
        if inGroup {
            parts.append(String(localized: "Tour \(set.roundIndex + 1)"))
        } else {
            parts.append(String(localized: "Série \(set.setIndex + 1)"))
        }
        if set.subSetIndex > 0 {
            parts.append(subSetLabel(for: set))
        }
        return parts.joined(separator: " · ")
    }

    private static func subSetLabel(for set: CompletedSet) -> String {
        switch set.format {
        case .dropset: return String(localized: "palier \(set.subSetIndex)")
        case .restPause: return String(localized: "mini-série \(set.subSetIndex)")
        case .myoReps: return String(localized: "myo-série \(set.subSetIndex)")
        default: return String(localized: "sous-série \(set.subSetIndex)")
        }
    }

    /// Libelle de droite : la performance elle-meme. Une serie chronometree
    /// affiche son temps, une serie au poids du corps n'affiche pas « 0 kg ».
    static func performance(for set: CompletedSet, unit: MassUnit = WeightFormatter.preferredUnit) -> String {
        var parts: [String] = []

        if let duration = set.durationSeconds, duration > 0, set.format.isTimed {
            parts.append(formattedDuration(duration))
        }
        if set.reps > 0 {
            parts.append(String(localized: "\(set.reps) reps"))
        }
        switch set.loadType {
        case .external:
            if set.weight > 0 { parts.append(WeightFormatter.string(kilograms: set.weight, unit: unit)) }
        case .weighted:
            parts.append("+" + WeightFormatter.string(kilograms: set.weight, unit: unit))
        case .assisted:
            parts.append(String(localized: "-\(WeightFormatter.string(kilograms: set.weight, unit: unit)) d'aide"))
        case .bodyweight:
            parts.append(String(localized: "poids du corps"))
        case .unknown:
            // Serie anterieure au typage : on affiche la charge telle quelle
            // si elle existe, sans rien supposer de sa nature.
            if set.weight > 0 { parts.append(WeightFormatter.string(kilograms: set.weight, unit: unit)) }
        }
        if set.sideConvention == .perSide {
            parts.append(String(localized: "par côté"))
        }
        if let effort = set.effort {
            parts.append(effort.displayText)
        }
        if set.reachedFailure {
            parts.append(String(localized: "échec"))
        }
        return parts.isEmpty ? String(localized: "—") : parts.joined(separator: " · ")
    }

    /// Mention de substitution : l'historique conserve prevu ET realise.
    static func substitutionNote(for set: CompletedSet) -> String? {
        guard !set.plannedExerciseId.isEmpty, set.plannedExerciseId != set.exerciseId else { return nil }
        return String(localized: "Remplace l'exercice prévu")
    }

    /// Tonnage d'une seance, calcule par le moteur. Retourne aussi le nombre
    /// de series dont la charge effective est inconnue, pour ne jamais
    /// confondre « zéro » et « donnée manquante ».
    static func tonnage(for session: CompletedSession, fallbackBodyweight: Double? = nil) -> (total: Double, unknownSets: Int) {
        SetMetrics.totalTonnage(session.metricsInputs(fallbackBodyweightKilograms: fallbackBodyweight))
    }

    static func formattedDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remaining = seconds % 60
        return minutes > 0 ? "\(minutes) min \(remaining) s" : "\(remaining) s"
    }
}
