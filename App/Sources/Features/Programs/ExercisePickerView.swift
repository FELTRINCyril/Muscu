import SwiftUI
import SwiftData
import MuscuEngine

// Selecteur d'exercice reutilisable : recherche + filtre muscle + miniatures.
// Utilise pour ajouter un exercice a une seance (Task 15), pour le remplacer
// pendant une seance en cours (Task 18) et pour choisir/creer un record.
// Le callback onPick expose (id, displayName) plutot que CatalogExercise
// directement : les exercices personnalises (CustomExercise) sont pickables
// au meme titre que le catalogue, avec leur UUID en guise d'exerciseId.
struct ExercisePickerView: View {
    @Environment(CatalogStore.self) private var catalogStore
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CustomExercise.name) private var customExercises: [CustomExercise]

    let onPick: (_ id: String, _ displayName: String) -> Void
    var initialMuscleFilter: String? = nil

    @State private var searchText = ""
    @State private var filterMuscle: String?

    init(initialMuscleFilter: String? = nil, onPick: @escaping (_ id: String, _ displayName: String) -> Void) {
        self.onPick = onPick
        self.initialMuscleFilter = initialMuscleFilter
        _filterMuscle = State(initialValue: initialMuscleFilter)
    }

    var body: some View {
        NavigationStack {
            List {
                if !filteredCustomExercises.isEmpty {
                    Section("Perso") {
                        ForEach(filteredCustomExercises) { custom in
                            Button {
                                onPick(custom.id.uuidString, custom.name)
                                dismiss()
                            } label: {
                                CustomExercisePickerRow(exercise: custom)
                            }
                        }
                    }
                }

                Section {
                    ForEach(filtered) { exercise in
                        Button {
                            onPick(exercise.id, exercise.nameFr)
                            dismiss()
                        } label: {
                            ExercisePickerRow(exercise: exercise)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Choisir un exercice")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Rechercher un exercice")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    muscleFilterMenu
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
        }
    }

    private var muscleFilterMenu: some View {
        Menu {
            Button("Tous") { filterMuscle = nil }
            ForEach(catalogStore.muscles, id: \.self) { muscle in
                Button(FrenchLabels.muscle(muscle)) { filterMuscle = muscle }
            }
        } label: {
            Image(systemName: filterMuscle == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
    }

    private var filtered: [CatalogExercise] {
        let searched = searchText.isEmpty ? catalogStore.all : catalogStore.search(searchText)
        return searched
            .filter { filterMuscle == nil || $0.primaryMuscles.contains(filterMuscle!) }
            .sorted { $0.nameFr.localizedStandardCompare($1.nameFr) == .orderedAscending }
    }

    private var filteredCustomExercises: [CustomExercise] {
        let needle = Self.normalize(searchText)
        return customExercises
            .filter { needle.isEmpty || Self.normalize($0.name).contains(needle) }
            .filter { filterMuscle == nil || $0.primaryMuscles.contains(filterMuscle!) }
    }

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
    }
}

private struct CustomExercisePickerRow: View {
    let exercise: CustomExercise

    var body: some View {
        HStack(spacing: 12) {
            ExerciseImageView(imagePath: nil)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .foregroundStyle(.primary)
                if let muscle = exercise.primaryMuscles.first {
                    Text(FrenchLabels.muscle(muscle))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text("Perso")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Theme.accent.opacity(0.15))
                .foregroundStyle(Theme.accent)
                .clipShape(Capsule())
        }
    }
}

private struct ExercisePickerRow: View {
    let exercise: CatalogExercise

    var body: some View {
        HStack(spacing: 12) {
            ExerciseImageView(imagePath: exercise.images.first)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.nameFr)
                    .foregroundStyle(.primary)
                if let muscle = exercise.primaryMuscles.first {
                    Text(FrenchLabels.muscle(muscle))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

#Preview {
    ExercisePickerView { _, _ in }
        .environment(CatalogStore())
        .preferredColorScheme(.dark)
}
