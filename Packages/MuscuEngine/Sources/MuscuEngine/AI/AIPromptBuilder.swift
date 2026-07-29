import Foundation

/// Construit le prompt de generation : parametres du wizard + notes libres
/// + liste blanche des exercices autorises (filtree par equipement) + schema
/// JSON attendu (celui de DraftProgram).
public enum AIPromptBuilder {
    public static func prompt(input: GeneratorInput, userNotes: String, catalog: ExerciseCatalog) -> String {
        let byId = Dictionary(uniqueKeysWithValues: catalog.all.map { ($0.id, $0) })
        let equipmentForSelection: TrainingEquipment = (input.goal == .calisthenics) ? .bodyweight : input.equipment

        let allowed = StapleExercises.all.compactMap { staple -> String? in
            guard let exercise = byId[staple.catalogId] else { return nil }
            guard RuleBasedGenerator.isEquipmentAllowed(exercise.equipment, for: equipmentForSelection) else { return nil }
            let equipment = exercise.equipment ?? "libre"
            let muscle = exercise.primaryMuscles.first ?? "?"
            return "- \(exercise.id) | \(exercise.nameFr) | \(muscle) | \(equipment)"
        }.joined(separator: "\n")

        let goalLabel: String
        switch input.goal {
        case .hypertrophy: goalLabel = "prise de masse (hypertrophie)"
        case .strength: goalLabel = "force"
        case .fatLoss: goalLabel = "perte de poids"
        case .endurance: goalLabel = "endurance musculaire"
        case .pullUpProgress: goalLabel = "progression aux tractions"
        case .calisthenics: goalLabel = "calisthenics / poids du corps"
        }
        let experienceLabel: String
        switch input.experience {
        case .beginner: experienceLabel = "debutant"
        case .intermediate: experienceLabel = "intermediaire"
        case .advanced: experienceLabel = "avance"
        }

        var lines: [String] = []
        lines.append("Tu es un coach de musculation. Genere un programme d'entrainement complet.")
        lines.append("")
        lines.append("Parametres :")
        lines.append("- Objectif : \(goalLabel)")
        lines.append("- Niveau : \(experienceLabel)")
        lines.append("- \(input.daysPerWeek) seances par semaine, environ \(input.sessionMinutes) minutes chacune")
        if !input.priorityMuscles.isEmpty {
            lines.append("- Muscles prioritaires : \(input.priorityMuscles.joined(separator: ", "))")
        }
        if !input.avoidAreas.isEmpty {
            lines.append("- Zones a menager (aucun exercice les ciblant) : \(input.avoidAreas.joined(separator: ", "))")
        }
        let notes = userNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty {
            lines.append("")
            lines.append("Demandes specifiques de l'utilisateur :")
            lines.append(notes)
        }
        lines.append("")
        lines.append("Exercices AUTORISES (utilise UNIQUEMENT ces exerciseId, exactement tels quels) :")
        lines.append(allowed)
        lines.append("")
        lines.append("Reponds UNIQUEMENT avec un objet JSON valide (aucun texte autour, pas de bloc markdown) au schema exact suivant :")
        lines.append("""
        {"name": "nom du programme", "notes": "conseils courts",
         "sessions": [{"name": "nom seance", "warmupEnabled": true,
           "exercises": [{"exerciseId": "id exact de la liste", "displayName": "nom francais de la liste",
             "sets": 4, "repsLower": 6, "repsUpper": 12, "restSeconds": 90, "percentOneRepMax": null}]}]}
        """)
        lines.append("Contraintes : exactement \(input.daysPerWeek) sessions ; 4 a 7 exercices par session ; percentOneRepMax est null ou un nombre (ex 80).")
        return lines.joined(separator: "\n")
    }
}
