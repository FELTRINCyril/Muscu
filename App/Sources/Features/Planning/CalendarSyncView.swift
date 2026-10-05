import SwiftUI
import SwiftData
import MuscuEngine

/// Échanges facultatifs avec l'application Calendrier.
///
/// L'écran fonctionne sans permission : il l'explique au lieu de se bloquer,
/// et n'en demande une qu'au moment où l'utilisateur exporte réellement.
struct CalendarSyncView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \ScheduledWorkout.plannedDate) private var workouts: [ScheduledWorkout]

    @State private var authorization: CalendarAuthorization = .notDetermined
    @State private var calendars: [CalendarDescriptor] = []
    @State private var selectedCalendarId: String?
    @State private var message: String?
    @State private var isWorking = false

    @State private var slotTitle = ""
    @State private var slotDate = Date.now

    private var upcoming: [ScheduledWorkout] {
        workouts.filter { $0.deletedAt == nil && $0.plannedDate >= .now && !$0.state.isSettled }
    }

    private var exported: Int {
        CalendarExportService.links(in: modelContext).count
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Séances à venir", value: "\(upcoming.count)")
                    LabeledContent("Déjà exportées", value: "\(exported)")
                } header: {
                    Text("État")
                } footer: {
                    Text("Muscu ne modifie et ne supprime que les événements qu’il a lui-même créés.")
                }

                if authorization == .authorized {
                    exportSection
                } else {
                    permissionSection
                }

                importSection

                if let message {
                    Section {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("calendar.message")
                    }
                }
            }
            .navigationTitle("Calendrier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
            .task { refreshAuthorization() }
        }
    }

    private var exportSection: some View {
        Section {
            Picker("Calendrier", selection: $selectedCalendarId) {
                Text("Choisir…").tag(String?.none)
                ForEach(calendars) { calendar in
                    Text(calendar.title).tag(String?.some(calendar.id))
                }
            }
            .pickerStyle(.navigationLink)
            .accessibilityIdentifier("calendar.picker")

            Button("Exporter les séances à venir") { export() }
                .disabled(selectedCalendarId == nil || upcoming.isEmpty || isWorking)
                .accessibilityIdentifier("calendar.export")

            Button("Retirer les événements créés par Muscu", role: .destructive) { remove() }
                .disabled(exported == 0 || isWorking)
                .accessibilityIdentifier("calendar.remove")
        } header: {
            Text("Export")
        }
    }

    private var permissionSection: some View {
        Section {
            Button("Autoriser l’accès au calendrier") {
                Task {
                    _ = await CalendarExportService.ensureAccess(AppServices.calendarStore)
                    refreshAuthorization()
                }
            }
            .accessibilityIdentifier("calendar.authorize")
            .disabled(authorization == .denied)

            if authorization == .denied {
                Text("L’accès est refusé dans les réglages de l’appareil. Le planning reste entièrement utilisable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Autorisation")
        } footer: {
            Text("L’accès au calendrier est facultatif. Muscu fonctionne sans.")
        }
    }

    private var importSection: some View {
        Section {
            TextField("Titre du créneau", text: $slotTitle)
                .accessibilityIdentifier("calendar.slot.title")
            DatePicker("Date", selection: $slotDate, displayedComponents: [.date, .hourAndMinute])
            Button("Ajouter au planning") {
                let workout = CalendarExportService.importSlot(
                    title: slotTitle,
                    date: slotDate,
                    programSessionId: nil,
                    in: modelContext
                )
                message = "« \(workout.displayName) » ajoutée au planning."
                slotTitle = ""
            }
            .disabled(slotTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityIdentifier("calendar.slot.add")
        } header: {
            Text("Importer un créneau")
        } footer: {
            Text("Muscu ne lit jamais votre calendrier entier : vous décrivez le créneau à réserver.")
        }
    }

    private func refreshAuthorization() {
        authorization = AppServices.calendarStore.authorizationStatus()
        calendars = authorization == .authorized ? AppServices.calendarStore.writableCalendars() : []
        if selectedCalendarId == nil { selectedCalendarId = calendars.first?.id }
    }

    private func export() {
        guard let selectedCalendarId else { return }
        isWorking = true
        Task {
            let outcome = await CalendarExportService.export(
                workouts: upcoming,
                to: selectedCalendarId,
                store: AppServices.calendarStore,
                in: modelContext
            )
            message = outcome.summary
            isWorking = false
        }
    }

    private func remove() {
        isWorking = true
        Task {
            let outcome = await CalendarExportService.remove(
                workouts: workouts.filter { $0.deletedAt == nil },
                store: AppServices.calendarStore,
                in: modelContext
            )
            message = outcome.summary
            isWorking = false
        }
    }
}
