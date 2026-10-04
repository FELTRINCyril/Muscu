import SwiftUI
import SwiftData
import Charts
import MuscuEngine

// Tableaux de bord. Aucun calcul n'est fait ici : tout vient de
// `MuscuEngine.TrainingAnalytics`, pour que deux écrans affichant le même
// indicateur affichent forcément la même valeur.
//
// Chaque graphique indique son unité, sa période, la formule employée et le
// nombre de séries dont la donnée manque. Chacun expose aussi une
// alternative textuelle lisible par VoiceOver.
struct ChartsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(CatalogStore.self) private var catalogStore
    @Environment(\.massUnit) private var massUnit

    @State private var sessions: [AnalyticsSession] = []
    @State private var selectedExerciseId: String?
    @State private var selectedMetric: ExerciseMetric = .estimatedOneRepMax
    @State private var window: AnalysisWindow = .twelveWeeks
    @State private var heatmapMetric: TrainingAnalytics.HeatmapMetric = .sessions

    /// Fenêtre d'analyse. Toujours affichée : un indicateur sans période
    /// n'est pas interprétable.
    private enum AnalysisWindow: String, CaseIterable, Identifiable {
        case fourWeeks = "4 semaines"
        case twelveWeeks = "12 semaines"
        case all = "Tout"

        var id: String { rawValue }

        var weeks: Int? {
            switch self {
            case .fourWeeks: return 4
            case .twelveWeeks: return 12
            case .all: return nil
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if sessions.isEmpty {
                    ContentUnavailableView(
                        "Aucune donnée",
                        systemImage: "chart.line.uptrend.xyaxis",
                        description: Text("Terminez des séances pour voir vos tableaux de bord.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else {
                    windowPicker
                    volumeCard
                    muscleDistributionCard
                    frequencyCard
                    heatmapCard
                    exerciseCard
                    comparisonCard
                }
            }
            .padding()
        }
        .background(Theme.background)
        .onAppear(perform: reload)
    }

    private var windowPicker: some View {
        Picker("Période", selection: $window) {
            ForEach(AnalysisWindow.allCases) { option in
                Text(option.rawValue).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("charts.windowPicker")
    }

    // MARK: - Calendrier de chaleur

    private var heatmapCard: some View {
        ChartCard(
            title: "Calendrier de chaleur",
            subtitle: "\(heatmapMetric.displayName) par jour · \(periodLabel)",
            footnote: heatmapMetric.explanation + " Échelle linéaire sur \(TrainingAnalytics.heatmapLevelCount) niveaux, maximum de la période : \(heatmapMaximumLabel).",
            missingDataNote: heatmapMissingNote,
            textAlternative: heatmapAlternative
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Grandeur", selection: $heatmapMetric) {
                    ForEach(TrainingAnalytics.HeatmapMetric.allCases) { metric in
                        Text(metric.displayName).tag(metric)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("charts.heatmapMetric")

                heatmapGrid
            }
        }
    }

    private var heatmapGrid: some View {
        // Une colonne par semaine, une ligne par jour de la semaine : la
        // lecture verticale suit la semaine, comme un calendrier.
        HStack(alignment: .top, spacing: 3) {
            ForEach(heatmapWeeks, id: \.self) { weekStart in
                VStack(spacing: 3) {
                    ForEach(0..<7, id: \.self) { offset in
                        let day = calendar.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart
                        heatmapCell(day)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func heatmapCell(_ day: Date) -> some View {
        let entry = heatmapValues[calendar.startOfDay(for: day)]
        let level = TrainingAnalytics.heatmapLevel(value: entry?.value ?? 0, maximum: heatmapMaximum)
        return RoundedRectangle(cornerRadius: 2)
            .fill(day > Date.now ? Color.clear : Theme.accent.opacity(level == 0 ? 0.12 : 0.2 + 0.2 * Double(level)))
            .frame(width: 10, height: 10)
    }

    private var heatmapValues: [Date: TrainingAnalytics.HeatmapDay] {
        TrainingAnalytics.heatmap(sessions: windowedSessions, metric: heatmapMetric, calendar: calendar)
    }

    private var heatmapMaximum: Double {
        heatmapValues.values.map(\.value).max() ?? 0
    }

    private var heatmapMaximumLabel: String {
        guard heatmapMaximum > 0 else { return String(localized: "aucune donnée") }
        let value = WeightFormatter.number(heatmapDisplayValue(heatmapMaximum))
        return heatmapUnit.map { String(localized: "\(value) \($0)") } ?? value
    }

    /// Semaines couvertes par la fenêtre, de la plus ancienne à la plus
    /// récente.
    private var heatmapWeeks: [Date] {
        let days = windowedSessions.map(\.date)
        guard let first = days.min() else { return [] }
        var weeks: [Date] = []
        var cursor = TrainingAnalytics.startOfWeek(for: first, calendar: calendar)
        let end = TrainingAnalytics.startOfWeek(for: Date.now, calendar: calendar)
        while cursor <= end, weeks.count < 60 {
            weeks.append(cursor)
            guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: cursor) else { break }
            cursor = next
        }
        return weeks
    }

    private var heatmapMissingNote: String? {
        let unknown = heatmapValues.values.reduce(0) { $0 + $1.unknownSets }
        guard unknown > 0 else { return nil }
        return String(localized: "\(unknown) série(s) sans charge effective connue ne sont pas comptées.")
    }

    private var heatmapAlternative: String {
        let active = heatmapValues.values.filter { $0.value > 0 }
        guard !active.isEmpty else {
            return String(localized: "Aucune donnée de \(heatmapMetric.displayName.lowercased()) sur la période.")
        }
        let total = active.reduce(0) { $0 + $1.value }
        let best = active.max { $0.value < $1.value }
        let bestDay = best.map { Self.dayFormatter.string(from: $0.date) } ?? ""
        // Le suffixe d'unite est assemble AVANT la chaine localisee : un
        // litteral imbrique dans une interpolation ne peut pas etre
        // extrait par le catalogue.
        let unit = heatmapUnit.map { " " + $0 } ?? ""
        return String(localized: "\(active.count) jour(s) actif(s) sur la période, total \(WeightFormatter.number(heatmapDisplayValue(total)))\(unit), maximum le \(bestDay).")
    }

    /// Le moteur calcule en kg ; seule une grandeur de masse est convertie
    /// dans l'unite du profil.
    private var heatmapUnit: String? {
        heatmapMetric.unit == MassUnit.kilograms.symbol ? massUnit.symbol : heatmapMetric.unit
    }

    private func heatmapDisplayValue(_ value: Double) -> Double {
        heatmapMetric.unit == MassUnit.kilograms.symbol ? massUnit.fromKilograms(value) : value
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.setLocalizedDateFormatFromTemplate("dMMMM")
        return formatter
    }()

    // MARK: - Volume hebdomadaire

    private var volumeCard: some View {
        ChartCard(
            title: "Volume par semaine",
            subtitle: "Séries de travail et tonnage · \(periodLabel)",
            footnote: ExerciseMetric.tonnage.formulaDescription,
            missingDataNote: missingTonnageNote,
            textAlternative: volumeAlternative
        ) {
            Chart(weeks, id: \.weekStart) { week in
                BarMark(
                    x: .value("Semaine", week.weekStart, unit: .weekOfYear),
                    y: .value("Séries", week.workingSetCount)
                )
                .foregroundStyle(Theme.accent)
            }
            .chartYAxisLabel("séries")
            .frame(height: 180)
        }
    }

    private var missingTonnageNote: String? {
        let unknown = weeks.reduce(0) { $0 + $1.tonnage.unknownSets }
        guard unknown > 0 else { return nil }
        return String(localized: "\(unknown) série(s) sans poids de corps connu : leur tonnage n'est pas comptabilisé. Renseignez votre poids dans le profil pour les inclure.")
    }

    private var volumeAlternative: String {
        guard let last = weeks.last else { return String(localized: "Aucune semaine sur la période.") }
        let total = TrainingAnalytics.merged(weeks)
        let tonnage = total.tonnage.isComplete
            ? String(localized: "\(WeightFormatter.string(kilograms: total.tonnage.value, unit: massUnit)) de tonnage")
            : String(localized: "tonnage partiel (\(total.tonnage.unknownSets) séries non mesurables)")
        return String(localized: "\(weeks.count) semaines analysées, \(total.workingSetCount) séries de travail, \(tonnage). Dernière semaine : \(last.workingSetCount) séries, \(last.sessionCount) séance(s).")
    }

    // MARK: - Répartition par muscle

    private var muscleDistributionCard: some View {
        ChartCard(
            title: "Répartition par muscle",
            subtitle: "Séries de travail · \(periodLabel)",
            footnote: "Seuls les muscles principaux de chaque exercice sont comptés.",
            missingDataNote: imbalanceNote,
            textAlternative: distributionAlternative
        ) {
            Chart(topMuscles, id: \.muscle) { entry in
                BarMark(
                    x: .value("Séries", entry.sets),
                    y: .value("Muscle", FrenchLabels.muscle(entry.muscle))
                )
                .foregroundStyle(Theme.accent)
            }
            .chartXAxisLabel("séries")
            .frame(height: CGFloat(max(1, topMuscles.count)) * 28 + 40)
        }
    }

    private var imbalanceNote: String? {
        let findings = TrainingAnalytics.imbalances(weeklySetsByMuscle: setsByMuscle)
        guard !findings.isEmpty else { return nil }
        let names = findings.prefix(3).map { FrenchLabels.muscle($0.muscle) }.joined(separator: ", ")
        return String(localized: "Nettement moins travaillé(s) que la médiane sur la période : \(names). C'est un écart de volume observé, pas un jugement sur votre programme.")
    }

    private var distributionAlternative: String {
        guard !topMuscles.isEmpty else { return String(localized: "Aucun muscle identifié sur la période.") }
        let detail = topMuscles.prefix(5)
            .map { String(localized: "\(FrenchLabels.muscle($0.muscle)) \($0.sets) séries") }
            .joined(separator: ", ")
        return String(localized: "Répartition sur \(periodLabel) : \(detail).")
    }

    // MARK: - Fréquence

    private var frequencyCard: some View {
        ChartCard(
            title: "Fréquence",
            subtitle: "Séances par semaine · \(periodLabel)",
            footnote: adherenceLabel,
            missingDataNote: nil,
            textAlternative: frequencyAlternative
        ) {
            Chart(TrainingAnalytics.sessionsPerWeek(sessions: windowedSessions, calendar: calendar), id: \.date) { point in
                LineMark(x: .value("Semaine", point.date, unit: .weekOfYear), y: .value("Séances", point.value))
                    .foregroundStyle(Theme.accent)
                PointMark(x: .value("Semaine", point.date, unit: .weekOfYear), y: .value("Séances", point.value))
                    .foregroundStyle(Theme.accent)
            }
            .chartYAxisLabel("séances")
            .frame(height: 160)
        }
    }

    private var adherenceLabel: String {
        guard let first = weeks.first?.weekStart, let last = weeks.last?.weekStart else {
            return String(localized: "Aucune séance planifiée sur la période.")
        }
        let end = calendar.date(byAdding: .day, value: 7, to: last) ?? last
        let adherence = AnalyticsBridge.adherence(context: modelContext, from: first, to: end)
        guard let ratio = adherence.ratio else {
            return String(localized: "Aucune séance planifiée sur la période : l'adhérence n'est pas calculable.")
        }
        return String(localized: "Adhérence au planning : \(adherence.completedCount)/\(adherence.plannedCount) séances prévues (\(Int(ratio * 100)) %).")
    }

    private var frequencyAlternative: String {
        let streak = TrainingAnalytics.currentWeeklyStreak(sessions: sessions, now: .now, calendar: calendar)
        let total = weeks.reduce(0) { $0 + $1.sessionCount }
        return String(localized: "\(total) séance(s) sur \(periodLabel). Semaines consécutives avec au moins une séance : \(streak).")
    }

    // MARK: - Évolution par exercice

    @ViewBuilder
    private var exerciseCard: some View {
        if exerciseOptions.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Exercice", selection: $selectedExerciseId) {
                    ForEach(exerciseOptions, id: \.id) { option in
                        Text(option.displayName).tag(option.id as String?)
                    }
                }
                .pickerStyle(.menu)
                .tint(Theme.accent)
                .accessibilityIdentifier("charts.exercisePicker")

                if availableMetrics.count > 1 {
                    Picker("Indicateur", selection: $selectedMetric) {
                        ForEach(availableMetrics, id: \.self) { metric in
                            Text(metricLabel(metric)).tag(metric)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                ChartCard(
                    title: metricLabel(effectiveMetric),
                    subtitle: unitLabel(effectiveMetric) + " · " + periodLabel,
                    footnote: effectiveMetric.formulaDescription(
                        maximumRepsForOneRepMax: WorkoutSettings.maximumRepsForOneRepMax
                    ),
                    missingDataNote: exerciseMissingNote,
                    textAlternative: exerciseAlternative
                ) {
                    Chart(exerciseSeries, id: \.date) { point in
                        LineMark(x: .value("Date", point.date), y: .value(metricLabel(effectiveMetric), point.value))
                            .foregroundStyle(Theme.accent)
                        PointMark(x: .value("Date", point.date), y: .value(metricLabel(effectiveMetric), point.value))
                            .foregroundStyle(Theme.accent)
                    }
                    .frame(height: 180)
                }
            }
        }
    }

    private var exerciseMissingNote: String? {
        guard let selectedExerciseId else { return nil }
        let sessionsWithExercise = windowedSessions.filter { session in
            session.workingSets.contains { $0.exerciseId == selectedExerciseId }
        }
        let missing = sessionsWithExercise.count - exerciseSeries.count
        guard missing > 0 else { return nil }
        return String(localized: "\(missing) séance(s) sans valeur exploitable pour cet indicateur : elles sont absentes de la courbe plutôt qu'affichées à zéro.")
    }

    private var exerciseAlternative: String {
        guard let first = exerciseSeries.first, let last = exerciseSeries.last else {
            return String(localized: "Aucune valeur exploitable pour cet exercice sur la période.")
        }
        let unit = displayUnitSymbol(effectiveMetric)
        let start = WeightFormatter.number(first.value) + (unit.isEmpty ? "" : " " + unit)
        let end = WeightFormatter.number(last.value) + (unit.isEmpty ? "" : " " + unit)
        return String(localized: "\(exerciseSeries.count) point(s), de \(start) à \(end) sur \(periodLabel).")
    }

    // MARK: - Comparaison de périodes

    @ViewBuilder
    private var comparisonCard: some View {
        if let comparison {
            ChartCard(
                title: "Comparaison",
                subtitle: "Moitié récente vs moitié précédente · \(periodLabel)",
                footnote: "Constat chiffré sur la période, sans lien de cause à effet.",
                missingDataNote: nil,
                textAlternative: comparison.summaryText
            ) {
                Text(comparison.summaryText)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var comparison: PeriodComparison? {
        guard weeks.count >= 4 else { return nil }
        let midpoint = weeks.count / 2
        let previous = TrainingAnalytics.merged(Array(weeks.prefix(midpoint)))
        let current = TrainingAnalytics.merged(Array(weeks.suffix(weeks.count - midpoint)))
        return TrainingAnalytics.compare(previous: previous, current: current)
    }

    // MARK: - Données

    private var calendar: Calendar { TrainingAnalytics.calendar() }

    private var windowedSessions: [AnalyticsSession] {
        guard let weeksBack = window.weeks else { return sessions }
        let start = calendar.date(
            byAdding: .weekOfYear,
            value: -weeksBack,
            to: TrainingAnalytics.startOfWeek(for: .now, calendar: calendar)
        ) ?? .distantPast
        return sessions.filter { $0.date >= start }
    }

    private var weeks: [WeeklySummary] {
        TrainingAnalytics.filled(
            weeks: TrainingAnalytics.weeklySummaries(sessions: windowedSessions, calendar: calendar),
            calendar: calendar
        )
    }

    private var setsByMuscle: [String: Int] {
        TrainingAnalytics.setsByMuscle(sessions: windowedSessions)
    }

    private var topMuscles: [(muscle: String, sets: Int)] {
        setsByMuscle
            .map { (muscle: $0.key, sets: $0.value) }
            .sorted { ($0.sets, $1.muscle) > ($1.sets, $0.muscle) }
            .prefix(8)
            .map { $0 }
    }

    private var exerciseOptions: [(id: String, displayName: String)] {
        var seen: [String: String] = [:]
        for session in windowedSessions {
            for set in session.workingSets { seen[set.exerciseId] = set.displayName }
        }
        return seen.map { (id: $0.key, displayName: $0.value) }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    private var availableMetrics: [ExerciseMetric] {
        guard let selectedExerciseId else { return [] }
        return TrainingAnalytics.availableMetrics(exerciseId: selectedExerciseId, sessions: windowedSessions)
    }

    /// Indicateur réellement affichable : si celui choisi n'a aucune donnée
    /// pour cet exercice, on retombe sur le premier disponible.
    private var effectiveMetric: ExerciseMetric {
        availableMetrics.contains(selectedMetric) ? selectedMetric : (availableMetrics.first ?? .maxReps)
    }

    /// Serie affichee, convertie dans l'unite du profil pour un indicateur
    /// de masse. Les calculs restent faits en kg par le moteur.
    private var exerciseSeries: [AnalyticsPoint] {
        guard let selectedExerciseId else { return [] }
        let series = TrainingAnalytics.series(metric: effectiveMetric, exerciseId: selectedExerciseId, sessions: windowedSessions)
        guard isMassMetric(effectiveMetric) else { return series }
        return series.map { AnalyticsPoint(date: $0.date, value: massUnit.fromKilograms($0.value)) }
    }

    private func isMassMetric(_ metric: ExerciseMetric) -> Bool {
        metric.unitSymbol == MassUnit.kilograms.symbol
    }

    private func displayUnitSymbol(_ metric: ExerciseMetric) -> String {
        isMassMetric(metric) ? massUnit.symbol : metric.unitSymbol
    }

    private var periodLabel: String {
        window == .all ? String(localized: "tout l'historique") : window.rawValue.lowercased()
    }

    private func metricLabel(_ metric: ExerciseMetric) -> String {
        switch metric {
        case .estimatedOneRepMax: return "1RM estimé"
        case .maxLoad: return "Charge max"
        case .maxReps: return "Répétitions max"
        case .tonnage: return "Tonnage"
        }
    }

    private func unitLabel(_ metric: ExerciseMetric) -> String {
        metric.unitSymbol.isEmpty ? "répétitions" : displayUnitSymbol(metric)
    }

    private func reload() {
        sessions = AnalyticsBridge.sessions(context: modelContext, catalogStore: catalogStore)
        if selectedExerciseId == nil { selectedExerciseId = exerciseOptions.first?.id }
    }
}

/// Carte de graphique : titre, période, formule, données manquantes et
/// alternative textuelle. Le graphique lui-même est masqué à VoiceOver, qui
/// lit l'alternative — un nuage de points n'est pas lisible autrement.
private struct ChartCard<Content: View>: View {
    let title: String
    let subtitle: String
    let footnote: String
    let missingDataNote: String?
    let textAlternative: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            content
                .accessibilityHidden(true)

            Text(textAlternative)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("\(title). \(textAlternative)")

            if let missingDataNote {
                Label(missingDataNote, systemImage: "exclamationmark.circle")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            Text(footnote)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    ChartsView()
        .environment(CatalogStore())
        .modelContainer(for: CompletedSession.self, inMemory: true)
        .preferredColorScheme(.dark)
}
