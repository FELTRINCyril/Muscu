import SwiftUI
import SwiftData
import MuscuEngine

/// Calendrier du planning : jour, semaine ou mois.
///
/// Cet ecran ne montre QUE le planning. Une decision prise ici (deplacer,
/// ignorer, reporter) ne touche jamais l'historique : les seances terminees
/// y apparaissent en lecture seule, comme reperes.
struct PlanningView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case day, week, month

        var id: String { rawValue }

        var title: String {
            switch self {
            case .day: return String(localized: "Jour")
            case .week: return String(localized: "Semaine")
            case .month: return String(localized: "Mois")
            }
        }
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(CatalogStore.self) private var catalogStore

    @Query(sort: \ScheduledWorkout.plannedDate) private var workouts: [ScheduledWorkout]
    @Query(sort: \CompletedSession.date, order: .reverse) private var completedSessions: [CompletedSession]
    @Query(sort: \Program.name) private var programs: [Program]

    @State private var mode: Mode = .week
    @State private var anchor = Date.now
    @State private var workoutToMove: ScheduledWorkout?
    @State private var newDate = Date.now
    @State private var proposals: [RescheduleProposal] = []
    @State private var isAddingWorkout = false
    @State private var isShowingCalendar = false

    private var calendar: Calendar { .current }

    var body: some View {
        List {
            modeSection
            if !proposals.isEmpty { proposalsSection }
            if !conflicts.isEmpty { conflictsSection }
            contentSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Planning")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isAddingWorkout = true
                } label: {
                    Label("Ajouter une séance", systemImage: "plus")
                }
                .accessibilityIdentifier("planning.add")
            }
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink {
                    SchedulesView()
                } label: {
                    Label("Récurrences", systemImage: "repeat")
                }
                .accessibilityIdentifier("planning.schedules")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingCalendar = true
                } label: {
                    Label("Calendrier", systemImage: "calendar.badge.plus")
                }
                .accessibilityIdentifier("planning.calendar")
            }
        }
        .sheet(item: $workoutToMove) { workout in
            moveSheet(workout)
        }
        .sheet(isPresented: $isAddingWorkout) {
            AddScheduledWorkoutView(defaultDate: anchor)
        }
        .sheet(isPresented: $isShowingCalendar) {
            CalendarSyncView()
        }
        .onAppear(perform: refreshProposals)
        .onChange(of: workouts.count) { _, _ in refreshProposals() }
    }

    // MARK: - Sections

    private var modeSection: some View {
        Section {
            Picker("Vue", selection: $mode) {
                ForEach(Mode.allCases) { value in
                    Text(value.title).tag(value)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("planning.mode")

            HStack {
                Button {
                    shift(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("Période précédente")
                .accessibilityIdentifier("planning.previous")

                Spacer()
                Text(periodTitle)
                    .font(.headline)
                    .accessibilityIdentifier("planning.period")
                Spacer()

                Button {
                    shift(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .accessibilityLabel("Période suivante")
                .accessibilityIdentifier("planning.next")
            }
            .buttonStyle(.borderless)

            Button("Aujourd’hui") { anchor = .now }
                .accessibilityIdentifier("planning.today")
        }
    }

    private var proposalsSection: some View {
        Section {
            ForEach(proposals, id: \.workoutId) { proposal in
                VStack(alignment: .leading, spacing: 6) {
                    Text(title(for: proposal.workoutId))
                        .font(.subheadline.weight(.semibold))
                    Text("Prévue le \(Self.longDate.string(from: proposal.originalDate)), proposée le \(Self.longDate.string(from: proposal.proposedDate)).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(proposal.rationale)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !proposal.remainingConflicts.isEmpty {
                        Label("Un chevauchement subsiste à cette date.", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    HStack {
                        Button("Replanifier") {
                            PlanningService.accept(proposal, in: modelContext)
                            refreshProposals()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                        .accessibilityIdentifier("planning.proposal.accept")

                        Button("Ignorer la séance") {
                            if let workout = workouts.first(where: { $0.id == proposal.workoutId }) {
                                PlanningService.update(workout, to: .skipped, in: modelContext)
                            }
                            refreshProposals()
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("planning.proposal.skip")
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Séances manquées")
        } footer: {
            Text("Rien n’est déplacé sans votre confirmation.")
        }
    }

    private var conflictsSection: some View {
        Section("Chevauchements") {
            ForEach(Array(conflicts.enumerated()), id: \.offset) { _, conflict in
                Label(description(of: conflict), systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Text("Un chevauchement n’empêche rien : c’est une information.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var contentSection: some View {
        switch mode {
        case .day:
            daySection(for: anchor)
        case .week:
            ForEach(weekDays, id: \.self) { day in
                daySection(for: day)
            }
        case .month:
            monthSection
        }
    }

    private func daySection(for day: Date) -> some View {
        let items = workouts(on: day)
        let done = completedSessions(on: day)

        return Section {
            if items.isEmpty && done.isEmpty {
                Text("Rien de prévu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(items, id: \.id) { workout in
                workoutRow(workout)
            }
            ForEach(done, id: \.id) { session in
                HStack {
                    Label(session.sessionName.isEmpty ? "Séance" : session.sessionName, systemImage: "checkmark.seal")
                        .foregroundStyle(Theme.accent)
                    Spacer()
                    Text("Réalisée")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        } header: {
            Text(Self.dayHeader.string(from: day).capitalized)
        }
    }

    private var monthSection: some View {
        Section("Mois") {
            ForEach(monthWeeks, id: \.self) { weekStart in
                HStack(spacing: 4) {
                    ForEach(days(ofWeekStarting: weekStart), id: \.self) { day in
                        dayCell(day)
                    }
                }
                .padding(.vertical, 2)
            }
            Text("Touchez un jour pour l’ouvrir.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let count = workouts(on: day).count
        let doneCount = completedSessions(on: day).count
        let isCurrentMonth = calendar.isDate(day, equalTo: anchor, toGranularity: .month)

        return Button {
            anchor = day
            mode = .day
        } label: {
            VStack(spacing: 2) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.caption)
                    .foregroundStyle(isCurrentMonth ? .primary : .secondary)
                Circle()
                    .fill(doneCount > 0 ? Theme.accent : (count > 0 ? Color.orange : Color.clear))
                    .frame(width: 6, height: 6)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(calendar.isDateInToday(day) ? Theme.card : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(day: day, planned: count, done: doneCount))
    }

    private func workoutRow(_ workout: ScheduledWorkout) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.displayName.isEmpty ? "Séance" : workout.displayName)
                Text(Self.time.string(from: workout.plannedDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let originalDate = workout.originalDate {
                    Text("Reportée du \(Self.shortDate.string(from: originalDate))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(label(for: workout.state))
                .font(.caption.weight(.semibold))
                .foregroundStyle(color(for: workout.state))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(workout.displayName), \(Self.longDate.string(from: workout.plannedDate)), \(label(for: workout.state))")
        // Action accessible : le glisser-deposer n'est pas praticable avec
        // VoiceOver, un menu long-press oui.
        .accessibilityAction(named: "Déplacer") {
            newDate = workout.plannedDate
            workoutToMove = workout
        }
        .contextMenu {
            Button {
                newDate = workout.plannedDate
                workoutToMove = workout
            } label: {
                Label("Déplacer", systemImage: "calendar")
            }
            ForEach(Self.selectableStates, id: \.self) { state in
                Button {
                    PlanningService.update(workout, to: state, in: modelContext)
                } label: {
                    Label(label(for: state), systemImage: icon(for: state))
                }
            }
            Divider()
            Button(role: .destructive) {
                workout.deletedAt = .now
                workout.updatedAt = .now
                _ = PersistenceSupport.save(modelContext, action: "Retrait du planning")
            } label: {
                Label("Retirer du planning", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing) {
            Button {
                newDate = workout.plannedDate
                workoutToMove = workout
            } label: {
                Label("Déplacer", systemImage: "calendar")
            }
            .tint(.orange)
        }
    }

    private func moveSheet(_ workout: ScheduledWorkout) -> some View {
        NavigationStack {
            Form {
                DatePicker("Nouvelle date", selection: $newDate, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.graphical)
                    .accessibilityIdentifier("planning.move.date")
            }
            .navigationTitle(workout.displayName.isEmpty ? "Déplacer" : workout.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { workoutToMove = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Déplacer") {
                        PlanningService.move(workout, to: newDate, in: modelContext)
                        workoutToMove = nil
                        refreshProposals()
                    }
                    .accessibilityIdentifier("planning.move.confirm")
                }
            }
        }
    }

    // MARK: - Données

    private var activeWorkouts: [ScheduledWorkout] {
        workouts.filter { $0.deletedAt == nil }
    }

    private func workouts(on day: Date) -> [ScheduledWorkout] {
        activeWorkouts.filter { calendar.isDate($0.plannedDate, inSameDayAs: day) }
    }

    private func completedSessions(on day: Date) -> [CompletedSession] {
        completedSessions.filter { $0.deletedAt == nil && calendar.isDate($0.date, inSameDayAs: day) }
    }

    private var conflicts: [ScheduleConflict] {
        PlanningService.conflicts(in: modelContext, catalog: catalogStore.catalog, calendar: calendar)
            .filter { conflict in
                guard let first = activeWorkouts.first(where: { $0.id == conflict.first }) else { return false }
                return isInCurrentPeriod(first.plannedDate)
            }
    }

    private func refreshProposals() {
        proposals = PlanningService.rescheduleProposals(
            in: modelContext,
            catalog: catalogStore.catalog,
            calendar: calendar
        )
    }

    private func title(for workoutId: UUID) -> String {
        activeWorkouts.first { $0.id == workoutId }?.displayName ?? "Séance"
    }

    private func description(of conflict: ScheduleConflict) -> String {
        let first = title(for: conflict.first)
        let second = title(for: conflict.second)
        switch conflict.kind {
        case .sameDay:
            return "\(first) et \(second) le même jour."
        case .insufficientRecovery(let hours, let muscles):
            let names = muscles.map(FrenchLabels.muscle).joined(separator: ", ")
            return "\(first) et \(second) : \(hours) h d’écart sur \(names)."
        }
    }

    // MARK: - Période

    private func shift(by amount: Int) {
        let component: Calendar.Component = mode == .month ? .month : (mode == .week ? .weekOfYear : .day)
        anchor = calendar.date(byAdding: component, value: amount, to: anchor) ?? anchor
    }

    private func isInCurrentPeriod(_ date: Date) -> Bool {
        switch mode {
        case .day: return calendar.isDate(date, inSameDayAs: anchor)
        case .week: return calendar.isDate(date, equalTo: anchor, toGranularity: .weekOfYear)
        case .month: return calendar.isDate(date, equalTo: anchor, toGranularity: .month)
        }
    }

    private var periodTitle: String {
        switch mode {
        case .day: return Self.longDate.string(from: anchor).capitalized
        case .week:
            guard let first = weekDays.first, let last = weekDays.last else { return "" }
            return String(localized: "\(Self.shortDate.string(from: first)) – \(Self.shortDate.string(from: last))")
        case .month: return Self.month.string(from: anchor).capitalized
        }
    }

    private var weekDays: [Date] {
        days(ofWeekStarting: RecurrenceExpander.startOfWeek(for: anchor, calendar: calendar))
    }

    private func days(ofWeekStarting start: Date) -> [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var monthWeeks: [Date] {
        guard let interval = calendar.dateInterval(of: .month, for: anchor) else { return [] }
        var weeks: [Date] = []
        var cursor = RecurrenceExpander.startOfWeek(for: interval.start, calendar: calendar)
        while cursor < interval.end {
            weeks.append(cursor)
            guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: cursor) else { break }
            cursor = next
        }
        return weeks
    }

    private func accessibilityLabel(day: Date, planned: Int, done: Int) -> String {
        var parts = [Self.longDate.string(from: day)]
        if planned > 0 { parts.append("\(planned) séance(s) prévue(s)") }
        if done > 0 { parts.append("\(done) séance(s) réalisée(s)") }
        if planned == 0 && done == 0 { parts.append("rien de prévu") }
        return parts.joined(separator: ", ")
    }

    // MARK: - Libellés

    private static let selectableStates: [ScheduledWorkoutState] = [.planned, .started, .completed, .partial, .skipped, .postponed]

    private func label(for state: ScheduledWorkoutState) -> String {
        switch state {
        case .planned: return "Prévue"
        case .started: return "Commencée"
        case .completed: return "Terminée"
        case .partial: return "Partielle"
        case .skipped: return "Ignorée"
        case .postponed: return "Reportée"
        }
    }

    private func icon(for state: ScheduledWorkoutState) -> String {
        switch state {
        case .planned: return "calendar"
        case .started: return "play.circle"
        case .completed: return "checkmark.circle"
        case .partial: return "circle.lefthalf.filled"
        case .skipped: return "xmark.circle"
        case .postponed: return "arrow.uturn.right"
        }
    }

    private func color(for state: ScheduledWorkoutState) -> Color {
        switch state {
        case .completed: return Theme.accent
        case .skipped: return .secondary
        case .partial, .postponed: return .orange
        case .planned, .started: return .secondary
        }
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.setLocalizedDateFormatFromTemplate(format)
        return formatter
    }

    private static let dayHeader = formatter("EEEEdMMMM")
    private static let longDate = formatter("EEEEdMMMM")
    private static let shortDate = formatter("dMMM")
    private static let month = formatter("MMMMyyyy")
    private static let time = formatter("HHmm")
}
