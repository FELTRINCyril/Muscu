import SwiftUI
import SwiftData
import MuscuEngine

// Calendrier d'un plan : semaines, blocs, seances datees et leur etat.
//
// Deplacer ou marquer une seance ne touche JAMAIS l'historique : seul le
// planning change.
struct TrainingPlanView: View {
    @Bindable var plan: TrainingPlan

    @Environment(\.modelContext) private var modelContext

    @State private var workoutToMove: ScheduledWorkout?
    @State private var newDate = Date.now

    var body: some View {
        List {
            Section {
                LabeledContent("Statut", value: statusLabel)
                LabeledContent("Semaines", value: "\(plan.allWeeks.count)")
                LabeledContent("Séances prévues", value: "\(plan.allWeeks.reduce(0) { $0 + $1.scheduledWorkouts.count })")
            } footer: {
                if !plan.notes.isEmpty {
                    Text(plan.notes)
                }
            }

            ForEach(plan.allWeeks, id: \.id) { week in
                weekSection(week)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(plan.name.isEmpty ? "Plan" : plan.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $workoutToMove) { workout in
            moveSheet(workout)
        }
    }

    private func weekSection(_ week: TrainingWeek) -> some View {
        Section {
            ForEach(week.orderedWorkouts, id: \.id) { workout in
                workoutRow(workout)
            }
        } header: {
            HStack {
                Text("Semaine \(week.weekNumber)")
                if week.isDeload {
                    Text("Décharge")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.accent.opacity(0.2))
                        .foregroundStyle(Theme.accent)
                        .clipShape(Capsule())
                }
                Spacer()
                Text(blockLabel(week))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text(multiplierLabel(week))
                .font(.caption)
        }
    }

    private func workoutRow(_ workout: ScheduledWorkout) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.displayName.isEmpty ? "Séance" : workout.displayName)
                Text(Self.dateFormatter.string(from: workout.plannedDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(stateLabel(workout.state))
                .font(.caption.weight(.semibold))
                .foregroundStyle(stateColor(workout.state))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(workout.displayName), \(Self.dateFormatter.string(from: workout.plannedDate)), \(stateLabel(workout.state))")
        .contextMenu {
            Button {
                newDate = workout.plannedDate
                workoutToMove = workout
            } label: {
                Label("Déplacer", systemImage: "calendar")
            }
            ForEach(Self.selectableStates, id: \.self) { state in
                Button {
                    update(workout, to: state)
                } label: {
                    Label(stateLabel(state), systemImage: icon(for: state))
                }
            }
        }
    }

    private func moveSheet(_ workout: ScheduledWorkout) -> some View {
        NavigationStack {
            Form {
                DatePicker(
                    "Nouvelle date",
                    selection: $newDate,
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)
            }
            .navigationTitle(workout.displayName.isEmpty ? "Déplacer" : workout.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { workoutToMove = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Déplacer") {
                        move(workout, to: newDate)
                        workoutToMove = nil
                    }
                }
            }
        }
    }

    // MARK: - Actions

    /// Deplacer une seance ne casse pas la semaine : la seance reste
    /// rattachee a sa semaine, seule sa date change.
    private func move(_ workout: ScheduledWorkout, to date: Date) {
        workout.plannedDate = date
        workout.state = workout.state == .planned ? .postponed : workout.state
        workout.updatedAt = .now
        plan.updatedAt = .now
        _ = PersistenceSupport.save(modelContext, action: "Déplacement de la séance")
    }

    private func update(_ workout: ScheduledWorkout, to state: ScheduledWorkoutState) {
        workout.state = state
        workout.updatedAt = .now
        plan.updatedAt = .now
        _ = PersistenceSupport.save(modelContext, action: "Mise à jour du planning")
    }

    // MARK: - Libellés

    private static let selectableStates: [ScheduledWorkoutState] = [.planned, .completed, .partial, .skipped, .postponed]

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEEE d MMMM"
        return formatter
    }()

    private var statusLabel: String {
        switch plan.status {
        case .draft: return "Brouillon"
        case .active: return "En cours"
        case .completed: return "Terminé"
        case .archived: return "Archivé"
        }
    }

    private func blockLabel(_ week: TrainingWeek) -> String {
        week.block?.kind.displayName ?? ""
    }

    private func multiplierLabel(_ week: TrainingWeek) -> String {
        let volume = Int((week.volumeMultiplier * 100).rounded())
        let intensity = Int((week.intensityMultiplier * 100).rounded())
        return "Volume \(volume) % · intensité \(intensity) % de la prescription de base."
    }

    private func stateLabel(_ state: ScheduledWorkoutState) -> String {
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

    private func stateColor(_ state: ScheduledWorkoutState) -> Color {
        switch state {
        case .completed: return Theme.accent
        case .skipped: return .secondary
        case .partial, .postponed: return .orange
        case .planned, .started: return .secondary
        }
    }
}
