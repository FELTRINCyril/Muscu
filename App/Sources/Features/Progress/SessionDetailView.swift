import SwiftUI
import SwiftData
import MuscuEngine

// Detail d'une seance terminee : lecture, correction explicite (mode
// edition puis confirmation), « Refaire », partage. Les series
// d'echauffement sont marquees et attenuees.
struct SessionDetailView: View {
    let session: CompletedSession

    @Environment(\.modelContext) private var modelContext
    @Environment(CatalogStore.self) private var catalogStore
    @Environment(\.massUnit) private var massUnit

    @Query private var activeWorkouts: [ActiveWorkout]
    @Query private var personalBests: [PersonalBest]

    /// Brouillon de correction. `nil` = lecture seule.
    @State private var draft: PastSessionEditor.Draft?
    @State private var pendingRecordChanges: [PastSessionEditor.RecordChange] = []
    @State private var showingSaveConfirm = false
    @State private var showingDiscardConfirm = false
    @State private var showingAddExercise = false
    @State private var editMessage: String?

    @State private var showingShare = false
    @State private var showingActiveWorkoutAlert = false
    @State private var restTimer = RestTimer()
    @State private var workoutState: WorkoutState?

    var body: some View {
        Group {
            if draft != nil {
                editList
            } else {
                readList
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(session.sessionName.isEmpty ? "Séance" : session.sessionName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(draft != nil)
        .toolbar { toolbar }
        .confirmationDialog(
            "Enregistrer les corrections ?",
            isPresented: $showingSaveConfirm,
            titleVisibility: .visible
        ) {
            Button("Enregistrer") { save() }
                .accessibilityIdentifier("history.edit.confirmSave")
            Button("Continuer la correction", role: .cancel) {}
        } message: {
            Text(saveConfirmationMessage)
        }
        .confirmationDialog(
            "Abandonner les corrections ?",
            isPresented: $showingDiscardConfirm,
            titleVisibility: .visible
        ) {
            Button("Abandonner", role: .destructive) {
                draft = nil
                editMessage = nil
            }
            Button("Continuer la correction", role: .cancel) {}
        }
        .alert("Une séance est déjà en cours", isPresented: $showingActiveWorkoutAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Terminez ou abandonnez la séance en cours avant d’en refaire une.")
        }
        .sheet(isPresented: $showingAddExercise) {
            ExercisePickerView { exerciseId, displayName in
                addExercise(exerciseId: exerciseId, displayName: displayName)
            }
        }
        .sheet(isPresented: $showingShare) {
            SessionShareSheet(summary: SessionShareSummary.make(for: session, records: personalBests, unit: massUnit))
        }
        .fullScreenCover(item: $workoutState) { state in
            WorkoutRunnerView(state: state)
        }
    }

    // MARK: - Barre d'outils

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if draft != nil {
            ToolbarItem(placement: .cancellationAction) {
                Button("Annuler") { cancelEditing() }
                    .accessibilityIdentifier("history.edit.cancel")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Enregistrer") { requestSave() }
                    .accessibilityIdentifier("history.edit.save")
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        draft = PastSessionEditor.draft(for: session)
                        editMessage = nil
                    } label: {
                        Label("Modifier", systemImage: "pencil")
                    }
                    .accessibilityIdentifier("history.edit")
                    Button {
                        replay(.withTargets)
                    } label: {
                        Label("Refaire", systemImage: "arrow.clockwise")
                    }
                    .accessibilityIdentifier("history.replay")
                    Button {
                        replay(.empty)
                    } label: {
                        Label("Refaire à vide", systemImage: "arrow.clockwise.circle")
                    }
                    .accessibilityIdentifier("history.replayEmpty")
                    Button {
                        showingShare = true
                    } label: {
                        Label("Partager", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("history.share")
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .accessibilityLabel(Text("Actions"))
                }
                .accessibilityIdentifier("history.actions")
            }
        }
    }

    // MARK: - Lecture

    private var readList: some View {
        List {
            Section {
                LabeledContent("Horaires", value: intervalLabel)
                LabeledContent("Durée", value: SessionShareSummary.durationLabel(session.durationSeconds))
                if let breakdown = SessionReplayBuilder.timeBreakdown(for: session) {
                    SessionTimeBreakdownRow(breakdown: breakdown)
                }
                if let rating = session.effortRating {
                    Text(SessionEffortPresentation.summary(for: rating))
                        .foregroundStyle(SessionEffortPresentation.color(for: rating))
                        .accessibilityIdentifier("history.effort")
                }
                if session.hasCardio {
                    SessionCardioView(session: session)
                }
                if let editedAt = session.editedAt {
                    Text("Corrigée le \(editedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("history.editedAt")
                }
            }

            if !sessionRecords.isEmpty {
                Section("Records de la séance") {
                    ForEach(sessionRecords) { best in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(best.displayName)
                                Text(best.kind.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(best.formattedValue)
                                .foregroundStyle(Theme.accent)
                        }
                        .font(.subheadline)
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            ForEach(groupedSets, id: \.orderIndex) { group in
                Section {
                    ForEach(group.sets) { set in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(CompletedSetPresentation.label(for: set, inGroup: group.isGrouped))
                                Spacer()
                                Text(CompletedSetPresentation.performance(for: set, unit: massUnit))
                            }
                            if let note = CompletedSetPresentation.substitutionNote(for: set) {
                                Text(note)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            // Repos reellement pris : discret, absent quand
                            // il n'a pas ete mesure.
                            if let rest = CompletedSetPresentation.restNote(for: set) {
                                Text(rest)
                                    .font(.caption2)
                                    .monospacedDigit()
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .font(.subheadline)
                        .foregroundStyle(set.role == .warmup ? .secondary : .primary)
                        .padding(.leading, set.subSetIndex > 0 ? 16 : 0)
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    HStack {
                        Text(group.displayName)
                        if let badge = group.formatBadge {
                            Text(badge)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.accent.opacity(0.2))
                                .foregroundStyle(Theme.accent)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
    }

    private var intervalLabel: String {
        let (start, end) = PastSessionEditor.interval(of: session)
        let day = start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(WeightFormatter.displayLocale))
        let from = start.formatted(date: .omitted, time: .shortened)
        let to = end.formatted(date: .omitted, time: .shortened)
        return "\(day) · \(from) – \(to)"
    }

    private var sessionRecords: [PersonalBest] {
        personalBests
            .filter { $0.deletedAt == nil && $0.sourceSessionId == session.id }
            .sorted { ($0.displayName, $0.kindRaw) < ($1.displayName, $1.kindRaw) }
    }

    private struct ExerciseGroup {
        let orderIndex: Int
        let displayName: String
        let sets: [CompletedSet]
        /// L'exercice faisait partie d'un superset, triset ou circuit :
        /// les series se lisent alors par TOUR, pas par numero de serie.
        let isGrouped: Bool
        /// Format affiche a cote du nom quand ce n'est pas du classique.
        let formatBadge: String?
    }

    private var groupedSets: [ExerciseGroup] {
        let grouped = Dictionary(grouping: session.sets, by: \.orderIndex)
        return grouped.keys.sorted().compactMap { orderIndex in
            guard let sets = grouped[orderIndex], let first = sets.first else { return nil }
            let format = first.format
            return ExerciseGroup(
                orderIndex: orderIndex,
                displayName: first.displayName,
                sets: sets.sorted { ($0.roundIndex, $0.setIndex, $0.subSetIndex) < ($1.roundIndex, $1.setIndex, $1.subSetIndex) },
                isGrouped: first.groupId != nil,
                formatBadge: format == .classic ? nil : format.displayName
            )
        }
    }

    // MARK: - Correction

    private var editList: some View {
        List {
            if let editMessage {
                Section {
                    Label(editMessage, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("history.edit.message")
                }
            }

            Section {
                DatePicker("Début", selection: draftBinding(\.start))
                    .accessibilityIdentifier("history.edit.start")
                DatePicker("Fin", selection: draftBinding(\.end))
                    .accessibilityIdentifier("history.edit.end")
            } header: {
                Text("Horaires")
            }

            Section {
                EffortRatingView(rating: draftBinding(\.effortRating))
                    .listRowInsets(EdgeInsets())
            }

            ForEach(draft?.exercises ?? []) { exercise in
                Section {
                    ForEach(exercise.sets) { set in
                        SetEditRow(
                            label: setLabel(set, in: exercise),
                            measure: exercise.measure,
                            set: setBinding(exerciseID: exercise.id, setID: set.id),
                            unit: massUnit
                        )
                    }
                    .onDelete { offsets in
                        removeSets(at: offsets, from: exercise.id)
                    }
                    Button {
                        addSet(to: exercise.id)
                    } label: {
                        Label("Ajouter une série", systemImage: "plus")
                            .font(.subheadline)
                    }
                    .accessibilityIdentifier("history.edit.addSet")
                } header: {
                    HStack {
                        Text(exercise.displayName)
                        Spacer()
                        Button(role: .destructive) {
                            removeExercise(exercise.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel(Text("Retirer l’exercice"))
                        .accessibilityIdentifier("history.edit.removeExercise")
                    }
                }
            }

            Section {
                Button {
                    showingAddExercise = true
                } label: {
                    Label("Ajouter un exercice", systemImage: "plus.circle")
                }
                .accessibilityIdentifier("history.edit.addExercise")
            } footer: {
                Text("Une série ajoutée après coup n’a pas de repos mesuré. Les records issus de cette séance seront recalculés à l’enregistrement.")
            }
        }
    }

    private func setLabel(_ set: PastSessionEditor.SetDraft, in exercise: PastSessionEditor.ExerciseDraft) -> String {
        switch set.role {
        case .warmup: return String(localized: "Échauffement")
        case .approach: return String(localized: "Approche")
        case .backoff: return String(localized: "Back-off")
        case .working:
            var label = exercise.isGrouped
                ? String(localized: "Tour \(set.roundIndex + 1)")
                : String(localized: "Série \(set.setIndex + 1)")
            if set.subSetIndex > 0 { label += " · \(set.subSetIndex)" }
            return label
        }
    }

    private func draftBinding<Value>(_ keyPath: WritableKeyPath<PastSessionEditor.Draft, Value>) -> Binding<Value> {
        Binding(
            get: { draft?[keyPath: keyPath] ?? PastSessionEditor.draft(for: session)[keyPath: keyPath] },
            set: { newValue in
                draft?[keyPath: keyPath] = newValue
                editMessage = nil
            }
        )
    }

    private func setBinding(exerciseID: UUID, setID: UUID) -> Binding<PastSessionEditor.SetDraft> {
        Binding(
            get: {
                draft?.exercises.first { $0.id == exerciseID }?.sets.first { $0.id == setID }
                    ?? PastSessionEditor.SetDraft(
                        id: setID, existingSetId: nil, role: .working, weight: 0, reps: 0,
                        durationSeconds: nil, distanceMeters: nil, roundIndex: 0, setIndex: 0, subSetIndex: 0
                    )
            },
            set: { newValue in
                guard let exerciseIndex = draft?.exercises.firstIndex(where: { $0.id == exerciseID }),
                      let setIndex = draft?.exercises[exerciseIndex].sets.firstIndex(where: { $0.id == setID }) else { return }
                draft?.exercises[exerciseIndex].sets[setIndex] = newValue
                editMessage = nil
            }
        )
    }

    private func addSet(to exerciseID: UUID) {
        guard let index = draft?.exercises.firstIndex(where: { $0.id == exerciseID }),
              let exercise = draft?.exercises[index] else { return }
        draft?.exercises[index].sets.append(PastSessionEditor.newSet(for: exercise))
    }

    private func removeSets(at offsets: IndexSet, from exerciseID: UUID) {
        guard let index = draft?.exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
        draft?.exercises[index].sets.remove(atOffsets: offsets)
        if draft?.exercises[index].sets.isEmpty == true {
            draft?.exercises.remove(at: index)
        }
    }

    private func removeExercise(_ exerciseID: UUID) {
        draft?.exercises.removeAll { $0.id == exerciseID }
    }

    private func addExercise(exerciseId: String, displayName: String) {
        let loadKind: LoadKind
        if let catalogExercise = catalogStore.exercise(id: exerciseId) {
            loadKind = ExerciseClassification.loadKind(for: catalogExercise)
        } else if let custom = ((try? modelContext.fetch(FetchDescriptor<CustomExercise>())) ?? [])
            .first(where: { $0.id.uuidString == exerciseId }) {
            loadKind = custom.defaultLoadKind
        } else {
            loadKind = .unknown
        }
        draft?.exercises.append(PastSessionEditor.newExercise(
            exerciseId: exerciseId,
            displayName: displayName,
            loadKind: loadKind
        ))
    }

    private func cancelEditing() {
        guard let draft, PastSessionEditor.hasChanges(draft, comparedTo: session) else {
            self.draft = nil
            editMessage = nil
            return
        }
        showingDiscardConfirm = true
    }

    private func requestSave() {
        guard let draft else { return }
        if let issue = PastSessionEditor.issue(in: draft) {
            editMessage = issue.message
            return
        }
        guard PastSessionEditor.hasChanges(draft, comparedTo: session) else {
            self.draft = nil
            return
        }
        pendingRecordChanges = PastSessionEditor.recordChanges(for: session, draft: draft, in: modelContext)
        showingSaveConfirm = true
    }

    private var saveConfirmationMessage: String {
        var lines = [String(localized: "La séance sera marquée comme corrigée et synchronisée de nouveau.")]
        for change in pendingRecordChanges {
            let old = change.oldValue ?? "—"
            let new = change.newValue ?? String(localized: "supprimé")
            lines.append("\(change.exerciseName) · \(change.kindLabel) : \(old) → \(new)")
        }
        return lines.joined(separator: "\n")
    }

    private func save() {
        guard let draft else { return }
        guard PastSessionEditor.apply(draft, to: session, recordChanges: pendingRecordChanges, in: modelContext) else {
            editMessage = String(localized: "L’enregistrement a échoué : rien n’a été modifié.")
            return
        }
        self.draft = nil
        pendingRecordChanges = []
        editMessage = nil
        // Widgets et Sante decrivent la seance : ils suivent la correction.
        WidgetSnapshotService.refresh(in: modelContext, catalogStore: catalogStore)
        Task {
            await HealthSyncService.synchronize(in: modelContext, store: AppServices.healthStore)
        }
    }

    // MARK: - Refaire

    private func replay(_ mode: SessionReplay.Mode) {
        // Une seule seance active a la fois.
        guard activeWorkouts.isEmpty else {
            showingActiveWorkoutAlert = true
            return
        }
        workoutState = WorkoutState.replaying(
            session,
            mode: mode,
            modelContext: modelContext,
            catalogStore: catalogStore,
            restTimer: restTimer
        )
    }
}

/// Temps actif et temps de repos, avec la limite de la mesure dite.
struct SessionTimeBreakdownRow: View {
    let breakdown: SessionTimeBreakdown

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                LabeledContent("Actif", value: MeasureFormatter.clock(seconds: breakdown.activeSeconds))
                Spacer(minLength: 16)
                LabeledContent("Repos", value: MeasureFormatter.clock(seconds: breakdown.restSeconds))
            }
            GeometryReader { geometry in
                let total = max(1, breakdown.totalSeconds)
                let activeWidth = geometry.size.width * CGFloat(breakdown.activeSeconds) / CGFloat(total)
                HStack(spacing: 0) {
                    Rectangle().fill(Theme.accent).frame(width: activeWidth)
                    Rectangle().fill(Color.white.opacity(0.15))
                }
                .clipShape(Capsule())
            }
            .frame(height: 6)
            .accessibilityHidden(true)
            Text("Le repos va d’une validation à la suivante : il inclut l’exécution des séries en répétitions.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("session.timeBreakdown")
    }
}

/// Une serie en cours de correction : charge et repetitions, ou duree et
/// distance selon la mesure de l'exercice.
private struct SetEditRow: View {
    let label: String
    let measure: SetMeasure
    @Binding var set: PastSessionEditor.SetDraft
    let unit: MassUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                field(measure.measuresReps ? unit.symbol : String(localized: "lest \(unit.symbol)"), value: weightBinding)
                    .accessibilityIdentifier("history.edit.weight")
                if measure.measuresReps {
                    field(String(localized: "reps"), value: repsBinding)
                        .accessibilityIdentifier("history.edit.reps")
                }
                if measure.measuresDuration {
                    field(String(localized: "s"), value: optionalIntBinding(\.durationSeconds))
                        .accessibilityIdentifier("history.edit.duration")
                }
                if measure.measuresDistance {
                    field(String(localized: "m"), value: optionalDoubleBinding(\.distanceMeters))
                        .accessibilityIdentifier("history.edit.distance")
                }
            }
        }
    }

    private func field(_ suffix: String, value: Binding<Double>) -> some View {
        fieldBox(suffix) {
            TextField(suffix, value: value, format: .number)
                .keyboardType(.decimalPad)
        }
    }

    private func field(_ suffix: String, value: Binding<Int>) -> some View {
        fieldBox(suffix) {
            TextField(suffix, value: value, format: .number)
                .keyboardType(.numberPad)
        }
    }

    private func fieldBox<Content: View>(_ suffix: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 4) {
            content()
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(minWidth: 44)
            Text(suffix)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    /// Charge affichee dans l'unite du profil, stockee en kilogrammes.
    private var weightBinding: Binding<Double> {
        Binding(
            get: { (unit.fromKilograms(set.weight) * 100).rounded() / 100 },
            set: { set.weight = max(0, unit.toKilograms($0)) }
        )
    }

    private var repsBinding: Binding<Int> {
        Binding(get: { set.reps }, set: { set.reps = max(0, $0) })
    }

    /// Zero efface la valeur : une duree nulle est une absence de mesure,
    /// que la validation refuse ensuite clairement.
    private func optionalIntBinding(_ keyPath: WritableKeyPath<PastSessionEditor.SetDraft, Int?>) -> Binding<Int> {
        Binding(
            get: { set[keyPath: keyPath] ?? 0 },
            set: { set[keyPath: keyPath] = $0 > 0 ? $0 : nil }
        )
    }

    private func optionalDoubleBinding(_ keyPath: WritableKeyPath<PastSessionEditor.SetDraft, Double?>) -> Binding<Double> {
        Binding(
            get: { set[keyPath: keyPath] ?? 0 },
            set: { set[keyPath: keyPath] = $0 > 0 ? $0 : nil }
        )
    }
}
