import SwiftUI
import SwiftData
import MuscuEngine

// Sections communes aux fiches d'exercice (catalogue et perso) :
// statistiques de l'exercice et lien de demonstration personnel.

/// Statistiques d'un exercice : meilleur 1RM estime, force relative au poids
/// de corps, intensite moyenne et charge moyenne. Calculs dans le moteur
/// (`ExerciseStatistics`), periode et formules toujours affichees.
struct ExerciseStatsSection: View {
    let exerciseId: String

    @Environment(\.modelContext) private var modelContext
    @Environment(CatalogStore.self) private var catalogStore
    @Environment(\.massUnit) private var massUnit

    @State private var history: [AnalyticsSession] = []
    @State private var bodyweights: [AnalyticsPoint] = []
    @State private var window: Window = .twelveWeeks

    private enum Window: String, CaseIterable, Identifiable {
        case fourWeeks
        case twelveWeeks
        case all

        var id: String { rawValue }

        var weeks: Int? {
            switch self {
            case .fourWeeks: return 4
            case .twelveWeeks: return 12
            case .all: return nil
            }
        }

        var label: String {
            switch self {
            case .fourWeeks: return String(localized: "4 semaines")
            case .twelveWeeks: return String(localized: "12 semaines")
            case .all: return String(localized: "Tout")
            }
        }
    }

