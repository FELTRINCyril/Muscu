import Foundation
import SwiftData
import MuscuEngine

/// Ce qu'on partage d'une seance : un resume lisible, en texte ou en image.
///
/// Rien d'autre que ce qui est affiche ne part : ni identifiant, ni note
/// personnelle, ni mesure de sante (frequence cardiaque, energie), ni lieu.
/// Le texte et la carte image sont construits depuis la MEME description,
/// pour qu'ils disent exactement la meme chose. Inspire de
/// `ShareWorkoutSheet.tsx` d'Ischys (MIT) : une carte et un texte, choisis
/// par l'utilisateur.
struct SessionShareSummary: Equatable {
    struct Exercise: Equatable {
        var name: String
        /// Series de travail mises en forme, dans l'ordre.
        var sets: [String]
    }

    struct Record: Equatable {
        var exerciseName: String
        var label: String
        var value: String
    }

    var title: String
    var dateLabel: String
    var durationLabel: String?
    var workingSetCount: Int
    var tonnageLabel: String?
    var effortLabel: String?
    var exercises: [Exercise]
    var records: [Record]

    @MainActor
    static func make(
        for session: CompletedSession,
        records: [PersonalBest],
        unit: MassUnit,
        locale: Locale = WeightFormatter.displayLocale
    ) -> SessionShareSummary {
        let title = session.sessionName.isEmpty ? String(localized: "Séance") : session.sessionName
        let start = PastSessionEditor.interval(of: session).start
        let dateLabel = start.formatted(
            .dateTime.weekday(.wide).day().month(.wide).year().locale(locale)
        )
        let duration = session.durationSeconds > 0 ? durationLabel(session.durationSeconds) : nil

        let byOrder = Dictionary(grouping: session.sets.filter { $0.role.countsAsWorkingSet }, by: \.orderIndex)
        let exercises = byOrder.keys.sorted().compactMap { orderIndex -> Exercise? in
            guard let sets = byOrder[orderIndex], let first = sets.first else { return nil }
            let ordered = sets.sorted {
                ($0.roundIndex, $0.setIndex, $0.subSetIndex) < ($1.roundIndex, $1.setIndex, $1.subSetIndex)
            }
            return Exercise(
                name: first.displayName,
                sets: ordered.map { CompletedSetPresentation.performance(for: $0, unit: unit) }
            )
        }

        let tonnage = CompletedSetPresentation.tonnage(for: session)
        let shareRecords = records
            .filter { $0.deletedAt == nil && $0.sourceSessionId == session.id }
            .sorted { ($0.displayName, $0.kindRaw) < ($1.displayName, $1.kindRaw) }
            .map { Record(exerciseName: $0.displayName, label: $0.kind.displayName, value: recordValue($0, unit: unit)) }

        return SessionShareSummary(
            title: title,
            dateLabel: dateLabel,
            durationLabel: duration,
            workingSetCount: session.workingSets.count,
            // Un tonnage partiel (poids de corps inconnu) n'est pas partage
            // comme un total : il est simplement omis.
            tonnageLabel: tonnage.total > 0 && tonnage.unknownSets == 0
                ? WeightFormatter.string(kilograms: tonnage.total, unit: unit)
                : nil,
            effortLabel: session.effortRating.map { SessionEffortPresentation.summary(for: $0) },
            exercises: exercises,
            records: shareRecords
        )
    }

    private static func recordValue(_ best: PersonalBest, unit: MassUnit) -> String {
        switch best.kind {
        case .maxWeight, .estimatedOneRepMax, .maxSessionVolume:
            return WeightFormatter.string(kilograms: best.value, unit: unit)
        default:
            return best.formattedValue
        }
    }

    static func durationLabel(_ seconds: Int) -> String {
        let minutes = max(0, seconds) / 60
        if minutes >= 60 {
            return String(localized: "\(minutes / 60) h \(String(format: "%02d", minutes % 60))")
        }
        return String(localized: "\(minutes) min")
    }

    /// Texte partage : titre, date, statistiques, exercices, records.
    var text: String {
        var lines: [String] = []
        lines.append("\(title) — \(dateLabel)")
        var stats: [String] = []
        if let durationLabel { stats.append(durationLabel) }
        stats.append(String(localized: "\(workingSetCount) séries"))
        if let tonnageLabel { stats.append(tonnageLabel) }
        if let effortLabel { stats.append(effortLabel) }
        lines.append(stats.joined(separator: " · "))
        for exercise in exercises {
            lines.append("")
            lines.append(exercise.name)
            for (index, set) in exercise.sets.enumerated() {
                lines.append("  \(index + 1). \(set)")
            }
        }
        if !records.isEmpty {
            lines.append("")
            lines.append(String(localized: "Records"))
            for record in records {
                lines.append("  - \(record.exerciseName) — \(record.label) : \(record.value)")
            }
        }
        lines.append("")
        lines.append(String(localized: "Enregistré avec Muscu"))
        return lines.joined(separator: "\n")
    }
}
