import SwiftUI
import SwiftData
import Charts
import MuscuEngine

// Graphiques de progression : picker d'exercice (uniquement ceux presents
// dans l'historique) puis 1RM estime + tonnage par seance (ou max reps pour
// les exercices au poids du corps, sans serie chargee), plus un graphique
// global de tonnage hebdomadaire toutes seances confondues.
struct ChartsView: View {
    @Query(sort: \CompletedSession.date) private var sessions: [CompletedSession]

    @State private var selectedExerciseId: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if exerciseOptions.isEmpty {
                    ContentUnavailableView(
                        "Aucune donnée",
                        systemImage: "chart.line.uptrend.xyaxis",
                        description: Text("Terminez des séances pour voir vos graphiques de progression.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else {
                    Picker("Exercice", selection: $selectedExerciseId) {
                        ForEach(exerciseOptions) { option in
                            Text(option.displayName).tag(option.id as String?)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Theme.accent)

                    if let selected = selectedExercise {
                        exerciseCharts(for: selected)
                    }

                    weeklyTonnageChart
                }
            }
            .padding()
        }
        .background(Theme.background)
        .onAppear {
            if selectedExerciseId == nil {
                selectedExerciseId = exerciseOptions.first?.id
            }
        }
    }

    @ViewBuilder
    private func exerciseCharts(for option: ExerciseOption) -> some View {
        if isBodyweight(option.id) {
            ChartCard(title: "Max répétitions par séance") {
                Chart(maxRepsSeries(for: option.id)) { point in
                    LineMark(x: .value("Date", point.date), y: .value("Reps", point.value))
                        .foregroundStyle(Theme.accent)
                    PointMark(x: .value("Date", point.date), y: .value("Reps", point.value))
                        .foregroundStyle(Theme.accent)
                }
                .chartXAxis { dateAxis }
            }
        } else {
            ChartCard(title: "1RM estimé (kg)") {
                Chart(oneRepMaxSeries(for: option.id)) { point in
                    LineMark(x: .value("Date", point.date), y: .value("1RM", point.value))
                        .foregroundStyle(Theme.accent)
                    PointMark(x: .value("Date", point.date), y: .value("1RM", point.value))
                        .foregroundStyle(Theme.accent)
                }
                .chartXAxis { dateAxis }
            }

            ChartCard(title: "Tonnage par séance (kg)") {
                Chart(tonnageSeries(for: option.id)) { point in
                    BarMark(x: .value("Date", point.date), y: .value("Tonnage", point.value))
                        .foregroundStyle(Theme.accent)
                }
                .chartXAxis { dateAxis }
            }
        }
    }

    private var weeklyTonnageChart: some View {
        ChartCard(title: "Tonnage total par semaine (kg)") {
            Chart(weeklyTonnage) { point in
                BarMark(x: .value("Semaine", point.weekStart, unit: .weekOfYear), y: .value("Tonnage", point.tonnage))
                    .foregroundStyle(Theme.accent)
            }
            .chartXAxis { dateAxis }
        }
    }

    private var dateAxis: some AxisContent {
        AxisMarks(values: .automatic) { _ in
            AxisGridLine()
            AxisValueLabel(format: .dateTime.day().month(.abbreviated).locale(Locale(identifier: "fr_FR")))
        }
    }

    // MARK: - Donnees

    private struct ExerciseOption: Identifiable {
        let id: String
        let displayName: String
    }

    private struct SessionPoint: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
    }

    private struct WeekPoint: Identifiable {
        let id = UUID()
        let weekStart: Date
        let tonnage: Double
    }

    private var exerciseOptions: [ExerciseOption] {
        var seen: [String: String] = [:]
        for session in sessions {
            for set in session.sets where !set.isWarmup {
                seen[set.exerciseId] = set.displayName
            }
        }
        return seen.map { ExerciseOption(id: $0.key, displayName: $0.value) }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    private var selectedExercise: ExerciseOption? {
        exerciseOptions.first { $0.id == selectedExerciseId }
    }

    // Un exercice est "poids du corps" si aucune serie de travail de son
    // historique n'a de poids > 0 : dans ce cas le 1RM/tonnage n'ont pas de
    // sens, seul le nombre de repetitions progresse.
    private func isBodyweight(_ exerciseId: String) -> Bool {
        !sessions.contains { session in
            session.sets.contains { $0.exerciseId == exerciseId && !$0.isWarmup && $0.weight > 0 }
        }
    }

    private func oneRepMaxSeries(for exerciseId: String) -> [SessionPoint] {
        sessions.compactMap { session in
            let weighted = session.sets.filter { $0.exerciseId == exerciseId && !$0.isWarmup && $0.weight > 0 }
            guard let best = weighted.map({ OneRepMax.epley(weight: $0.weight, reps: $0.reps) }).max() else { return nil }
            return SessionPoint(date: session.date, value: best)
        }
    }

    private func tonnageSeries(for exerciseId: String) -> [SessionPoint] {
        sessions.compactMap { session in
            let sets = session.sets.filter { $0.exerciseId == exerciseId && !$0.isWarmup }
            guard !sets.isEmpty else { return nil }
            let tonnage = sets.reduce(0.0) { $0 + $1.weight * Double($1.reps) }
            return SessionPoint(date: session.date, value: tonnage)
        }
    }

    private func maxRepsSeries(for exerciseId: String) -> [SessionPoint] {
        sessions.compactMap { session in
            let sets = session.sets.filter { $0.exerciseId == exerciseId && !$0.isWarmup && $0.weight == 0 }
            guard let best = sets.map(\.reps).max() else { return nil }
            return SessionPoint(date: session.date, value: Double(best))
        }
    }

    private var weeklyTonnage: [WeekPoint] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: sessions) { session in
            calendar.dateInterval(of: .weekOfYear, for: session.date)?.start ?? session.date
        }
        return grouped.keys.sorted().map { weekStart in
            let tonnage = (grouped[weekStart] ?? []).reduce(0.0) { total, session in
                total + session.sets.filter { !$0.isWarmup }.reduce(0.0) { $0 + $1.weight * Double($1.reps) }
            }
            return WeekPoint(weekStart: weekStart, tonnage: tonnage)
        }
    }
}

private struct ChartCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            content
                .frame(height: 200)
        }
        .padding()
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    ChartsView()
        .modelContainer(for: CompletedSession.self, inMemory: true)
        .preferredColorScheme(.dark)
}
