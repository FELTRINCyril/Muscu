import AppIntents
import Foundation
import SwiftData
import SwiftUI
import MuscuEngine

// Siri et Raccourcis : records et fin de seance.
//
// Les questions (1RM, records recents) ne font que LIRE. Terminer et
// abandonner ecrivent : elles demandent toujours une confirmation et passent
// par le MEME chemin que les boutons de l'application (`WorkoutState`).
// Idee de la fin de seance a la voix : Iron (GPL) — aucun code repris.

// MARK: - Quel est mon 1RM ?

struct OneRepMaxIntent: AppIntent {
    static let title: LocalizedStringResource = "Quel est mon 1RM ?"
    static let description = IntentDescription("Donne le 1RM estimé d’un exercice et, s’il existe, le 1RM de référence saisi ou testé.")
    static let openAppWhenRun = false

    @Parameter(title: "Exercice", requestValueDialog: "Pour quel exercice ?")
    var exercise: ExerciseEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let context = try IntentStore.context()
        let answer = IntentAnswers.oneRepMax(exerciseId: exercise.id, in: context)
        let unit = ProfileStore.massUnit(in: context)
        let text = IntentAnswers.oneRepMaxText(answer, exerciseName: exercise.name, unit: unit)
        return .result(
            dialog: "\(text)",
            view: OneRepMaxSnippetView(exerciseName: exercise.name, answer: answer, unit: unit)
        )
    }
}

// MARK: - Mes records récents

struct RecentRecordsIntent: AppIntent {
    static let title: LocalizedStringResource = "Mes records récents"
    static let description = IntentDescription("Liste les derniers records établis, du plus récent au plus ancien.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let context = try IntentStore.context()
        let records = IntentAnswers.recentRecords(in: context, now: .now)
        let text = IntentAnswers.recentRecordsText(records)
        return .result(dialog: "\(text)", view: RecentRecordsSnippetView(records: records))
    }
}

// MARK: - Terminer la séance

struct FinishWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Terminer la séance"
    static let description = IntentDescription("Enregistre la séance en cours dans l’historique, comme le bouton « Terminer ».")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let state = LiveWorkoutActions.currentState()
        switch IntentAnswers.endCheck(for: state) {
        case .noSession:
            return .result(dialog: "Aucune séance n’est en cours.")
        case .nothingLogged:
            return .result(dialog: "Aucune série n’est enregistrée : il n’y a rien à terminer. Vous pouvez abandonner la séance.")
        case .canFinish(let workingSets, let remainingSlots):
            guard let state else { return .result(dialog: "Aucune séance n’est en cours.") }
            let question = IntentAnswers.finishConfirmationText(
                sessionTitle: state.sessionTitle,
                workingSets: workingSets,
                remainingSlots: remainingSlots
            )
            // Une ecriture ne part jamais sans confirmation.
            try await requestConfirmation(
                actionName: .custom(
                    acceptLabel: "Terminer",
                    acceptAlternatives: [],
                    denyLabel: "Continuer la séance",
                    denyAlternatives: []
                ),
                dialog: IntentDialog("\(question)")
            )
            // La seance a pu etre terminee ou abandonnee dans l'application
            // pendant la confirmation.
            guard !state.isClosed, state.activeWorkout != nil else {
                return .result(dialog: "Aucune séance n’est en cours.")
            }
            guard let completion = state.complete(outsideRunner: true) else {
                return .result(dialog: "La séance n’a pas pu être enregistrée. Elle reste en cours.")
            }
            return .result(dialog: "\(IntentAnswers.finishedText(completion.session))")
        }
    }
}

// MARK: - Abandonner la séance

