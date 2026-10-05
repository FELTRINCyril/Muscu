import SwiftUI
import SwiftData
import MuscuEngine

// Objectifs : fréquence, séries hebdomadaires par muscle, exercice ou mesure
// corporelle. L'avancement est factuel et non culpabilisant ; mettre en pause
// ou archiver ne réécrit jamais l'historique.
struct GoalsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(CatalogStore.self) private var catalogStore

    @Query(
        filter: #Predicate<TrainingGoal> { $0.deletedAt == nil },
        sort: \TrainingGoal.createdAt,
        order: .reverse
    )
    private var goals: [TrainingGoal]

    @State private var showingEditor = false
    @State private var sessions: [AnalyticsSession] = []

    var body: some View {
        List {
            if goals.isEmpty {
                ContentUnavailableView(
                    "Aucun objectif",
                    systemImage: "target",
                    description: Text("Un objectif sert de repère. Il reste facultatif et modifiable à tout moment.")
                )
            } else {
                ForEach(goals) { goal in
                    row(goal)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Objectifs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingEditor = true
                } label: {
                    Label("Ajouter", systemImage: "plus")
                }
                .accessibilityIdentifier("goals.add")
            }
        }
        .sheet(isPresented: $showingEditor) {
            GoalEditorView()
        }
        .onAppear {
            sessions = AnalyticsBridge.sessions(context: modelContext, catalogStore: catalogStore)
        }
    }

    @ViewBuilder
    private func row(_ goal: TrainingGoal) -> some View {
        let progress = progress(for: goal)

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(goal.title.isEmpty ? "Objectif" : goal.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(stateLabel(goal.state))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(goal.state == .reached ? Theme.accent : .secondary)
            }

            if let progress {
                if let ratio = progress.ratio {
                    ProgressView(value: ratio)
                        .tint(Theme.accent)
                        .accessibilityHidden(true)
                }
                Text(progress.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Cet objectif n'est pas exploitable sur cet appareil.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let dueDate = goal.dueDate {
                Text("Échéance : \(MeasurementsView.dateFormatter.string(from: dueDate))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let target = goal.target, let caution = GoalEvaluator.cautionMessage(for: target) {
                Label(caution, systemImage: "info.circle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button(goal.state == .paused ? "Reprendre" : "Mettre en pause") {
                    goal.state = goal.state == .paused ? .active : .paused
                    save(goal)
                }
                .font(.footnote)
                .buttonStyle(.bordered)

                Button("Archiver") {
                    goal.state = .archived
                    save(goal)
                }
                .font(.footnote)
                .buttonStyle(.bordered)
                .accessibilityIdentifier("goal.archive")
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }

    /// Avancement d'un objectif. La valeur observée vient toujours des
    /// calculs partagés : jamais d'un recalcul local.
    private func progress(for goal: TrainingGoal) -> GoalProgress? {
        guard let target = goal.target else { return nil }
        return GoalEvaluator.progress(
            target: target,
            observation: GoalObservation(current: currentValue(for: target), startValue: goal.startValue)
        )
    }

    private func currentValue(for target: GoalTarget) -> Double? {
        let calendar = TrainingAnalytics.calendar()
        let weeks = TrainingAnalytics.weeklySummaries(sessions: sessions, calendar: calendar)

        switch target {
        case .sessionsPerWeek:
            guard let last = weeks.last else { return nil }
            return Double(last.sessionCount)

        case .weeklySetsForMuscle(let muscle, _):
            guard let last = weeks.last else { return nil }
            return Double(last.setsByMuscle[muscle] ?? 0)

        case .exerciseOneRepMax(let exerciseId, _):
            return TrainingAnalytics
                .series(metric: .estimatedOneRepMax, exerciseId: exerciseId, sessions: sessions)
                .map(\.value)
                .max()

        case .exerciseReps(let exerciseId, _):
            return TrainingAnalytics
                .series(metric: .maxReps, exerciseId: exerciseId, sessions: sessions)
                .map(\.value)
                .max()

        case .bodyMeasurement(let kindRaw, _, _):
            var descriptor = FetchDescriptor<BodyMeasurement>(
                predicate: #Predicate { $0.kindRaw == kindRaw && $0.deletedAt == nil },
                sortBy: [SortDescriptor(\.measuredAt, order: .reverse)]
            )
            descriptor.fetchLimit = 1
            return (try? modelContext.fetch(descriptor))?.first?.value
        }
    }

    private func save(_ goal: TrainingGoal) {
        goal.updatedAt = .now
        _ = PersistenceSupport.save(modelContext, action: "Mise à jour de l’objectif")
    }

    private func stateLabel(_ state: GoalState) -> String {
        switch state {
        case .active: return "En cours"
        case .paused: return "En pause"
        case .reached: return "Atteint"
        case .archived: return "Archivé"
        }
    }
}

/// Création d'un objectif. Les bornes de bon sens viennent du moteur : une
/// saisie aberrante est refusée avant d'être enregistrée.
struct GoalEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.massUnit) private var massUnit

    private enum Kind: String, CaseIterable, Identifiable {
        case sessionsPerWeek = "Séances par semaine"
        case weeklySets = "Séries hebdomadaires"
        case bodyweight = "Poids corporel"

        var id: String { rawValue }
    }

    @State private var kind: Kind = .sessionsPerWeek
    @State private var title = ""
    @State private var sessionsPerWeek = 4
    @State private var weeklySets = 12
    @State private var muscle = "chest"
    @State private var bodyweightText = ""
    @State private var hasDueDate = false
    @State private var dueDate = Date.now.addingTimeInterval(60 * 60 * 24 * 60)

    var body: some View {
        NavigationStack {
            Form {
                Section("Type") {
                    Picker("Type d'objectif", selection: $kind) {
                        ForEach(Kind.allCases) { kind in
                            Text(kind.rawValue).tag(kind)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("goal.kindPicker")
                }

                Section("Cible") {
                    switch kind {
                    case .sessionsPerWeek:
                        Stepper("\(sessionsPerWeek) séances par semaine", value: $sessionsPerWeek, in: 1...14)
                    case .weeklySets:
                        Picker("Muscle", selection: $muscle) {
                            ForEach(Self.muscles, id: \.self) { key in
                                Text(FrenchLabels.muscle(key)).tag(key)
                            }
                        }
                        Stepper("\(weeklySets) séries par semaine", value: $weeklySets, in: 1...60)
                    case .bodyweight:
                        HStack {
                            TextField("Poids visé", text: $bodyweightText)
                                .keyboardType(.decimalPad)
                                .accessibilityIdentifier("goal.bodyweight")
                            Text(massUnit.symbol).foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Toggle("Fixer une échéance", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Échéance", selection: $dueDate, displayedComponents: [.date])
                    }
                } footer: {
                    Text("L'échéance est facultative. Un objectif sans date reste valable aussi longtemps que vous le souhaitez.")
                }

                Section("Titre") {
                    TextField("Optionnel", text: $title)
                }

                if let caution = target.flatMap(GoalEvaluator.cautionMessage(for:)) {
                    Section {
                        Text(caution)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Nouvel objectif")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }
                        .disabled(target?.isWithinSaneBounds != true)
                        .accessibilityIdentifier("goal.save")
                }
            }
        }
    }

    private var target: GoalTarget? {
        switch kind {
        case .sessionsPerWeek:
            return .sessionsPerWeek(count: sessionsPerWeek)
        case .weeklySets:
            return .weeklySetsForMuscle(muscle: muscle, sets: weeklySets)
        case .bodyweight:
            let normalized = bodyweightText.replacingOccurrences(of: ",", with: ".")
            guard let value = Double(normalized) else { return nil }
            // L'objectif est stocke en kg, comme les mesures qu'il compare.
            return .bodyMeasurement(
                kindRaw: BodyMeasurementKind.bodyweight.rawValue,
                value: massUnit.toKilograms(value),
                direction: .decrease
            )
        }
    }

    private func save() {
        guard let target, target.isWithinSaneBounds else { return }
        let goal = TrainingGoal(
            title: title.isEmpty ? defaultTitle : title,
            targetData: try? JSONEncoder().encode(target),
            dueDate: hasDueDate ? dueDate : nil,
            startValue: startValue(for: target)
        )
        modelContext.insert(goal)
        if PersistenceSupport.save(modelContext, action: "Création de l’objectif") {
            dismiss()
        }
    }

    /// Point de départ figé à la création : sans lui, un objectif en baisse
    /// ne peut pas exprimer d'avancement.
    private func startValue(for target: GoalTarget) -> Double? {
        guard case .bodyMeasurement(let kindRaw, _, _) = target else { return nil }
        var descriptor = FetchDescriptor<BodyMeasurement>(
            predicate: #Predicate { $0.kindRaw == kindRaw && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.measuredAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first?.value
            ?? ProfileStore.currentProfile(in: modelContext)?.bodyweightKilograms
    }

    private var defaultTitle: String {
        switch kind {
        case .sessionsPerWeek: return String(localized: "\(sessionsPerWeek) séances par semaine")
        case .weeklySets: return String(localized: "\(weeklySets) séries · \(FrenchLabels.muscle(muscle))")
        case .bodyweight: return String(localized: "Poids visé")
        }
    }

    private static let muscles = [
        "chest", "lats", "middle back", "shoulders", "biceps", "triceps",
        "quadriceps", "hamstrings", "glutes", "abdominals", "calves",
    ]
}
