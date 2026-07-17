import SwiftUI
import MuscuEngine

// Selecteur d'exercice reutilisable : recherche + filtre muscle + miniatures.
// Utilise pour ajouter un exercice a une seance (Task 15) et pour le remplacer
// pendant une seance en cours (Task 18).
struct ExercisePickerView: View {
    @Environment(CatalogStore.self) private var catalogStore
    @Environment(\.dismiss) private var dismiss

    let onPick: (CatalogExercise) -> Void
    var initialMuscleFilter: String? = nil

    @State private var searchText = ""
    @State private var filterMuscle: String?

    init(initialMuscleFilter: String? = nil, onPick: @escaping (CatalogExercise) -> Void) {
        self.onPick = onPick
        self.initialMuscleFilter = initialMuscleFilter
        _filterMuscle = State(initialValue: initialMuscleFilter)
    }

    var body: some View {
        NavigationStack {
            List(filtered) { exercise in
                Button {
                    onPick(exercise)
                    dismiss()
                } label: {
                    ExercisePickerRow(exercise: exercise)
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
    ExercisePickerView { _ in }
        .environment(CatalogStore())
        .preferredColorScheme(.dark)
}
