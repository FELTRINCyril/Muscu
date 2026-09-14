import SwiftUI
import SwiftData

// Recap de fin de seance : duree, tonnage, nb de series, detail par exercice.
// Au moment de "Terminer", la seance est basculee dans l'historique puis les
// records eventuellement battus (RecordDetection) sont proposes un par un :
// jamais de mise a jour silencieuse d'un ExerciseRecord.
struct WorkoutSummaryView: View {
    let state: WorkoutState
    let onFinish: () -> Void

    @State private var hasFinished = false
    @State private var pendingSuggestions: [RecordDetection.RecordSuggestion] = []
    // Une fois la seance terminee, state.loggedSets se vide (l'ActiveWorkout
    // est supprimee, cf. WorkoutState.finish) : on garde les series de la
    // CompletedSession fraichement creee pour continuer a afficher le recap.
    @State private var finishedSets: [CompletedSet]?
    @State private var isFinishing = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(spacing: 4) {
                        Text("Séance terminée")
                            .font(.title2.weight(.bold))
                        Text(state.programSession.name)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)

                    HStack(spacing: 12) {
                        StatCard(title: "Durée", value: formattedDuration)
                        StatCard(title: "Tonnage", value: "\(WorkoutState.formatWeight(totalTonnage)) kg")
                        StatCard(title: "Séries", value: "\(workingSets.count)")
                    }

