import SwiftUI
import MuscuEngine

/// Libelles et couleurs de la note d'effort de seance (1-10). Les paliers
/// viennent du moteur (`SessionEffort`) ; seule la presentation vit ici.
enum SessionEffortPresentation {
    static func label(for rating: Int) -> String {
        switch SessionEffort.band(for: rating) {
        case .veryEasy: return String(localized: "Très facile")
        case .easy: return String(localized: "Facile")
        case .moderate: return String(localized: "Modéré")
        case .hard: return String(localized: "Difficile")
        case .veryHard: return String(localized: "Très difficile")
        case .maximal: return String(localized: "Maximal")
        case nil: return ""
        }
    }

    /// Progression du vert au rouge, comme les paliers.
    static func color(for rating: Int) -> Color {
        switch SessionEffort.band(for: rating) {
        case .veryEasy, .easy: return .green
        case .moderate: return .yellow
        case .hard: return .orange
        case .veryHard, .maximal, nil: return .red
        }
    }

    /// « Effort 7/10 · Difficile ».
    static func summary(for rating: Int) -> String {
        String(localized: "Effort \(rating)/10 · \(label(for: rating))")
    }
}

/// Note d'effort de fin de seance : dix barres de hauteur croissante, que
/// l'on touche ou sur lesquelles on glisse le doigt. Facultative : « Effacer »
/// remet la note a « non renseignee » (jamais 0).
///
/// Geometrie des barres et geste de glissement adaptes d'UpLift
/// (`Views/Workout/EffortRatingView.swift`, licence MIT, cf.
/// THIRD_PARTY_NOTICES.md).
struct EffortRatingView: View {
    @Binding var rating: Int?
    /// Faux une fois la seance enregistree : la note est alors affichee,
    /// plus modifiable.
    var isEditable: Bool = true

    private let barCount = SessionEffort.range.count
    private let minBarHeight: CGFloat = 24
    private let maxBarHeight: CGFloat = 88
    private let barSpacing: CGFloat = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Effort ressenti")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if rating != nil, isEditable {
                    Button("Effacer") { rating = nil }
                        .font(.caption)
                        .accessibilityIdentifier("effort.clear")
                }
            }

            GeometryReader { geometry in
                let totalSpacing = barSpacing * CGFloat(barCount - 1)
                let barWidth = max(4, (geometry.size.width - totalSpacing) / CGFloat(barCount))
                HStack(alignment: .bottom, spacing: barSpacing) {
                    ForEach(Array(SessionEffort.range), id: \.self) { value in
                        RoundedRectangle(cornerRadius: 6)
                            .fill(fill(for: value))
                            .frame(width: barWidth, height: barHeight(for: value))
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
                .contentShape(Rectangle())
                .allowsHitTesting(isEditable)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let width = max(1, geometry.size.width)
                            let selected = SessionEffort.rating(atFraction: Double(value.location.x / width))
                            if selected != rating {
                                rating = selected
                                FeedbackSettings.selectionChanged()
                            }
                        }
                )
            }
            .frame(height: maxBarHeight)
            .accessibilityElement()
            .accessibilityLabel(Text("Effort ressenti"))
            .accessibilityValue(Text(accessibilityValue))
            .accessibilityAdjustableAction { direction in
                guard isEditable else { return }
                switch direction {
                case .increment:
                    rating = min(SessionEffort.range.upperBound, (rating ?? 0) + 1)
                case .decrement:
                    rating = max(SessionEffort.range.lowerBound, (rating ?? 2) - 1)
                @unknown default:
                    break
                }
            }
            .accessibilityIdentifier("effort.bars")

            HStack {
                Text("Très facile")
                Spacer()
                Text("Maximal")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)

            Group {
                if let rating {
                    Text(SessionEffortPresentation.summary(for: rating))
                        .foregroundStyle(SessionEffortPresentation.color(for: rating))
                } else if isEditable {
                    Text("Facultatif : glisse sur les barres pour noter la séance.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Effort non renseigné")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.footnote)
            .accessibilityIdentifier("effort.label")
        }
        .padding()
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var accessibilityValue: String {
        guard let rating else { return String(localized: "Non renseigné") }
        return SessionEffortPresentation.summary(for: rating)
    }

    private func barHeight(for value: Int) -> CGFloat {
        let fraction = CGFloat(value) / CGFloat(barCount)
        return minBarHeight + (maxBarHeight - minBarHeight) * fraction
    }

    private func fill(for value: Int) -> Color {
        guard let rating else { return Color.white.opacity(0.12) }
        return value <= rating ? SessionEffortPresentation.color(for: rating) : Color.white.opacity(0.12)
    }
}