struct DiscardWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Abandonner la séance"
    static let description = IntentDescription("Supprime la séance en cours et ses séries, sans rien ajouter à l’historique.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let state = LiveWorkoutActions.currentState() else {
            return .result(dialog: "Aucune séance n’est en cours.")
        }
        let question = IntentAnswers.discardConfirmationText(
            sessionTitle: state.sessionTitle,
            loggedSets: state.loggedSets.filter { $0.role.countsAsWorkingSet }.count
        )
        // Destructif : confirmation explicite, bouton marque comme tel.
        try await requestConfirmation(
            actionName: .custom(
                acceptLabel: "Abandonner",
                acceptAlternatives: [],
                denyLabel: "Garder la séance",
                denyAlternatives: [],
                destructive: true
            ),
            dialog: IntentDialog("\(question)")
        )
        guard !state.isClosed, state.activeWorkout != nil else {
            return .result(dialog: "Aucune séance n’est en cours.")
        }
        guard state.discard(outsideRunner: true) else {
            return .result(dialog: "L’abandon n’a pas pu être enregistré. La séance reste en cours.")
        }
        return .result(dialog: "Séance abandonnée. Rien n’a été ajouté à l’historique.")
    }
}

// MARK: - Réponses

/// Construction des reponses, separee des intents pour etre testee.
@MainActor
enum IntentAnswers {
    // MARK: 1RM

    /// Meilleure estimation (records types) et 1RM de reference (saisi ou
    /// teste) d'un exercice.
    static func oneRepMax(exerciseId: String, in context: ModelContext) -> RecordAnswers.OneRepMax {
        let estimatedKind = PersonalBestKind.estimatedOneRepMax.rawValue
        let bests = (try? context.fetch(FetchDescriptor<PersonalBest>(
            predicate: #Predicate { $0.exerciseId == exerciseId && $0.kindRaw == estimatedKind }
        ))) ?? []
        let estimated = bests
            .filter { $0.deletedAt == nil && $0.configurationKey.isEmpty }
            .map { RecordAnswers.DatedValue(value: $0.value, date: $0.achievedAt) }

        let record = ((try? context.fetch(FetchDescriptor<ExerciseRecord>(
            predicate: #Predicate { $0.exerciseId == exerciseId }
        ))) ?? []).first { $0.deletedAt == nil }
        let reference = record.flatMap { record in
            record.oneRepMax.map { RecordAnswers.DatedValue(value: $0, date: record.updatedAt) }
        }
        return RecordAnswers.oneRepMax(estimatedCandidates: estimated, reference: reference)
    }

    static func oneRepMaxText(_ answer: RecordAnswers.OneRepMax, exerciseName: String, unit: MassUnit) -> String {
        switch (answer.estimated, answer.reference) {
        case (nil, nil):
            return String(localized: "Aucun 1RM connu pour \(exerciseName) : ni estimation dans l’historique, ni valeur de référence.")
        case (let estimated?, nil):
            return String(localized: "1RM estimé pour \(exerciseName) : \(weight(estimated.value, unit)), le \(day(estimated.date)).")
        case (nil, let reference?):
            return String(localized: "1RM de référence pour \(exerciseName) : \(weight(reference.value, unit)), enregistré le \(day(reference.date)). Aucune estimation dans l’historique.")
        case (let estimated?, let reference?):
            return String(localized: "1RM estimé pour \(exerciseName) : \(weight(estimated.value, unit)), le \(day(estimated.date)). 1RM de référence : \(weight(reference.value, unit)), enregistré le \(day(reference.date)).")
        }
    }

    // MARK: Records récents

    struct RecentRecord: Identifiable, Equatable {
        let id: UUID
        let exerciseName: String
        let kindLabel: String
        let valueText: String
        let date: Date
    }

