import SwiftUI
import SwiftData

// Onglet Accueil : tableau de bord d'entree dans l'app. Trois cartes :
// - lancement rapide (prochaine seance du programme actif, ou reprise d'une
//   seance en cours) ;
// - vue de la semaine (7 pastilles L->D, remplies quand une seance a ete
//   terminee ce jour-la) ;
// - derniers records (3 plus recents ExerciseRecord).
// La detection/reprise de seance interrompue (alerte au lancement) vient de
// l'onglet Accueil provisoire de la Task 18 : comportement inchange, portee
// ici dans HomeView plutot qu'au niveau racine.
struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(CatalogStore.self) private var catalogStore

    @Query(sort: \Program.name) private var programs: [Program]
    @Query(sort: \CompletedSession.date, order: .reverse) private var completedSessions: [CompletedSession]
    @Query(sort: \ExerciseRecord.updatedAt, order: .reverse) private var records: [ExerciseRecord]
    @Query private var activeWorkouts: [ActiveWorkout]

    // Selection de l'onglet racine, pour rediriger vers "Programmes" depuis
    // l'etat vide "Aucun programme actif".
    @Binding var selectedTab: Int

    @State private var restTimer = RestTimer()
    @State private var workoutState: WorkoutState?
    @State private var showingRunner = false

    @State private var pendingActiveWorkout: ActiveWorkout?
    @State private var showingResumeAlert = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    heroCard
                    weekCard
                    if !recentRecords.isEmpty {
                        recordsCard
                    }
                }
                .padding()
            }
        }
        .task {
            checkForResumableWorkout()
        }
        .alert("Reprendre la séance en cours ?", isPresented: $showingResumeAlert) {
            Button("Reprendre") { resumeWorkout() }
            Button("Abandonner", role: .destructive) { abandonPendingWorkout() }
            Button("Annuler", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showingRunner) {
            if let workoutState {
                WorkoutRunnerView(state: workoutState)
            }
        }
    }

    // MARK: - Carte de lancement

    private var activeProgram: Program? {
        programs.first { $0.isActive }
    }

    private var currentActiveWorkout: ActiveWorkout? {
        activeWorkouts.first
    }

    @ViewBuilder
    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let program = activeProgram {
                VStack(alignment: .leading, spacing: 4) {
                    Text(program.name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let session = nextSession(for: program) {
                        Text(session.name)
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                    }
                }

                if currentActiveWorkout != nil {
                    Text("Séance en cours")
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                }

                Button {
                    if currentActiveWorkout != nil {
                        resumeCurrentWorkout()
                    } else {
                        startSession(program: program)
                    }
                } label: {
                    Text(currentActiveWorkout != nil ? "Reprendre la séance" : "Lancer la séance")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .controlSize(.large)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Aucun programme actif")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                    Text("Activez ou créez un programme pour lancer une séance.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Button {
                    selectedTab = 1
                } label: {
                    Text("Créer un programme")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .controlSize(.large)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // Prochaine seance : celle qui suit la derniere CompletedSession du
    // programme actif (modulo, retour au debut apres la derniere). Sans
    // historique correspondant, on propose la premiere seance du programme.
    // Fonction statique/pure (pas de dependance a l'instance) pour rester
    // testable independamment du @Query des CompletedSession affichees.
    private func nextSession(for program: Program) -> ProgramSession? {
        Self.nextSession(for: program, completedSessions: completedSessions)
    }

    static func nextSession(for program: Program, completedSessions: [CompletedSession]) -> ProgramSession? {
        let sessions = program.sessions.sorted { $0.orderIndex < $1.orderIndex }
        guard !sessions.isEmpty else { return nil }

        guard let lastCompleted = completedSessions.first(where: { completed in
            completed.programName == program.name
                && sessions.contains { $0.name == completed.sessionName }
        }) else {
            return sessions.first
        }

        guard let lastIndex = sessions.firstIndex(where: { $0.name == lastCompleted.sessionName }) else {
            return sessions.first
        }

        let nextIndex = (lastIndex + 1) % sessions.count
        return sessions[nextIndex]
    }

    private func startSession(program: Program) {
        guard let session = nextSession(for: program) else { return }
        workoutState = WorkoutState(
            programSession: session,
            modelContext: modelContext,
            catalogStore: catalogStore,
            restTimer: restTimer
        )
        showingRunner = true
    }

    private func resumeCurrentWorkout() {
        guard let workout = currentActiveWorkout,
              let state = WorkoutState.resume(
                from: workout,
                modelContext: modelContext,
                catalogStore: catalogStore,
                restTimer: restTimer
              ) else { return }
        workoutState = state
        showingRunner = true
    }

    // MARK: - Alerte de reprise (identique a la Task 18)

    private func checkForResumableWorkout() {
        guard let workout = WorkoutState.pendingActiveWorkout(modelContext: modelContext) else { return }
        pendingActiveWorkout = workout
        showingResumeAlert = true
    }

    private func resumeWorkout() {
        guard let workout = pendingActiveWorkout,
              let state = WorkoutState.resume(
                from: workout,
                modelContext: modelContext,
                catalogStore: catalogStore,
                restTimer: restTimer
              ) else { return }
        workoutState = state
        showingRunner = true
    }

    private func abandonPendingWorkout() {
        guard let workout = pendingActiveWorkout else { return }
        modelContext.delete(workout)
        try? modelContext.save()
    }

    // MARK: - Vue de la semaine

    private static var mondayFirstCalendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 2 // Lundi
        return calendar
    }

    private var weekDays: [Date] {
        let calendar = Self.mondayFirstCalendar
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: .now) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
    }

    private var sessionsThisWeek: [CompletedSession] {
        let calendar = Self.mondayFirstCalendar
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: .now) else { return [] }
        return completedSessions.filter { $0.date >= interval.start && $0.date < interval.end }
    }

    private func hasSession(on day: Date) -> Bool {
        let calendar = Self.mondayFirstCalendar
        return completedSessions.contains { calendar.isDate($0.date, inSameDayAs: day) }
    }

    private var weekCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cette semaine")
                .font(.headline)
                .foregroundStyle(.white)

            HStack(spacing: 8) {
                ForEach(weekDays, id: \.self) { day in
                    DayPill(
                        letter: Self.dayLetter(for: day),
                        isFilled: hasSession(on: day),
                        isToday: Calendar.current.isDateInToday(day)
                    )
                }
            }

            Text("\(sessionsThisWeek.count) séance\(sessionsThisWeek.count > 1 ? "s" : "") cette semaine")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private static let letters = ["L", "M", "M", "J", "V", "S", "D"]

    private static func dayLetter(for date: Date) -> String {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let index = calendar.component(.weekday, from: date)
        // weekday standard (1 = dimanche ... 7 = samedi) -> index 0 = lundi.
        let mondayIndex = (index + 5) % 7
        return letters[mondayIndex]
    }

    // MARK: - Derniers records

    private var recentRecords: [ExerciseRecord] {
        Array(records.prefix(3))
    }

    private var recordsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Derniers records")
                .font(.headline)
                .foregroundStyle(.white)

            ForEach(recentRecords) { record in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.displayName)
                            .foregroundStyle(.primary)
                        Text(Self.relativeDate(record.updatedAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(recordLabel(for: record))
                        .font(.subheadline)
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func recordLabel(for record: ExerciseRecord) -> String {
        if let oneRepMax = record.oneRepMax {
            return "1RM \(WorkoutState.formatWeight(oneRepMax)) kg"
        }
        if let maxReps = record.maxReps {
            return "Max \(maxReps) reps"
        }
        return ""
    }

    // RelativeDateTimeFormatter arrondit les ecarts de quelques secondes de
    // facon ambigue ("dans 0 seconde" pour un record tout juste enregistre) :
    // en dessous d'une minute, on affiche explicitement "à l'instant".
    private static func relativeDate(_ date: Date) -> String {
        guard abs(date.timeIntervalSinceNow) >= 60 else { return "À l'instant" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}

private struct DayPill: View {
    let letter: String
    let isFilled: Bool
    let isToday: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isFilled ? Theme.accent : Color.clear)
            Circle()
                .strokeBorder(isFilled ? Theme.accent : Color.secondary, lineWidth: isToday ? 3 : 1)
            Text(letter)
                .font(.caption.bold())
                .foregroundStyle(isFilled ? .black : .secondary)
        }
        .frame(width: 32, height: 32)
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    HomeView(selectedTab: .constant(0))
        .environment(CatalogStore())
        .modelContainer(for: Program.self, inMemory: true)
        .preferredColorScheme(.dark)
}
