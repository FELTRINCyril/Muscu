import SwiftUI
import SwiftData
import MuscuEngine

// Onglet Exercices : catalogue + recherche + filtres + exercices perso.
struct ExercisesView: View {
    @Environment(CatalogStore.self) private var catalogStore
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CustomExercise.name) private var customExercises: [CustomExercise]

    @State private var searchText = ""
    @State private var filterMuscle: String?
    @State private var filterEquipment: String?
    @State private var filterCategory: String?
    @State private var showingAddSheet = false

    var body: some View {
        NavigationStack {
            List {
                if !filteredCustomExercises.isEmpty {
                    Section("Exercices perso") {
                        ForEach(filteredCustomExercises) { exercise in
                            NavigationLink {
                                CustomExerciseDetailView(exercise: exercise)
                            } label: {
                                CustomExerciseRow(exercise: exercise)
                            }
                        }
                        .onDelete(perform: deleteCustomExercises)
                    }
                }

                Section("Catalogue") {
                    ForEach(filteredCatalogExercises) { exercise in
                        NavigationLink {
                            ExerciseDetailView(exercise: exercise)
                        } label: {
                            CatalogExerciseRow(exercise: exercise)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Exercices")
            .searchable(text: $searchText, prompt: "Rechercher un exercice")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    filterMenu
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("exercises.addButton")
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                CustomExerciseForm()
            }
        }
    }

    private var filterMenu: some View {
        Menu {
            Menu("Muscle") {
                Button("Tous") { filterMuscle = nil }
                ForEach(catalogStore.muscles, id: \.self) { muscle in
                    Button(FrenchLabels.muscle(muscle)) { filterMuscle = muscle }
                }
            }
            Menu("Matériel") {
                Button("Tous") { filterEquipment = nil }
                ForEach(catalogStore.equipments, id: \.self) { equipment in
                    Button(FrenchLabels.equipment(equipment)) { filterEquipment = equipment }
                }
            }
            Menu("Catégorie") {
                Button("Toutes") { filterCategory = nil }
                ForEach(catalogStore.categories, id: \.self) { category in
                    Button(FrenchLabels.category(category)) { filterCategory = category }
                }
            }
        } label: {
            Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
    }

    private var hasActiveFilters: Bool {
        filterMuscle != nil || filterEquipment != nil || filterCategory != nil
    }

    private var filteredCatalogExercises: [CatalogExercise] {
        let searched = searchText.isEmpty ? catalogStore.all : catalogStore.search(searchText)
        return searched
            .filter { exercise in
                if let filterMuscle, !exercise.primaryMuscles.contains(filterMuscle) {
                    return false
                }
                if let filterEquipment, exercise.equipment != filterEquipment {
                    return false
                }
                if let filterCategory, exercise.category != filterCategory {
                    return false
                }
                return true
            }
            .sorted { $0.nameFr.localizedStandardCompare($1.nameFr) == .orderedAscending }
    }

    private var filteredCustomExercises: [CustomExercise] {
        customExercises.filter { exercise in
            if !searchText.isEmpty && !Self.normalize(exercise.name).contains(Self.normalize(searchText)) {
                return false
            }
            if let filterMuscle, !exercise.primaryMuscles.contains(filterMuscle) {
                return false
            }
            if let filterEquipment, exercise.equipment != filterEquipment {
                return false
            }
            // Les exercices perso n'ont pas de categorie : exclus si un filtre categorie est actif.
            if filterCategory != nil {
                return false
            }
            return true
        }
    }

    private func deleteCustomExercises(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(filteredCustomExercises[index])
        }
    }

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
    }
}

private struct CatalogExerciseRow: View {
    let exercise: CatalogExercise

    var body: some View {
        HStack(spacing: 12) {
            ExerciseImageView(imagePath: exercise.images.first)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.nameFr)
                    .font(.body)
                if let muscle = exercise.primaryMuscles.first {
                    Text(FrenchLabels.muscle(muscle))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct CustomExerciseRow: View {
    let exercise: CustomExercise

    var body: some View {
        HStack(spacing: 12) {
            ExerciseImageView(imagePath: nil)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(exercise.name)
                        .font(.body)
                    PersoBadge()
                }
                if let muscle = exercise.primaryMuscles.first {
                    Text(FrenchLabels.muscle(muscle))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct PersoBadge: View {
    var body: some View {
        Text("Perso")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Theme.accent.opacity(0.2))
            .foregroundStyle(Theme.accent)
            .clipShape(Capsule())
    }
}

#Preview {
    ExercisesView()
        .environment(CatalogStore())
        .modelContainer(for: CustomExercise.self, inMemory: true)
        .preferredColorScheme(.dark)
}
