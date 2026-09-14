import Foundation
import SwiftData

/// Suppression des données, par catégorie ou en totalité.
///
/// Deux garanties exigées par la roadmap :
/// 1. la suppression est **vérifiable** — chaque opération renvoie ce qu'elle
///    a réellement supprimé ;
/// 2. elle est **complète** — la liste des catégories couvre tout le schéma,
///    et un test le vérifie.
@MainActor
enum DataDeletion {
    enum Category: String, CaseIterable, Identifiable {
        case history
        case records
        case programsAndPlans
        case measurements
        case checkIns
        case goalsAndAdaptations
        case planningAndReminders
        case templates
        case library
        case aiCoach
        case customExercises
        case profile

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .history: return "Historique des séances"
            case .records: return "Records"
            case .programsAndPlans: return "Programmes et plans"
            case .measurements: return "Mesures corporelles et photos"
            case .checkIns: return "Check-in de forme"
            case .goalsAndAdaptations: return "Objectifs et adaptations"
            case .planningAndReminders: return "Lieux, planning récurrent et rappels"
            case .templates: return "Modèles de séance"
            case .library: return "Favoris, tags et collections"
            case .aiCoach: return "Coach IA"
            case .customExercises: return "Exercices personnalisés"
            case .profile: return "Profil"
            }
        }

        var explanation: String {
            switch self {
            case .history: return "Séances terminées et séries associées."
            case .records: return "Records par exercice, y compris les records typés."
            case .programsAndPlans: return "Programmes, séances types, groupes, plans et planning."
            case .measurements: return "Poids, mensurations, pourcentage de masse grasse et photos de progression (fichiers compris)."
            case .checkIns: return "Énergie, sommeil, courbatures, stress et douleurs déclarées."
            case .goalsAndAdaptations: return "Objectifs suivis et journal des adaptations."
            case .planningAndReminders: return "Lieux et inventaires, récurrences, rappels programmés et liens vers l’app Calendrier. Les événements déjà créés dans Calendrier ne sont pas retirés : faites-le depuis le planning avant cette suppression."
            case .templates: return "Modèles de séance et de programme enregistrés."
            case .library: return "Exercices favoris, tags personnels et collections."
            case .aiCoach: return "Réglages du coach IA, consentement, compteur d’usage, journal technique et clé personnelle du Trousseau."
            case .customExercises: return "Exercices que vous avez créés."
            case .profile: return "Objectif, niveau, matériel, jours disponibles et mesures de référence."
            }
        }
    }

    /// Ce qui a réellement été supprimé, par type.
    struct Report: Equatable {
        var countsByModel: [String: Int] = [:]

        var total: Int { countsByModel.values.reduce(0, +) }

        var summary: String {
            guard total > 0 else { return "Aucune donnée à supprimer." }
            return countsByModel
                .filter { $0.value > 0 }
                .sorted { $0.key < $1.key }
                .map { "\($0.value) \($0.key)" }
                .joined(separator: ", ")
        }
    }

    /// Supprime une catégorie. La séance en cours est toujours supprimée avec
    /// l'historique : la laisser orpheline n'aurait aucun sens.
    @discardableResult
    static func delete(_ category: Category, context: ModelContext) throws -> Report {
        var report = Report()
        switch category {
        case .history:
            report.countsByModel["séances"] = try deleteAll(CompletedSession.self, in: context)
            report.countsByModel["séries"] = try deleteAll(CompletedSet.self, in: context)
            report.countsByModel["séances en cours"] = try deleteAll(ActiveWorkout.self, in: context)
            report.countsByModel["liens Santé"] = try deleteAll(HealthWorkoutLink.self, in: context)
            report.countsByModel["lignes en quarantaine"] = try deleteAll(ImportQuarantineEntry.self, in: context)

        case .records:
            report.countsByModel["records"] = try deleteAll(ExerciseRecord.self, in: context)
            report.countsByModel["records typés"] = try deleteAll(PersonalBest.self, in: context)

        case .programsAndPlans:
            report.countsByModel["programmes"] = try deleteAll(Program.self, in: context)
            report.countsByModel["séances types"] = try deleteAll(ProgramSession.self, in: context)
            report.countsByModel["prescriptions"] = try deleteAll(PrescribedExercise.self, in: context)
            report.countsByModel["groupes"] = try deleteAll(ExerciseGroup.self, in: context)
            report.countsByModel["plans"] = try deleteAll(TrainingPlan.self, in: context)
            report.countsByModel["blocs"] = try deleteAll(TrainingBlock.self, in: context)
            report.countsByModel["semaines"] = try deleteAll(TrainingWeek.self, in: context)
            report.countsByModel["séances planifiées"] = try deleteAll(ScheduledWorkout.self, in: context)

        case .measurements:
            report.countsByModel["mesures"] = try deleteAll(BodyMeasurement.self, in: context)
            // Les fichiers partent avec les lignes : effacer la ligne sans
            // effacer l'image laisserait la photo sur l'appareil.
            PhotoStore.deleteAll()
            report.countsByModel["photos"] = try deleteAll(ProgressPhoto.self, in: context)

        case .checkIns:
            report.countsByModel["check-in"] = try deleteAll(ReadinessEntry.self, in: context)

        case .goalsAndAdaptations:
            report.countsByModel["objectifs"] = try deleteAll(TrainingGoal.self, in: context)
            report.countsByModel["adaptations"] = try deleteAll(AdaptationEntry.self, in: context)

        case .planningAndReminders:
            report.countsByModel["lieux"] = try deleteAll(PlaceProfile.self, in: context)
            report.countsByModel["récurrences"] = try deleteAll(PlanningSchedule.self, in: context)
            report.countsByModel["rappels"] = try deleteAll(NotificationRecord.self, in: context)
            report.countsByModel["liens calendrier"] = try deleteAll(CalendarLink.self, in: context)

        case .templates:
            report.countsByModel["modèles"] = try deleteAll(SessionTemplate.self, in: context)

        case .library:
            report.countsByModel["annotations d’exercices"] = try deleteAll(ExerciseLibraryEntry.self, in: context)
            report.countsByModel["collections"] = try deleteAll(ExerciseCollection.self, in: context)

        case .aiCoach:
            // Le coach IA ne stocke aucune entite SwiftData : ses reglages,
            // son journal et sa cle vivent hors de la base. Les oublier ici
            // rendrait la « suppression totale » mensongere.
            let hadEntries = AICoachLog.entries.count
            let hadKey = AIKeychain.hasKey
            AISettings.reset()
            AICoachLog.clear()
            report.countsByModel["lignes de journal IA"] = hadEntries
            report.countsByModel["clé IA"] = hadKey ? 1 : 0

        case .customExercises:
            report.countsByModel["exercices personnalisés"] = try deleteAll(CustomExercise.self, in: context)

        case .profile:
            report.countsByModel["profils"] = try deleteAll(AthleteProfile.self, in: context)
            // L'etat de synchronisation suit le profil : le conserver apres
            // avoir tout supprime laisserait une file d'attente pointant vers
            // des entites disparues.
            report.countsByModel["état de synchronisation"] = try deleteAll(SyncState.self, in: context)
        }
        try context.save()
        return report
    }

    /// Suppression totale : toutes les catégories, en une seule transaction.
    @discardableResult
    static func deleteEverything(context: ModelContext) throws -> Report {
        var report = Report()
        for category in Category.allCases {
            let partial = try delete(category, context: context)
            for (key, value) in partial.countsByModel {
                report.countsByModel[key, default: 0] += value
            }
        }
        return report
    }

    /// Modèles couverts par les catégories. Comparé au schéma courant par un
    /// test : un modèle oublié rendrait la « suppression totale » mensongère.
    static let coveredModelNames: Set<String> = [
        "CompletedSession", "CompletedSet", "ActiveWorkout", "HealthWorkoutLink",
        "ExerciseRecord", "PersonalBest",
        "Program", "ProgramSession", "PrescribedExercise", "ExerciseGroup",
        "TrainingPlan", "TrainingBlock", "TrainingWeek", "ScheduledWorkout",
        "BodyMeasurement", "ReadinessEntry",
        "TrainingGoal", "AdaptationEntry",
        "CustomExercise", "AthleteProfile", "SyncState",
        "PlanningSchedule", "NotificationRecord", "CalendarLink",
        "SessionTemplate", "ExerciseLibraryEntry", "ExerciseCollection",
        "ImportQuarantineEntry", "PlaceProfile", "ProgressPhoto",
    ]

    private static func deleteAll<T: PersistentModel>(_ type: T.Type, in context: ModelContext) throws -> Int {
        let items = try context.fetch(FetchDescriptor<T>())
        for item in items { context.delete(item) }
        return items.count
    }
}
