import SwiftUI
import SwiftData
import MuscuEngine

// Fiche detaillee d'un exercice du catalogue.
struct ExerciseDetailView: View {
    let exercise: CatalogExercise

    @State private var currentImageIndex = 0
    @Environment(NetworkStatus.self) private var networkStatus
    @Environment(CatalogStore.self) private var catalogStore
    @Environment(\.modelContext) private var modelContext
    @Query private var libraryEntries: [ExerciseLibraryEntry]
    @Query(sort: \PlaceProfile.name) private var places: [PlaceProfile]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                imageView
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .onTapGesture {
                        guard exercise.images.count > 1 else { return }
                        currentImageIndex = (currentImageIndex + 1) % exercise.images.count
                    }

                Text(exercise.nameFr)
                    .font(.title2.weight(.bold))

                infoRow

                if !exercise.primaryMuscles.isEmpty {
                    ChipsSection(title: "Muscles principaux", muscles: exercise.primaryMuscles)
                }

                if !exercise.secondaryMuscles.isEmpty {
                    ChipsSection(title: "Muscles secondaires", muscles: exercise.secondaryMuscles)
                }

                if !exercise.instructionsFr.isEmpty {
                    instructionsSection
                }

                variantsSection

                sourceSection

                videoButton
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle("Fiche exercice")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    LibraryStore.toggleFavorite(exercise.id, in: modelContext)
                } label: {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                }
                .tint(.yellow)
                .accessibilityLabel(isFavorite ? "Retirer des favoris" : "Ajouter aux favoris")
                .accessibilityIdentifier("exercise.favorite")
            }
        }
    }

    private var isFavorite: Bool {
        libraryEntries.contains { $0.exerciseId == exercise.id && $0.isFavorite && $0.deletedAt == nil }
    }

    private var personalTags: [String] {
        libraryEntries.first { $0.exerciseId == exercise.id }.map { $0.tags.sorted() } ?? []
    }

    /// Variantes proches, CALCULEES depuis le catalogue (mêmes muscles
    /// principaux, même type de mouvement). Aucune liste éditoriale n’est
    /// inventée : ce qui est affiché est déductible des données présentes.
    private var variants: [SubstitutionCandidate] {
        let inventory = places
            .first { $0.deletedAt == nil && $0.isDefault }?
            .inventory ?? EquipmentInventory()
        return SubstitutionFinder.candidates(
            for: exercise,
            in: catalogStore.all,
            inventory: inventory,
            level: exercise.level,
            limit: 5
        )
    }

    @ViewBuilder
    private var variantsSection: some View {
        let candidates = variants
        if !candidates.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Variantes proches")
                    .font(.headline)
                ForEach(candidates) { candidate in
                    NavigationLink {
                        ExerciseDetailView(exercise: candidate.exercise)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(candidate.exercise.nameFr)
                                .font(.subheadline)
                            Text(candidate.reasons.first?.explanation ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Origine et droits des contenus. Un média sans provenance connue n’a
    /// rien à faire dans l’application.
    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !personalTags.isEmpty {
                Text("Vos tags : " + personalTags.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Données et images : free-exercise-db (The Unlicense). Traductions françaises maintenues par Muscu. Aucun contenu n’est collecté ailleurs.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var imageView: some View {
        ExerciseImageView(imagePath: exercise.images.indices.contains(currentImageIndex) ? exercise.images[currentImageIndex] : nil)
    }

    private var infoRow: some View {
        HStack(spacing: 16) {
            if let equipment = exercise.equipment {
                Label(FrenchLabels.equipment(equipment), systemImage: "dumbbell")
            }
            Label(FrenchLabels.level(exercise.level), systemImage: "chart.bar.fill")
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Instructions")
                .font(.headline)
            ForEach(Array(exercise.instructionsFr.enumerated()), id: \.offset) { index, instruction in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1).")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                    Text(instruction)
                        .font(.subheadline)
                }
            }
        }
    }

    private var videoButton: some View {
        VStack(spacing: 4) {
            if networkStatus.isOnline {
                Link(destination: videoSearchURL) {
                    videoButtonLabel
                }
            } else {
                videoButtonLabel
                    .opacity(0.4)
            }

            if !networkStatus.isOnline {
                Text("Connexion internet requise")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var videoButtonLabel: some View {
        Label("Voir en vidéo", systemImage: "play.rectangle.fill")
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding()
            .background(Theme.card)
            .foregroundStyle(Theme.accent)
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var videoSearchURL: URL {
        let query = "\(exercise.name) form"
        var components = URLComponents(string: "https://www.youtube.com/results")!
        components.queryItems = [URLQueryItem(name: "search_query", value: query)]
        return components.url!
    }
}

private struct ChipsSection: View {
    let title: String
    let muscles: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            FlowChips(labels: muscles.map(FrenchLabels.muscle))
        }
    }
}

// Disposition simple en lignes qui s'enchainent, sans dependance externe.
private struct FlowChips: View {
    let labels: [String]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(labels, id: \.self) { label in
                Text(label)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.card)
                    .clipShape(Capsule())
            }
        }
    }
}

// Fiche simplifiee pour un exercice perso : pas d'images ni d'instructions, mais les notes.
struct CustomExerciseDetailView: View {
    let exercise: CustomExercise

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(exercise.name)
                        .font(.title2.weight(.bold))
                    PersoBadge()
                }

                if !exercise.equipment.isEmpty {
                    Label(FrenchLabels.equipment(exercise.equipment), systemImage: "dumbbell")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if !exercise.primaryMuscles.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Muscles")
                            .font(.headline)
                        FlowChips(labels: exercise.primaryMuscles.map(FrenchLabels.muscle))
                    }
                }

                if !exercise.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes")
                            .font(.headline)
                        Text(exercise.notes)
                            .font(.subheadline)
                    }
                }
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle("Fiche exercice")
        .navigationBarTitleDisplayMode(.inline)
    }
}