    var body: some View {
        Group {
            if hasHistory {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Statistiques")
                        .font(.headline)

                    Picker("Période", selection: $window) {
                        ForEach(Window.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("exercise.stats.window")

                    content
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .onAppear(perform: reload)
    }

    @ViewBuilder
    private var content: some View {
        let stats = statistics
        VStack(alignment: .leading, spacing: 8) {
            StatLine(
                title: String(localized: "Meilleur 1RM estimé"),
                value: stats.bestEstimatedOneRepMax.map { best in
                    String(localized: "\(WeightFormatter.string(kilograms: best.value, unit: massUnit)) le \(best.date.formatted(date: .abbreviated, time: .omitted))")
                } ?? String(localized: "Aucune série éligible")
            )
            StatLine(title: String(localized: "Force relative"), value: relativeStrengthText(stats))
            StatLine(
                title: String(localized: "Intensité moyenne"),
                value: stats.averageIntensity.map { intensity in
                    String(localized: "\(Int((intensity * 100).rounded())) % du 1RM estimé (\(stats.intensitySetCount) série(s))")
                } ?? String(localized: "Non calculable")
            )
            StatLine(
                title: String(localized: "Charge moyenne"),
                value: stats.averageLoad.map { load in
                    String(localized: "\(WeightFormatter.string(kilograms: load, unit: massUnit)) (\(stats.loadSetCount) série(s))")
                } ?? String(localized: "Non calculable")
            )

            if stats.unknownLoadSets > 0 {
                Label(
                    String(localized: "\(stats.unknownLoadSets) série(s) sans poids de corps connu : exclue(s) des moyennes plutôt que comptée(s) à zéro."),
                    systemImage: "exclamationmark.circle"
                )
                .font(.caption2)
                .foregroundStyle(.orange)
            }

            Text(formulas)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("exercise.stats")
    }

    private func relativeStrengthText(_ stats: ExerciseStatistics) -> String {
        guard stats.bestEstimatedOneRepMax != nil else { return String(localized: "Non calculable") }
        guard let ratio = stats.relativeStrength, let bodyweight = stats.bodyweightAtBest else {
            return String(localized: "Poids de corps inconnu à la date du meilleur 1RM : ajoutez une pesée dans Mesures.")
        }
        return String(localized: "\(WeightFormatter.number(ratio, maximumFractionDigits: 2)) × le poids de corps (\(WeightFormatter.string(kilograms: bodyweight, unit: massUnit)))")
    }

    private var formulas: String {
        let maximum = OneRepMaxEstimation.clamped(WorkoutSettings.maximumRepsForOneRepMax)
        return String(localized: "Période : \(periodLabel). 1RM estimé (Epley : charge × (1 + répétitions ⁄ 30)) sur les séries de travail de 1 à \(maximum) répétitions à charge réelle. Force relative = meilleur 1RM estimé ÷ poids de corps connu à cette date. Intensité = charge de chaque série ÷ meilleur 1RM estimé connu jusqu’à sa séance, en moyenne. Charge moyenne = moyenne des charges effectives des séries de travail chargées. Aucun niveau (débutant, avancé…) n’est attribué : il faudrait une table de référence sourcée.")
    }

    private var periodLabel: String {
        window == .all ? String(localized: "tout l’historique") : window.label.lowercased()
    }

    private var hasHistory: Bool {
        history.contains { session in session.workingSets.contains { $0.exerciseId == exerciseId } }
    }

    private var statistics: ExerciseStatistics {
        ExerciseStatistics.compute(exerciseId: exerciseId, history: history, period: period, bodyweights: bodyweights)
    }

    private var period: DateInterval {
        let calendar = TrainingAnalytics.calendar()
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now)) ?? .now
        guard let weeks = window.weeks else {
            return DateInterval(start: .distantPast, end: end)
        }
        let start = calendar.date(byAdding: .weekOfYear, value: -weeks, to: calendar.startOfDay(for: .now)) ?? .distantPast
        return DateInterval(start: start, end: end)
    }

    private func reload() {
        history = AnalyticsBridge.sessions(context: modelContext, catalogStore: catalogStore)
        bodyweights = AnalyticsBridge.bodyweightPoints(context: modelContext)
    }
}

private struct StatLine: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Lien de demonstration personnel (video, article) attache a l'exercice.
/// Seuls les liens `http`/`https` sont acceptes (`DemoLink`) ; la recherche
/// video generique reste proposee en repli.
struct DemoLinkSection: View {
    let exerciseId: String
    /// Recherche video de repli, quand aucun lien personnel n'est enregistre.
    let fallbackSearchQuery: String

    @Environment(\.modelContext) private var modelContext
    @Environment(NetworkStatus.self) private var networkStatus
    @Query private var libraryEntries: [ExerciseLibraryEntry]
    @State private var isEditing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let link = personalLink {
                if networkStatus.isOnline {
                    Link(destination: link) {
                        buttonLabel(String(localized: "Ma démonstration"), systemImage: "play.rectangle.fill")
                    }
                    .accessibilityIdentifier("exercise.demoLink.open")
                } else {
                    buttonLabel(String(localized: "Ma démonstration"), systemImage: "play.rectangle.fill")
                        .opacity(0.4)
                }
                Text(link.host() ?? link.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if networkStatus.isOnline {
                Link(destination: videoSearchURL) {
                    buttonLabel(
                        personalLink == nil ? String(localized: "Voir en vidéo") : String(localized: "Rechercher une autre vidéo"),
                        systemImage: "magnifyingglass"
                    )
                }
            } else {
                buttonLabel(String(localized: "Voir en vidéo"), systemImage: "magnifyingglass")
                    .opacity(0.4)
                Text("Connexion internet requise")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                isEditing = true
            } label: {
                Label(
                    personalLink == nil ? String(localized: "Ajouter mon lien de démonstration") : String(localized: "Modifier mon lien"),
                    systemImage: "link"
                )
                .font(.subheadline)
            }
            .accessibilityIdentifier("exercise.demoLink.edit")
        }
        .sheet(isPresented: $isEditing) {
            DemoLinkEditor(exerciseId: exerciseId, initialText: storedLink ?? "")
        }
    }

    private var storedLink: String? {
        libraryEntries.first { $0.exerciseId == exerciseId && $0.deletedAt == nil }?.demoURL
    }

    /// Un lien enregistre est revalide a l'affichage : une valeur venue
    /// d'une ancienne version ou d'une synchronisation n'est jamais ouverte
    /// sans controle.
    private var personalLink: URL? {
        guard let text = storedLink, let normalized = DemoLink.normalized(text) else { return nil }
        return URL(string: normalized)
    }

    private var videoSearchURL: URL {
        var components = URLComponents(string: "https://www.youtube.com/results")!
        components.queryItems = [URLQueryItem(name: "search_query", value: "\(fallbackSearchQuery) form")]
        return components.url!
    }

    private func buttonLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding()
            .background(Theme.card)
            .foregroundStyle(Theme.accent)
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// Saisie du lien de demonstration.
private struct DemoLinkEditor: View {
    let exerciseId: String
    let initialText: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var showsError = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://…", text: $text)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("exercise.demoLink.field")
                } footer: {
                    if showsError {
                        Text("Lien refusé : seule une adresse web complète, commençant par http:// ou https://, est acceptée.")
                            .foregroundStyle(.orange)
                    } else {
                        Text("Une vidéo ou un article qui montre le mouvement comme vous le pratiquez. Le lien s’ouvre dans le navigateur.")
                    }
                }

                if !initialText.isEmpty {
                    Section {
                        Button("Supprimer le lien", role: .destructive) {
                            if LibraryStore.setDemoURL(nil, for: exerciseId, in: modelContext) { dismiss() }
                        }
                    }
                }
            }
            .navigationTitle("Lien de démonstration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }
                        .accessibilityIdentifier("exercise.demoLink.save")
                }
            }
            .onAppear { text = initialText }
        }
    }

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty || DemoLink.isAcceptable(trimmed) else {
            showsError = true
            return
        }
        if LibraryStore.setDemoURL(trimmed, for: exerciseId, in: modelContext) {
            dismiss()
        }
    }
}
