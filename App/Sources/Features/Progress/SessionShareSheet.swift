import SwiftUI
import MuscuEngine

/// Partage d'une seance : apercu de la carte image, puis partage de
/// l'image ou du texte. Ce qui part est exactement ce qui est affiche.
struct SessionShareSheet: View {
    let summary: SessionShareSummary

    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @State private var renderedImage: Image?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    SessionShareCard(summary: summary)
                        .frame(width: 320, height: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .accessibilityIdentifier("share.card")

                    VStack(spacing: 12) {
                        if let renderedImage {
                            ShareLink(
                                item: renderedImage,
                                preview: SharePreview(summary.title, image: renderedImage)
                            ) {
                                Label("Partager l’image", systemImage: "photo")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.accent)
                            .accessibilityIdentifier("share.image")
                        }
                        ShareLink(item: summary.text) {
                            Label("Partager le texte", systemImage: "text.alignleft")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("share.text")
                    }
                    .controlSize(.large)

                    Text("Seul le contenu affiché est partagé : ni notes, ni lieu, ni données de santé.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Text(summary.text)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .textSelection(.enabled)
                }
                .padding()
            }
            .background(Theme.background)
            .navigationTitle("Partager la séance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
            .task { render() }
        }
    }

    /// Carte carree rendue en image (1080 px de cote environ).
    @MainActor
    private func render() {
        let renderer = ImageRenderer(content:
            SessionShareCard(summary: summary)
                .frame(width: 360, height: 360)
        )
        renderer.scale = max(displayScale, 3)
        if let image = renderer.uiImage {
            renderedImage = Image(uiImage: image)
        }
    }
}

/// Carte carree au style sombre de l'application.
struct SessionShareCard: View {
    let summary: SessionShareSummary

    /// Au-dela, la carte resterait lisible mais trop chargee.
    private let maximumExercises = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Muscu", systemImage: "dumbbell.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.accent)
                Spacer()
                Text(summary.dateLabel)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Text(summary.title)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.6)

            HStack(spacing: 8) {
                if let duration = summary.durationLabel {
                    stat(duration, caption: String(localized: "Durée"))
                }
                stat("\(summary.workingSetCount)", caption: String(localized: "Séries"))
                if let tonnage = summary.tonnageLabel {
                    stat(tonnage, caption: String(localized: "Tonnage"))
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(summary.exercises.prefix(maximumExercises).enumerated()), id: \.offset) { _, exercise in
                    HStack(alignment: .firstTextBaseline) {
                        Text(exercise.name)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        Text(String(localized: "\(exercise.sets.count) séries"))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .font(.caption)
                }
                if summary.exercises.count > maximumExercises {
                    Text(String(localized: "+ \(summary.exercises.count - maximumExercises) exercice(s)"))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                if !summary.records.isEmpty {
                    Label(String(localized: "\(summary.records.count) record(s)"), systemImage: "trophy.fill")
                        .foregroundStyle(Theme.accent)
                }
                Spacer()
                if let effort = summary.effortLabel {
                    Text(effort)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .font(.caption2.weight(.semibold))
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [Theme.card, Theme.background],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .environment(\.colorScheme, .dark)
    }

    private func stat(_ value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