                    if hasFinished && !pendingSuggestions.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(pendingSuggestions) { suggestion in
                                RecordSuggestionCard(
                                    suggestion: suggestion,
                                    onSave: { save(suggestion) },
                                    onDismiss: { discard(suggestion) }
                                )
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(groupedByExercise, id: \.orderIndex) { group in
                            ExerciseSummaryCard(displayName: group.displayName, sets: group.sets)
                        }
                    }
                }
                .padding()
            }

            Button {
                if hasFinished {
                    onFinish()
                } else {
                    finishSession()
                }
            } label: {
                Text(hasFinished ? "Fermer" : "Terminer")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .controlSize(.large)
            .disabled(isFinishing)
            .accessibilityIdentifier(hasFinished ? "workout.closeSummaryButton" : "workout.finishSummaryButton")
            .padding()
        }
        .background(Theme.background)
    }

    // MARK: - Records

    private func finishSession() {
        isFinishing = true
        guard let completedSession = state.finish() else {
            isFinishing = false
            return
        }
        finishedSets = completedSession.sets

        // Les widgets affichent la semaine écoulée : ils doivent refléter
        // cette séance immédiatement.
        WidgetSnapshotService.refresh(in: state.modelContext)

        // Écriture dans Santé, si et seulement si l'utilisateur l'a activée.
        // Un échec n'affecte pas la séance : elle est déjà enregistrée.
        Task {
            await HealthSyncService.synchronize(
                in: state.modelContext,
                store: AppServices.healthStore
            )
        }
        let records = (try? state.modelContext.fetch(FetchDescriptor<ExerciseRecord>())) ?? []
        // Le poids de corps fige sur la seance prime ; a defaut on retombe
        // sur la derniere mesure connue, sans jamais supposer une valeur.
        let bodyweight = ProfileStore.latestBodyweightKilograms(in: state.modelContext)
        pendingSuggestions = RecordDetection.check(
            session: completedSession,
            records: records,
            bodyweightKilograms: bodyweight
        )
        // Les records TYPES (charge, tonnage, temps, tours) sont recalcules
        // depuis l'historique et n'ont pas besoin d'etre confirmes un par un :
        // ils decrivent ce qui vient d'etre fait, sans modifier de programme.
        let candidates = PersonalBestUpdater.candidates(for: completedSession, bodyweightKilograms: bodyweight)
        if !PersonalBestUpdater.apply(
            candidates: candidates,
            context: state.modelContext,
            sourceSessionId: completedSession.id,
            achievedAt: completedSession.date
        ).isEmpty {
            _ = PersistenceSupport.save(state.modelContext, action: "Enregistrement des records")
        }
        hasFinished = true
        isFinishing = false
    }

    private func save(_ suggestion: RecordDetection.RecordSuggestion) {
        let record = fetchRecord(exerciseId: suggestion.exerciseId)
            ?? ExerciseRecord(exerciseId: suggestion.exerciseId, displayName: suggestion.displayName)

        switch suggestion.kind {
        case .oneRepMax(let new, _):
            record.oneRepMax = new
        case .maxReps(let new, _):
            record.maxReps = new
        }
        record.updatedAt = .now

        if record.modelContext == nil {
            state.modelContext.insert(record)
        }
        if PersistenceSupport.save(state.modelContext, action: "Enregistrement du record") {
            discard(suggestion)
        }
    }

    private func discard(_ suggestion: RecordDetection.RecordSuggestion) {
        pendingSuggestions.removeAll { $0.id == suggestion.id }
    }

    private func fetchRecord(exerciseId: String) -> ExerciseRecord? {
        let descriptor = FetchDescriptor<ExerciseRecord>(predicate: #Predicate { $0.exerciseId == exerciseId })
        return try? state.modelContext.fetch(descriptor).first
    }

    // Les series d'echauffement (isWarmup) sont loggees pour l'historique
    // mais ne comptent ni dans le tonnage ni dans le nombre de series de
    // travail affiches ici (ce ne sont pas des series de travail).
    private var workingSets: [CompletedSet] {
        (finishedSets ?? state.loggedSets).filter { !$0.isWarmup }
    }

    private var totalTonnage: Double {
        workingSets.reduce(0) { $0 + $1.weight * Double($1.reps) }
    }

    private var formattedDuration: String {
        let seconds = max(0, Int(Date.now.timeIntervalSince(state.startedAt)))
        let minutes = seconds / 60
        let remainder = seconds % 60
        return String(format: "%d:%02d", minutes, remainder)
    }

    private struct ExerciseGroup {
        let orderIndex: Int
        let displayName: String
        let sets: [CompletedSet]
    }

    private var groupedByExercise: [ExerciseGroup] {
        let grouped = Dictionary(grouping: workingSets, by: \.orderIndex)
        return grouped.keys.sorted().compactMap { orderIndex in
            guard let sets = grouped[orderIndex], let displayName = sets.first?.displayName else { return nil }
            return ExerciseGroup(
                orderIndex: orderIndex,
                displayName: displayName,
                sets: sets.sorted { $0.setIndex < $1.setIndex }
            )
        }
    }
}

private struct StatCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.weight(.semibold))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct ExerciseSummaryCard: View {
    let displayName: String
    let sets: [CompletedSet]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(displayName)
                .font(.subheadline.weight(.semibold))

            ForEach(sets) { set in
                Text("Série \(set.setIndex + 1) : \(set.reps) reps @ \(WorkoutState.formatWeight(set.weight)) kg")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct RecordSuggestionCard: View {
    let suggestion: RecordDetection.RecordSuggestion
    let onSave: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "trophy.fill")
                    .foregroundStyle(Theme.accent)
                Text("Nouveau record !")
                    .font(.subheadline.weight(.semibold))
            }
            Text(suggestion.displayName)
                .font(.subheadline)
            Text(detailLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Ignorer", role: .cancel) { onDismiss() }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Enregistrer") { onSave() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
            }
        }
        .padding()
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var detailLabel: String {
        switch suggestion.kind {
        case .oneRepMax(let new, let old):
            if let old {
                return "\(WorkoutState.formatWeight(old)) kg -> \(WorkoutState.formatWeight(new)) kg"
            }
            return "1RM estimé : \(WorkoutState.formatWeight(new)) kg"
        case .maxReps(let new, let old):
            if let old {
                return "\(old) -> \(new) répétitions"
            }
            return "\(new) répétitions"
        }
    }
}
