import AppIntents
import Foundation
import SwiftData
import MuscuEngine

// Raccourcis et Siri.
//
// Regles communes :
// - les entites exposees ont un identifiant STABLE (UUID de programme,
//   identifiant de catalogue), jamais un rang qui bougerait ;
// - toute ECRITURE demande confirmation, meme quand la demande semble
//   claire : un raccourci mal declenche ne doit pas modifier l'historique ;
// - tous les libelles sont localises, comme le reste de l'application.

// MARK: - Entités

struct ProgramEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource("Programme"))
    static let defaultQuery = ProgramEntityQuery()

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct ProgramEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [ProgramEntity] {
        try all().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func suggestedEntities() async throws -> [ProgramEntity] {
        try all()
    }

    @MainActor
    private func all() throws -> [ProgramEntity] {
        let context = try IntentStore.context()
        let programs = try context.fetch(FetchDescriptor<Program>(sortBy: [SortDescriptor(\.name)]))
        return programs
            .filter { $0.deletedAt == nil }
            .map { ProgramEntity(id: $0.id, name: $0.name) }
    }
}

struct ExerciseEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource("Exercice"))
    static let defaultQuery = ExerciseEntityQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct ExerciseEntityQuery: EntityQuery, EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [ExerciseEntity] {
        guard let catalog = IntentStore.catalog() else { return [] }
        return identifiers.compactMap { identifier in
            catalog.exercise(id: identifier).map { ExerciseEntity(id: $0.id, name: $0.nameFr) }
        }
    }

    /// Recherche par nom, tolerante aux accents et aux fautes simples : c'est
    /// la meme recherche que dans l'application, pas une seconde regle.
    func entities(matching string: String) async throws -> [ExerciseEntity] {
        guard let catalog = IntentStore.catalog() else { return [] }
        return LibrarySearch.run(query: string, catalog: catalog.all, limit: 10)
            .map { ExerciseEntity(id: $0.exercise.id, name: $0.exercise.nameFr) }
    }

    func suggestedEntities() async throws -> [ExerciseEntity] {
        guard let catalog = IntentStore.catalog() else { return [] }
        return catalog.all.prefix(10).map { ExerciseEntity(id: $0.id, name: $0.nameFr) }
    }
}

// MARK: - Démarrer la prochaine séance

struct StartNextWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Démarrer la prochaine séance"
    static let description = IntentDescription("Ouvre Muscu sur la séance qui vient dans le programme actif.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = try IntentStore.context()
        let programs = try context.fetch(FetchDescriptor<Program>())
            .filter { $0.deletedAt == nil }

        guard let active = programs.first(where: \.isActive) ?? programs.first else {
            IntentRouter.shared.request(.home)
            return .result(dialog: "Aucun programme n’est encore créé.")
        }

        let completed = try context.fetch(FetchDescriptor<CompletedSession>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        ))
        let next = HomeView.nextSession(for: active, completedSessions: completed)

        IntentRouter.shared.request(.home)
        guard let next else {
            return .result(dialog: "Le programme « \(active.name) » ne contient aucune séance.")
        }
        return .result(dialog: "Prochaine séance : \(next.name).")
    }
}

// MARK: - Ouvrir un programme

struct OpenProgramIntent: AppIntent {
    static let title: LocalizedStringResource = "Ouvrir un programme"
    static let description = IntentDescription("Affiche un programme dans Muscu.")
    static let openAppWhenRun = true

    @Parameter(title: "Programme")
    var program: ProgramEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        IntentRouter.shared.request(.program(program.id))
        return .result(dialog: "Ouverture de « \(program.name) ».")
    }
}

// MARK: - Ouvrir un exercice

struct OpenExerciseIntent: AppIntent {
    static let title: LocalizedStringResource = "Ouvrir un exercice"
    static let description = IntentDescription("Affiche la fiche d’un exercice dans Muscu.")
    static let openAppWhenRun = true

    @Parameter(title: "Exercice")
    var exercise: ExerciseEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        IntentRouter.shared.request(.exercise(exercise.id))
        return .result(dialog: "Ouverture de « \(exercise.name) ».")
    }
}

// MARK: - Enregistrer le poids corporel

struct LogBodyweightIntent: AppIntent {
    static let title: LocalizedStringResource = "Enregistrer le poids corporel"
    static let description = IntentDescription("Ajoute une mesure de poids corporel.")
    /// Une ecriture ne part jamais sans confirmation : un raccourci
    /// declenche par erreur ne doit pas polluer le suivi.
    static let isDiscoverable = true

    @Parameter(title: "Poids", controlStyle: .field)
    var weight: Double

    @Parameter(title: "Unité")
    var unit: MassUnitAppEnum?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard weight > 0, weight < 700 else {
            throw $weight.needsValueError("Quel poids faut-il enregistrer ?")
        }

