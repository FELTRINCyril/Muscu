import SwiftUI
import SwiftData
import MuscuEngine

// Onglet Accueil : ecran d'accueil de l'app, pense comme un vrai tableau de
// bord fitness (pas juste une carte de lancement). De haut en bas :
// - en-tete (date du jour + salutation) ;
// - carte hero "Seance du jour", piece centrale, avec estimation de duree et
//   bouton de lancement/reprise ;
// - ligne de 3 statistiques compactes (seances/semaine, serie, tonnage 7j) ;
// - vue de la semaine (7 pastilles L->D, remplies quand une seance a ete
//   terminee ce jour-la) ;
// - derniers records (3 plus recents ExerciseRecord).
// La detection/reprise de seance interrompue (alerte au lancement) vient de
// l'onglet Accueil provisoire de la Task 18 : comportement inchange, portee
// ici dans HomeView plutot qu'au niveau racine.
struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(CatalogStore.self) private var catalogStore
    @Environment(\.massUnit) private var massUnit

    @Query(sort: \Program.name) private var programs: [Program]
    @Query(sort: \CompletedSession.date, order: .reverse) private var completedSessions: [CompletedSession]
    @Query(sort: \ExerciseRecord.updatedAt, order: .reverse) private var records: [ExerciseRecord]
    @Query private var activeWorkouts: [ActiveWorkout]

    // Selection de l'onglet racine, pour rediriger vers "Programmes" depuis
    // l'etat vide "Aucun programme actif".
    @Binding var selectedTab: Int

    @State private var restTimer = RestTimer()
    @State private var workoutState: WorkoutState?
    @State private var sessionToPrepare: ProgramSession?

    @State private var pendingActiveWorkout: ActiveWorkout?
    @State private var showingResumeAlert = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    header
                    heroCard
                    statsRow
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
        .sheet(item: $sessionToPrepare) { session in
            SessionPrepView(session: session) { readinessScaling in
                sessionToPrepare = nil
                // La preparation a pu modifier la prescription (progression
                // acceptee) : la seance est construite APRES sa fermeture,
                // pour partir des valeurs a jour.
                PresentationSync.afterCurrentPresentationDismissed {
                    startSession(session, readinessScaling: readinessScaling)
                }
            }
        }
        .fullScreenCover(item: $workoutState) { state in
            WorkoutRunnerView(state: state)
        }
    }

    // MARK: - En-tete

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Self.todayLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            Text(currentActiveWorkout != nil ? "Séance en cours" : "Prêt à t'entraîner ?")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static var todayLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.setLocalizedDateFormatFromTemplate("EEEE d MMMM")
        return formatter.string(from: .now)
    }

    // MARK: - Carte de lancement (hero)

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
                let session = nextSession(for: program)

                Text("Séance du jour")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .textCase(.uppercase)
                    .tracking(0.5)

                VStack(alignment: .leading, spacing: 4) {
                    Text(program.name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let session {
                        Text(session.name)
                            .font(.title.bold())
                            .foregroundStyle(.white)
                    }
                }

                if let session {
                    HStack(spacing: 6) {
                        Image(systemName: "list.bullet")
                            .foregroundStyle(.secondary)
                        Text("\(session.exercises.count) exercice\(session.exercises.count > 1 ? "s" : "")")
                            .foregroundStyle(.secondary)
                        Text("-")
                            .foregroundStyle(.secondary)
                        Image(systemName: "clock")
                            .foregroundStyle(.secondary)
                        Text("environ \(Self.estimatedMinutes(for: session)) min")
                            .foregroundStyle(.secondary)
                    }
                    .font(.footnote)
                }

                Button {
                    if currentActiveWorkout != nil {
                        resumeCurrentWorkout()
                    } else {
                        startSession(program: program)
                    }
                } label: {
                    Text(currentActiveWorkout != nil ? "Reprendre la séance" : "Lancer la séance")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .controlSize(.large)
                .disabled(session == nil)

                // La rotation propose la seance suivante, mais l'utilisateur
                // doit pouvoir en choisir une autre sans passer par
                // l'editeur de programme (jour deplace, salle differente...).
                if currentActiveWorkout == nil, program.sessions.count > 1 {
                    Menu {
                        ForEach(program.orderedSessions) { candidate in
                            Button {
                                sessionToPrepare = candidate
                            } label: {
                                Text(candidate.name)
                            }
                        }
                    } label: {
                        Label("Choisir une autre séance", systemImage: "arrow.triangle.swap")
                            .font(.footnote)
                    }
                    .accessibilityIdentifier("home.chooseSessionMenu")
                }
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
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(activeProgram != nil ? Theme.accent.opacity(0.35) : Color.clear, lineWidth: 1.5)
        )
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
            if let completedProgramId = completed.programId {
                return completedProgramId == program.id
            }
            return completed.programName == program.name
                && sessions.contains { $0.name == completed.sessionName }
        }) else {
            return sessions.first
        }

        guard let lastIndex = sessions.firstIndex(where: { session in
            if let completedSessionId = lastCompleted.programSessionId {
                return session.id == completedSessionId
            }
            return session.name == lastCompleted.sessionName
        }) else {
            return sessions.first
        }

        let nextIndex = (lastIndex + 1) % sessions.count
        return sessions[nextIndex]
    }

    // Duree estimee de la seance. Le calcul vit dans MuscuEngine
    // (SessionDuration) pour que l'accueil, l'editeur et le generateur
    // affichent tous la meme estimation.
    private static func estimatedMinutes(for session: ProgramSession) -> Int {
        SessionDuration.estimatedMinutes(for: WorkoutPlanBuilder.plan(for: session))
    }

    private func startSession(program: Program) {
        guard let session = nextSession(for: program) else { return }
        // Passage par l'ecran de preparation : check-in facultatif et
        // propositions de progression, que l'utilisateur peut ignorer.
        sessionToPrepare = session
    }

    private func startSession(_ session: ProgramSession, readinessScaling: WeekScaling? = nil) {
        // Une semaine de decharge ET un check-in prudent se CUMULENT : ils
        // repondent a deux raisons differentes d'alleger.
        let weekScaling = WeekScalingResolver.scaling(for: session, context: modelContext)
        let combined = readinessScaling.map { weekScaling.combined(with: $0) } ?? weekScaling

        workoutState = WorkoutState(
            programSession: session,
            modelContext: modelContext,
            catalogStore: catalogStore,
            restTimer: restTimer,
            weekScaling: combined
        )
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
    }

    // MARK: - Alerte de reprise (identique a la Task 18)

    private func checkForResumableWorkout() {
        guard let workout = WorkoutState.pendingActiveWorkout(modelContext: modelContext) else { return }
        pendingActiveWorkout = workout
        showingResumeAlert = true
    }

    // Declencher une NOUVELLE presentation (fullScreenCover) dans le meme
    // cycle de run loop que la fermeture de l'alerte systeme peut etre
    // silencieusement ignoree par UIKit : l'alerte est encore en cours de
    // transition de fermeture, et la nouvelle presentation n'a jamais lieu -
    // "Reprendre" ne fait alors rien, et si la presentation finit par
    // s'etablir dans un etat incoherent, "Fermer" sur le recap de fin de
    // seance ne ferme plus rien non plus (constate et corrige, cf.
    // .superpowers/sdd/progress.md). PresentationSync attend la fin REELLE
    // de la transition en cours (etat UIKit, pas un delai devine) avant de
    // presenter le runner.
    private func resumeWorkout() {
        guard let workout = pendingActiveWorkout,
              let state = WorkoutState.resume(
                from: workout,
                modelContext: modelContext,
                catalogStore: catalogStore,
                restTimer: restTimer
              ) else { return }
        PresentationSync.afterCurrentPresentationDismissed {
            workoutState = state
        }
    }

    private func abandonPendingWorkout() {
        guard let workout = pendingActiveWorkout else { return }
        modelContext.delete(workout)
        _ = PersistenceSupport.save(modelContext, action: "Activation du programme")
    }

    // MARK: - Statistiques

    private static var mondayFirstCalendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 2 // Lundi
        return calendar
    }

    private var sessionsThisWeek: [CompletedSession] {
        let calendar = Self.mondayFirstCalendar
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: .now) else { return [] }
        return completedSessions.filter { $0.date >= interval.start && $0.date < interval.end }
    }

    // Nombre de semaines consecutives (semaine courante incluse) comptant au
    // moins une CompletedSession, en remontant tant qu'aucun "trou" n'est
    // rencontre.
    private var weekStreak: Int {
        let calendar = Self.mondayFirstCalendar
        guard var weekStart = calendar.dateInterval(of: .weekOfYear, for: .now)?.start else { return 0 }
        if sessionsThisWeek.isEmpty,
           let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: weekStart) {
            weekStart = previous
        }
        var streak = 0
        while let interval = calendar.dateInterval(of: .weekOfYear, for: weekStart) {
            let hasSession = completedSessions.contains { $0.date >= interval.start && $0.date < interval.end }
            guard hasSession else { break }
            streak += 1
            guard let previousWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: weekStart) else { break }
            weekStart = previousWeek
        }
        return streak
    }

    // Tonnage (poids x reps) des 7 derniers jours, series d'echauffement
    // exclues (meme convention que le recap de fin de seance).
    private var tonnageLast7Days: Double {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
        let sets = completedSessions
            .filter { $0.date >= cutoff }
            .flatMap(\.sets)
            .filter { !$0.isWarmup }
        return sets.reduce(0) { $0 + $1.weight * Double($1.reps) }
    }

    // "850 kg" sous 1000 kg, "12,4 t" au-dela (plus lisible qu'un nombre a
    // 5 chiffres pour une stat compacte). En livres, la tonne n'a pas de
    // sens : la valeur reste en livres.
    private static func formattedTonnage(_ value: Double, unit: MassUnit) -> String {
        guard unit == .kilograms, value >= 1000 else {
            return "\(Int(unit.fromKilograms(value).rounded())) \(unit.symbol)"
        }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        let tons = value / 1000
        return "\(formatter.string(from: NSNumber(value: tons)) ?? String(format: "%.1f", tons)) t"
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            StatTile(
                systemImage: "figure.strengthtraining.traditional",
                value: "\(sessionsThisWeek.count)",
                label: "Séances\ncette semaine"
            )
            StatTile(
                systemImage: "flame.fill",
                value: "\(weekStreak)",
                label: weekStreak > 1 ? "Semaines\nde suite" : "Semaine\nde suite"
            )
            StatTile(
                systemImage: "scalemass.fill",
                value: Self.formattedTonnage(tonnageLast7Days, unit: massUnit),
                label: "Tonnage\n7 jours"
            )
        }
    }

    // MARK: - Vue de la semaine

    private var weekDays: [Date] {
        let calendar = Self.mondayFirstCalendar
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: .now) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
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

            VStack(spacing: 10) {
                ForEach(recentRecords) { record in
                    HStack(spacing: 12) {
                        Image(systemName: "medal.fill")
                            .foregroundStyle(Theme.accent)
                            .font(.title3)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.displayName)
                                .foregroundStyle(.primary)
                            Text(Self.relativeDate(record.updatedAt))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(recordLabel(for: record))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func recordLabel(for record: ExerciseRecord) -> String {
        var values: [String] = []
        if let oneRepMax = record.oneRepMax {
            values.append("1RM \(WeightFormatter.string(kilograms: oneRepMax, unit: massUnit))")
        }
        if let maxReps = record.maxReps { values.append("Max \(maxReps) reps") }
        return values.joined(separator: " · ")
    }

    // RelativeDateTimeFormatter arrondit les ecarts de quelques secondes de
    // facon ambigue ("dans 0 seconde" pour un record tout juste enregistre) :
    // en dessous d'une minute, on affiche explicitement "a l'instant".
    private static func relativeDate(_ date: Date) -> String {
        guard abs(date.timeIntervalSinceNow) >= 60 else { return "À l'instant" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}

private struct StatTile: View {
    let systemImage: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.subheadline)
                .foregroundStyle(Theme.accent)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
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