    static func recentRecords(in context: ModelContext, now: Date) -> [RecentRecord] {
        let bests = ((try? context.fetch(FetchDescriptor<PersonalBest>())) ?? []).filter { $0.deletedAt == nil }
        let byId = Dictionary(bests.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let entries = bests.map {
            RecordAnswers.RecordEntry(
                id: $0.id,
                exerciseName: $0.displayName,
                kindKey: $0.kindRaw,
                value: $0.value,
                achievedAt: $0.achievedAt
            )
        }
        return RecordAnswers.recent(entries, now: now).compactMap { entry in
            guard let best = byId[entry.id] else { return nil }
            let label = best.configurationLabel.map { "\(best.kind.displayName) (\($0))" } ?? best.kind.displayName
            return RecentRecord(
                id: entry.id,
                exerciseName: entry.exerciseName,
                kindLabel: label,
                valueText: best.formattedValue,
                date: entry.achievedAt
            )
        }
    }

    static func recentRecordsText(_ records: [RecentRecord]) -> String {
        guard !records.isEmpty else {
            return String(localized: "Aucun record sur les \(RecordAnswers.recentWindowDays) derniers jours.")
        }
        let lines = records.map { record in
            String(localized: "\(record.exerciseName), \(record.kindLabel) : \(record.valueText) (\(day(record.date)))")
        }
        return String(localized: "Records récents : \(lines.joined(separator: " ; ")).")
    }

    // MARK: Fin de séance

    static func endCheck(for state: WorkoutState?) -> SessionEndCheck {
        guard let state, !state.isClosed, state.activeWorkout != nil else { return .noSession }
        return SessionEndCheck.evaluate(
            hasActiveSession: true,
            workingSetsLogged: state.loggedSets.filter { $0.role.countsAsWorkingSet }.count,
            progress: state.progress,
            isFreeSession: state.isFreeSession
        )
    }

    static func finishConfirmationText(sessionTitle: String, workingSets: Int, remainingSlots: Int) -> String {
        let base = String(localized: "Terminer « \(sessionTitle) » ? \(workingSets) série(s) de travail enregistrée(s).")
        guard remainingSlots > 0 else { return base }
        return base + " " + String(localized: "\(remainingSlots) série(s) prévue(s) ne seront pas faites.")
    }

    static func finishedText(_ session: CompletedSession) -> String {
        let minutes = max(0, session.durationSeconds) / 60
        return String(localized: "Séance enregistrée : \(session.workingSets.count) série(s) de travail en \(minutes) min.")
    }

    static func discardConfirmationText(sessionTitle: String, loggedSets: Int) -> String {
        String(localized: "Abandonner « \(sessionTitle) » ? Les \(loggedSets) série(s) enregistrée(s) seront supprimées et rien ne sera ajouté à l’historique.")
    }

    // MARK: Mise en forme

    static func weight(_ kilograms: Double, _ unit: MassUnit) -> String {
        WeightFormatter.string(kilograms: kilograms, unit: unit)
    }

    static func day(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }
}

// MARK: - Vues Siri

/// Petite vue affichee par Siri sous la reponse au 1RM.
struct OneRepMaxSnippetView: View {
    let exerciseName: String
    let answer: RecordAnswers.OneRepMax
    let unit: MassUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(exerciseName)
                .font(.headline)
            if answer.isEmpty {
                Text("Aucun 1RM connu")
                    .foregroundStyle(.secondary)
            }
            if let estimated = answer.estimated {
                row(title: "1RM estimé", value: estimated)
            }
            if let reference = answer.reference {
                row(title: "1RM de référence", value: reference)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(title: LocalizedStringKey, value: RecordAnswers.DatedValue) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                Text(value.date, format: .dateTime.day().month(.abbreviated).year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(verbatim: WeightFormatter.string(kilograms: value.value, unit: unit))
                .font(.title3.weight(.semibold))
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

/// Liste courte des records recents.
struct RecentRecordsSnippetView: View {
    let records: [IntentAnswers.RecentRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if records.isEmpty {
                Text("Aucun record récent")
                    .foregroundStyle(.secondary)
            }
            ForEach(records) { record in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: record.exerciseName)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(verbatim: record.kindLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(verbatim: record.valueText)
                            .font(.subheadline)
                            .monospacedDigit()
                        Text(record.date, format: .dateTime.day().month(.abbreviated))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