        let context = try IntentStore.context()
        let resolvedUnit = (unit ?? MassUnitAppEnum(ProfileStore.massUnit(in: context))).massUnit
        let kilograms = resolvedUnit.toKilograms(weight)
        let formatted = String(format: "%.1f", weight)

        // Confirmation explicite avant toute ecriture : un raccourci
        // declenche par erreur ne doit pas polluer le suivi.
        try await requestConfirmation(
            actionName: .set,
            dialog: IntentDialog("Enregistrer \(formatted) \(resolvedUnit.symbol) comme poids corporel ?")
        )

        let measurement = BodyMeasurement(
            kindRaw: BodyMeasurementKind.bodyweight.rawValue,
            measuredAt: .now,
            value: kilograms,
            sourceRaw: MeasurementSource.manual.rawValue
        )
        context.insert(measurement)
        guard PersistenceSupport.save(context, action: "Enregistrement du poids") else {
            return .result(dialog: "Le poids n’a pas pu être enregistré.")
        }
        return .result(dialog: "Poids enregistré : \(formatted) \(resolvedUnit.symbol).")
    }
}

enum MassUnitAppEnum: String, AppEnum {
    case kilograms
    case pounds

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource("Unité de masse"))
    static let caseDisplayRepresentations: [MassUnitAppEnum: DisplayRepresentation] = [
        .kilograms: DisplayRepresentation(title: LocalizedStringResource("Kilogrammes")),
        .pounds: DisplayRepresentation(title: LocalizedStringResource("Livres")),
    ]

    init(_ unit: MassUnit) {
        self = unit == .pounds ? .pounds : .kilograms
    }

    var massUnit: MassUnit { self == .pounds ? .pounds : .kilograms }
}

// MARK: - Minuteur de repos

struct StartRestTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Lancer un minuteur de repos"
    static let description = IntentDescription("Démarre un minuteur de repos dans Muscu.")
    static let openAppWhenRun = true

    @Parameter(title: "Durée (secondes)", default: 90, inclusiveRange: (5, 900))
    var seconds: Int

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        RestTimerLauncher.shared.request(seconds: seconds)
        IntentRouter.shared.request(.home)
        return .result(dialog: "Minuteur de \(seconds) secondes lancé.")
    }
}

/// Demande de minuteur deposee par un raccourci et consommee par l'interface.
@MainActor
@Observable
final class RestTimerLauncher {
    static let shared = RestTimerLauncher()

    private(set) var pendingSeconds: Int?

    private init() {}

    func request(seconds: Int) { pendingSeconds = seconds }

    func consume() -> Int? {
        defer { pendingSeconds = nil }
        return pendingSeconds
    }
}

// MARK: - Résumé de la semaine

struct WeeklySummaryIntent: AppIntent {
    static let title: LocalizedStringResource = "Afficher le résumé de la semaine"
    static let description = IntentDescription("Résume les séances des sept derniers jours.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = try IntentStore.context()
        let since = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
        let sessions = try context.fetch(FetchDescriptor<CompletedSession>())
            .filter { $0.deletedAt == nil && $0.date >= since }

        guard !sessions.isEmpty else {
            return .result(dialog: "Aucune séance sur les sept derniers jours.")
        }

        let workingSets = sessions.reduce(0) { $0 + $1.workingSets.count }
        let tonnage = SetMetrics.totalTonnage(sessions.flatMap { $0.metricsInputs() })
        let unit = ProfileStore.massUnit(in: context)
        let tonnageText = tonnage.total > 0
            ? String(format: "%.0f %@ de tonnage", unit.fromKilograms(tonnage.total), unit.symbol)
            : "tonnage inconnu"

        return .result(dialog: "\(sessions.count) séance(s), \(workingSets) série(s) de travail, \(tonnageText).")
    }
}

// MARK: - Raccourcis proposés

struct MuscuShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartNextWorkoutIntent(),
            phrases: [
                "Démarrer ma séance dans \(.applicationName)",
                "Start my workout in \(.applicationName)",
            ],
            shortTitle: "Prochaine séance",
            systemImageName: "play.circle"
        )
        AppShortcut(
            intent: WeeklySummaryIntent(),
            phrases: [
                "Résumé de ma semaine dans \(.applicationName)",
                "Weekly summary in \(.applicationName)",
            ],
            shortTitle: "Résumé de la semaine",
            systemImageName: "chart.bar"
        )
        AppShortcut(
            intent: StartRestTimerIntent(),
            phrases: [
                "Lancer un repos dans \(.applicationName)",
                "Start a rest timer in \(.applicationName)",
            ],
            shortTitle: "Minuteur de repos",
            systemImageName: "timer"
        )
    }
}
