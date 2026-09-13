import SwiftUI
import SwiftData
import MuscuEngine

/// Liste des recurrences hebdomadaires et de leurs rappels.
struct SchedulesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(CatalogStore.self) private var catalogStore

    @Query(sort: \PlanningSchedule.createdAt) private var schedules: [PlanningSchedule]
    @Query(sort: \Program.name) private var programs: [Program]

    @State private var editing: PlanningSchedule?

    private var activeSchedules: [PlanningSchedule] {
        schedules.filter { $0.deletedAt == nil }
    }

    var body: some View {
        List {
            Section {
                if activeSchedules.isEmpty {
                    Text("Aucune récurrence. Ajoutez-en une pour planifier une semaine type.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(activeSchedules, id: \.id) { schedule in
                    Button {
                        editing = schedule
                    } label: {
                        row(schedule)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: delete)
            } footer: {
                Text("Une récurrence remplit le planning à l’avance. Les séances déjà commencées ou terminées ne sont jamais réécrites.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Récurrences")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editing = create()
                } label: {
                    Label("Ajouter", systemImage: "plus")
                }
                .accessibilityIdentifier("schedules.add")
            }
        }
        .sheet(item: $editing) { schedule in
            ScheduleEditorView(schedule: schedule)
        }
    }

    private func row(_ schedule: PlanningSchedule) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(schedule.name.isEmpty ? "Récurrence" : schedule.name)
                Spacer()
                if !schedule.isEnabled {
                    Text("En pause")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Text(daysLabel(schedule))
                .font(.caption)
                .foregroundStyle(.secondary)
            if schedule.remindersEnabled {
                Label("Rappels actifs", systemImage: "bell")
                    .font(.caption2)
                    .foregroundStyle(Theme.accent)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func daysLabel(_ schedule: PlanningSchedule) -> String {
        let days = schedule.weekdays.sorted().map(Self.weekdayName)
        let time = String(format: "%02d:%02d", schedule.hour, schedule.minute)
        guard !days.isEmpty else { return "Aucun jour choisi" }
        return days.joined(separator: ", ") + " · " + time
    }

    static func weekdayName(_ weekday: Int) -> String {
        let symbols = Calendar.current.weekdaySymbols
        let index = max(1, min(7, weekday)) - 1
        return symbols[index].capitalized
    }

    private func create() -> PlanningSchedule {
        let schedule = PlanningSchedule(
            programId: programs.first(where: \.isActive)?.id ?? programs.first?.id,
            name: "Semaine type"
        )
        schedule.weekdays = [2, 4, 6]
        context_insert(schedule)
        return schedule
    }

    private func context_insert(_ schedule: PlanningSchedule) {
        modelContext.insert(schedule)
        _ = PersistenceSupport.save(modelContext, action: "Création d’une récurrence")
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let schedule = activeSchedules[index]
            schedule.deletedAt = .now
            schedule.updatedAt = .now
        }
        _ = PersistenceSupport.save(modelContext, action: "Suppression d’une récurrence")
    }
}

/// Edition d'une recurrence : jours, heure, bornes, pauses et rappels.
struct ScheduleEditorView: View {
    @Bindable var schedule: PlanningSchedule

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(CatalogStore.self) private var catalogStore

    @Query(sort: \Program.name) private var programs: [Program]
    @Query(sort: \PlaceProfile.name) private var places: [PlaceProfile]

    @State private var hasEndDate = false
    @State private var endDate = Date.now
    @State private var reminderDayOfEnabled = false
    @State private var dayOfTime = Date.now
    @State private var generationMessage: String?
    @State private var authorizationMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                identitySection
                daysSection
                remindersSection
                boundsSection
            }
            .navigationTitle(schedule.name.isEmpty ? "Récurrence" : schedule.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminé") { save() }
                        .accessibilityIdentifier("schedule.done")
                }
            }
            .onAppear(perform: load)
        }
    }

    private var identitySection: some View {
        Section {
            TextField("Nom", text: $schedule.name)
                .accessibilityIdentifier("schedule.name")

            Picker("Programme", selection: programSelection) {
                Text("Aucun").tag(UUID?.none)
                ForEach(programs.filter { $0.deletedAt == nil }, id: \.id) { program in
                    Text(program.name).tag(UUID?.some(program.id))
                }
            }
            .pickerStyle(.navigationLink)

            if !places.filter({ $0.deletedAt == nil }).isEmpty {
                Picker("Lieu", selection: placeSelection) {
                    Text("Non précisé").tag(UUID?.none)
                    ForEach(places.filter { $0.deletedAt == nil }, id: \.id) { place in
                        Text(place.name).tag(UUID?.some(place.id))
                    }
                }
                .pickerStyle(.navigationLink)
            }

            Toggle("Active", isOn: $schedule.isEnabled)
                .accessibilityIdentifier("schedule.enabled")

            // Le remplissage est l'action principale de cet ecran : il reste
            // atteignable sans faire defiler le formulaire.
            Button("Remplir le planning") { generate() }
                .accessibilityIdentifier("schedule.generate")

            if let generationMessage {
                Text(generationMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("schedule.generate.result")
            }
        } footer: {
            Text("Les séances déjà commencées, terminées ou déplacées à la main ne sont jamais réécrites.")
        }
    }

    private var daysSection: some View {
        Section {
            ForEach(1...7, id: \.self) { weekday in
                Toggle(SchedulesView.weekdayName(weekday), isOn: weekdayBinding(weekday))
                    .accessibilityIdentifier("schedule.day.\(weekday)")
            }
            DatePicker("Heure", selection: timeBinding, displayedComponents: [.hourAndMinute])
                .accessibilityIdentifier("schedule.time")
        } header: {
            Text("Jours")
        } footer: {
            Text("L’heure reste l’heure locale : un changement de fuseau ou d’heure d’été ne décale pas vos séances.")
        }
    }

    private var boundsSection: some View {
        Section {
            DatePicker("Début", selection: $schedule.startDate, displayedComponents: [.date])
            Toggle("Date de fin", isOn: $hasEndDate)
            if hasEndDate {
                DatePicker("Fin", selection: $endDate, in: schedule.startDate..., displayedComponents: [.date])
            }
            Stepper(
                "Semaines de pause : \(schedule.pausedWeekOffsets.count)",
                onIncrement: { addPauseWeek() },
                onDecrement: { removePauseWeek() }
            )
            if !schedule.pausedWeekOffsets.isEmpty {
                Text("Semaines en pause : " + schedule.pausedWeekOffsets.sorted().map { "\($0 + 1)" }.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Période")
        } footer: {
            Text("Une semaine de pause est sautée sans décaler les suivantes.")
        }
    }

    private var remindersSection: some View {
        Section {
            Toggle("Rappels", isOn: reminderToggle)
                .accessibilityIdentifier("schedule.reminders")

            if schedule.remindersEnabled {
                Stepper("Avant la séance : \(schedule.reminderLeadMinutes) min", value: $schedule.reminderLeadMinutes, in: 0...480, step: 15)
                Toggle("Rappel le matin même", isOn: $reminderDayOfEnabled)
                if reminderDayOfEnabled {
                    DatePicker("Heure du rappel", selection: $dayOfTime, displayedComponents: [.hourAndMinute])
                }
                Stepper(
                    schedule.reminderComebackAfterDays == 0
                        ? "Rappel de reprise : désactivé"
                        : "Rappel de reprise : après \(schedule.reminderComebackAfterDays) jours",
                    value: $schedule.reminderComebackAfterDays,
                    in: 0...30
                )
                Toggle("Son", isOn: $schedule.reminderSoundEnabled)
            }

            if let authorizationMessage {
                Text(authorizationMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("schedule.reminders.message")
            }
        } header: {
            Text("Rappels")
        } footer: {
            Text("Aucun rappel n’est programmé sans votre autorisation. Muscu fonctionne entièrement sans notifications.")
        }
    }

    // MARK: - Liaisons

    private var programSelection: Binding<UUID?> {
        Binding(get: { schedule.programId }, set: { schedule.programId = $0 })
    }

    private var placeSelection: Binding<UUID?> {
        Binding(get: { schedule.placeId }, set: { schedule.placeId = $0 })
    }

    private func weekdayBinding(_ weekday: Int) -> Binding<Bool> {
        Binding(
            get: { schedule.weekdays.contains(weekday) },
            set: { isOn in
                var days = schedule.weekdays
                if isOn { days.insert(weekday) } else { days.remove(weekday) }
                schedule.weekdays = days
            }
        )
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: schedule.hour, minute: schedule.minute, second: 0, of: .now) ?? .now
            },
            set: { newValue in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                schedule.hour = parts.hour ?? schedule.hour
                schedule.minute = parts.minute ?? schedule.minute
            }
        )
    }

    private var reminderToggle: Binding<Bool> {
        Binding(
            get: { schedule.remindersEnabled },
            set: { isOn in
                Task { await setReminders(isOn) }
            }
        )
    }

    // MARK: - Actions

    private func load() {
        hasEndDate = schedule.endDate != nil
        endDate = schedule.endDate ?? Date.now
        reminderDayOfEnabled = schedule.reminderDayOfHour != nil
        dayOfTime = Calendar.current.date(
            bySettingHour: schedule.reminderDayOfHour ?? 8,
            minute: schedule.reminderDayOfMinute ?? 0,
            second: 0,
            of: .now
        ) ?? .now
    }

    private func save() {
        schedule.endDate = hasEndDate ? endDate : nil
        if reminderDayOfEnabled {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: dayOfTime)
            schedule.reminderDayOfHour = parts.hour
            schedule.reminderDayOfMinute = parts.minute
        } else {
            schedule.reminderDayOfHour = nil
            schedule.reminderDayOfMinute = nil
        }
        schedule.updatedAt = .now
        _ = PersistenceSupport.save(modelContext, action: "Enregistrement de la récurrence")

        Task {
            await ReminderService.refresh(
                in: modelContext,
                scheduler: AppServices.notificationScheduler,
                catalog: catalogStore.catalog
            )
            dismiss()
        }
    }

    private func setReminders(_ isOn: Bool) async {
        let outcome: ReminderSyncOutcome
        if isOn {
            outcome = await ReminderService.enableReminders(
                for: schedule,
                in: modelContext,
                scheduler: AppServices.notificationScheduler,
                catalog: catalogStore.catalog
            )
        } else {
            outcome = await ReminderService.disableReminders(
                for: schedule,
                in: modelContext,
                scheduler: AppServices.notificationScheduler,
                catalog: catalogStore.catalog
            )
        }

        authorizationMessage = switch outcome.authorization {
        case .denied: "Les notifications sont refusées dans les réglages de l’appareil. Le planning reste utilisable."
        case .notDetermined: "Autorisation non accordée : aucun rappel n’est programmé."
        case .authorized: nil
        }
    }

    private func addPauseWeek() {
        var offsets = schedule.pausedWeekOffsets
        offsets.insert((offsets.max() ?? -1) + 1)
        schedule.pausedWeekOffsets = offsets
    }

    private func removePauseWeek() {
        var offsets = schedule.pausedWeekOffsets
        if let last = offsets.max() { offsets.remove(last) }
        schedule.pausedWeekOffsets = offsets
    }

    private func generate() {
        let program = programs.first { $0.id == schedule.programId }
        let result = PlanningService.applyRecurrence(schedule, program: program, in: modelContext)
        _ = PersistenceSupport.save(modelContext, action: "Remplissage du planning")
        generationMessage = "\(result.created) séance(s) ajoutée(s), \(result.removed) retirée(s)."
    }
}

