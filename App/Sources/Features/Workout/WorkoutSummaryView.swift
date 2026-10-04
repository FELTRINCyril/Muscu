import SwiftUI
import SwiftData
import MuscuEngine

// Recap de fin de seance : duree, tonnage, nb de series, detail par exercice.
// Au moment de "Terminer", la seance est basculee dans l'historique puis les
// records eventuellement battus (RecordDetection) sont proposes un par un :
// jamais de mise a jour silencieuse d'un ExerciseRecord.
struct WorkoutSummaryView: View {
    let state: WorkoutState
    let onFinish: () -> Void
    @Environment(\.massUnit) private var massUnit

    @State private var hasFinished = false
    @State private var pendingSuggestions: [RecordDetection.RecordSuggestion] = []
    // Une fois la seance terminee, state.loggedSets se vide (l'ActiveWorkout
    // est supprimee, cf. WorkoutState.finish) : on garde les series de la
    // CompletedSession fraichement creee pour continuer a afficher le recap.
    @State private var finishedSets: [CompletedSet]?
    @State private var isFinishing = false
    /// Note d'effort facultative, choisie avant « Terminer » : elle part
    /// avec la seance. Ensuite elle est figee — une seance terminee est
    /// immuable (cf. decision 0011, synchronisation).
    @State private var effortRating: Int?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(spacing: 4) {
                        Text("Séance terminée")
                            .font(.title2.weight(.bold))
                        Text(state.sessionTitle)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)

                    HStack(spacing: 12) {
                        StatCard(title: "Durée", value: formattedDuration)
                        StatCard(
                            title: "Tonnage",
                            value: WeightFormatter.string(kilograms: totalTonnage, unit: massUnit),
                            // Une seance dont le poids de corps est inconnu
                            // a un tonnage PARTIEL. L'afficher comme un
                            // total serait mentir sur une valeur ronde.
                            note: tonnage.unknownSets > 0
                                ? String(localized: "\(tonnage.unknownSets) série(s) non mesurables")
                                : nil
                        )
                        StatCard(title: "Séries", value: "\(workingSets.count)")
                    }

                    EffortRatingView(rating: $effortRating, isEditable: !hasFinished && !isFinishing)

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
            .padding(.horizontal)
            .padding(.top)
            .padding(.bottom, state.isFreeSession && !hasFinished ? 4 : 16)

            // Seance libre : la fin a ete demandee, elle peut encore etre
            // reprise tant que rien n'est enregistre.
            if state.isFreeSession && !hasFinished {
                Button("Continuer la séance") {
                    state.cancelEndRequest()
                }
                .font(.footnote)
                .disabled(isFinishing)
                .padding(.bottom)
                .accessibilityIdentifier("workout.continueFreeSession")
            }
        }
        .background(Theme.background)
    }

    // MARK: - Records

    private func finishSession() {
        isFinishing = true
        guard let completedSession = state.finish(effortRating: effortRating) else {
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

    /// Tonnage calcule par le MOTEUR, comme l'historique et les graphiques.
    ///
    /// Le calcul maison `poids x reps` qui vivait ici etait faux des que la
    /// serie n'etait pas une charge externe : une traction au poids du corps
    /// comptait pour zero, une traction assistee comptait son aide comme du
    /// travail. Deux ecrans affichaient deux tonnages differents pour la
    /// meme seance.
    private var tonnage: (total: Double, unknownSets: Int) {
        let bodyweight = ProfileStore.latestBodyweightKilograms(in: state.modelContext)
        let inputs = (finishedSets ?? state.loggedSets)
            .map { $0.metricsInput(bodyweightKilograms: bodyweight) }
        return SetMetrics.totalTonnage(inputs)
    }

    private var totalTonnage: Double { tonnage.total }

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
    let title: LocalizedStringKey
    let value: String
    /// Precision facultative : sert a dire qu'une valeur est PARTIELLE
    /// plutot qu'a la laisser passer pour un total.
    var note: String? = nil

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.weight(.semibold))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let note {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
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
    @Environment(\.massUnit) private var massUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(displayName)
                .font(.subheadline.weight(.semibold))

            // Meme mise en forme que l'historique : dans un superset les
            // tours doivent se lire « Tour 2 », et les trois paliers d'un
            // dropset ne peuvent pas s'afficher tous « Série 1 ».
            ForEach(sets) { set in
                HStack(alignment: .firstTextBaseline) {
                    Text(CompletedSetPresentation.label(for: set, inGroup: set.groupId != nil))
                    Spacer(minLength: 8)
                    Text(CompletedSetPresentation.performance(for: set, unit: massUnit))
                        .multilineTextAlignment(.trailing)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
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
    @Environment(\.massUnit) private var massUnit
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
                return String(localized: "\(WeightFormatter.string(kilograms: old, unit: massUnit)) -> \(WeightFormatter.string(kilograms: new, unit: massUnit))")
            }
            return String(localized: "1RM estimé : \(WeightFormatter.string(kilograms: new, unit: massUnit))")
        case .maxReps(let new, let old):
            if let old {
                return String(localized: "\(old) -> \(new) répétitions")
            }
            return String(localized: "\(new) répétitions")
        }
    }
}