/// Ajout d'une seance ponctuelle au planning, hors recurrence.
struct AddScheduledWorkoutView: View {
    let defaultDate: Date

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Program.name) private var programs: [Program]
    @Query(sort: \PlaceProfile.name) private var places: [PlaceProfile]

    @State private var date = Date.now
    @State private var selectedSessionId: UUID?
    @State private var placeId: UUID?
    @State private var name = ""

    private var sessions: [ProgramSession] {
        programs
            .filter { $0.deletedAt == nil }
            .flatMap(\.orderedSessions)
            .filter { $0.deletedAt == nil }
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    .accessibilityIdentifier("addWorkout.date")

                Picker("Séance du programme", selection: $selectedSessionId) {
                    Text("Aucune").tag(UUID?.none)
                    ForEach(sessions, id: \.id) { session in
                        Text("\(session.program?.name ?? "") · \(session.name)").tag(UUID?.some(session.id))
                    }
                }
                .pickerStyle(.navigationLink)
                .accessibilityIdentifier("addWorkout.session")

                TextField("Nom affiché", text: $name)
                    .accessibilityIdentifier("addWorkout.name")

                if !places.filter({ $0.deletedAt == nil }).isEmpty {
                    Picker("Lieu", selection: $placeId) {
                        Text("Non précisé").tag(UUID?.none)
                        ForEach(places.filter { $0.deletedAt == nil }, id: \.id) { place in
                            Text(place.name).tag(UUID?.some(place.id))
                        }
                    }
                    .pickerStyle(.navigationLink)
                }
            }
            .navigationTitle("Nouvelle séance prévue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter") { add() }
                        .accessibilityIdentifier("addWorkout.confirm")
                }
            }
            .onAppear {
                date = defaultDate
                placeId = PlaceStore.defaultPlace(in: modelContext)?.id
            }
        }
    }

    private func add() {
        let session = sessions.first { $0.id == selectedSessionId }
        let displayName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (session?.name ?? "Séance")
            : name
        let workout = ScheduledWorkout(
            plannedDate: date,
            programSessionId: session?.id,
            displayName: displayName,
            placeId: placeId
        )
        modelContext.insert(workout)
        _ = PersistenceSupport.save(modelContext, action: "Ajout au planning")
        dismiss()
    }
}
