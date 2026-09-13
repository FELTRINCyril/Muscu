import SwiftUI
import SwiftData
import MuscuEngine

// Onglet Exercices : catalogue + recherche + filtres + exercices perso.
struct ExercisesView: View {
    @Environment(CatalogStore.self) private var catalogStore
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CustomExercise.name) private var customExercises: [CustomExercise]
    @Query private var prescribedExercises: [PrescribedExercise]
    @Query private var completedSets: [CompletedSet]
    @Query private var activeWorkouts: [ActiveWorkout]
    // Les annotations personnelles sont requetees plutot que lues une fois :
    // mettre un exercice en favori doit reordonner la liste immediatement.
    @Query private var libraryEntries: [ExerciseLibraryEntry]
    @Query(sort: \ExerciseCollection.name) private var collections: [ExerciseCollection]
    @Query(sort: \PlaceProfile.name) private var places: [PlaceProfile]

    @State private var searchText = ""
    @State private var filterMuscle: String?
    @State private var filterEquipment: String?
    @State private var filterCategory: String?
    @State private var filterLevel: String?
    @State private var filterTag: String?
    @State private var filterPlaceId: UUID?
    @State private var favoritesOnly = false
    @State private var showingAddSheet = false
    @State private var pendingDeletion: CustomExercise?
    @State private var deletionBlockedMessage: String?
    @State private var taggingExerciseId: String?
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
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

                Section {
                    ForEach(filteredCatalogExercises) { exercise in
                        NavigationLink {
                            ExerciseDetailView(exercise: exercise)
                        } label: {
                            CatalogExerciseRow(
                                exercise: exercise,
                                isFavorite: metadata.isFavorite(exercise.id),
                                tags: metadata.tags(for: exercise.id).sorted()
                            )
                        }
                        .swipeActions(edge: .leading) {
                            favoriteButton(for: exercise.id)
                            Button {
                                taggingExerciseId = exercise.id
                            } label: {
                                Label("Tags", systemImage: "tag")
                            }
                            .tint(.blue)
                        }
                    }
                } header: {
                    Text("Catalogue")
                } footer: {
                    if filteredCatalogExercises.isEmpty && filteredCustomExercises.isEmpty {
                        Text(emptyMessage)
                    }
                }

            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Exercices")
            .navigationDestination(for: CatalogExerciseRoute.self) { route in
                if let exercise = catalogStore.exercise(id: route.id) {
                    ExerciseDetailView(exercise: exercise)
                }
            }
            .onAppear(perform: openRequestedExercise)
            .onChange(of: IntentRouter.shared.pending) { _, _ in openRequestedExercise() }
            .searchable(text: $searchText, prompt: "Rechercher un exercice")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    // Les collections vivent dans la barre d'outils, pas en
                    // bas de la liste : le catalogue compte plus de 800
                    // exercices, un lien place apres eux serait inatteignable.
                    NavigationLink {
                        ExerciseCollectionsView()
                    } label: {
                        Image(systemName: "folder")
                    }
                    .accessibilityLabel("Collections")
                    .accessibilityIdentifier("exercises.collections")

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
            .sheet(item: Binding(
                get: { taggingExerciseId.map(TaggedExercise.init) },
                set: { taggingExerciseId = $0?.id }
            )) { tagged in
                ExerciseTagEditor(exerciseId: tagged.id, initialTags: metadata.tags(for: tagged.id))
            }
            .confirmationDialog("Supprimer cet exercice personnalisé ?", isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            )) {
                Button("Supprimer", role: .destructive) { confirmDeletion() }
                Button("Annuler", role: .cancel) { pendingDeletion = nil }
            }
            .alert("Suppression impossible", isPresented: Binding(
                get: { deletionBlockedMessage != nil },
                set: { if !$0 { deletionBlockedMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deletionBlockedMessage ?? "")
            }
        }
    }

    private var filterMenu: some View {
        Menu {
            Toggle("Favoris uniquement", isOn: $favoritesOnly)
                .accessibilityIdentifier("exercises.filter.favorites")
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
            Menu("Difficulté") {
                Button("Toutes") { filterLevel = nil }
                ForEach(["beginner", "intermediate", "expert"], id: \.self) { level in
                    Button(FrenchLabels.level(level)) { filterLevel = level }
                }
            }
            if !allTags.isEmpty {
                Menu("Tags") {
                    Button("Tous") { filterTag = nil }
                    ForEach(allTags, id: \.self) { tag in
                        Button(tag) { filterTag = tag }
                    }
                }
            }
            if !activePlaces.isEmpty {
                Menu("Lieu") {
                    Button("Tous") { filterPlaceId = nil }
                    ForEach(activePlaces, id: \.id) { place in
                        Button(place.name) { filterPlaceId = place.id }
                    }
                }
            }
            if hasActiveFilters {
                Divider()
                Button("Tout effacer", role: .destructive) { clearFilters() }
            }
        } label: {
            Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .accessibilityIdentifier("exercises.filters")
        .accessibilityLabel(hasActiveFilters ? "Filtres actifs" : "Filtres")
    }

    /// Ouvre la fiche demandee par un raccourci Siri, une seule fois.
    private func openRequestedExercise() {
        guard case .exercise(let id)? = IntentRouter.shared.pending else { return }
        _ = IntentRouter.shared.consume()
        guard catalogStore.exercise(id: id) != nil else { return }
        path.append(CatalogExerciseRoute(id: id))
    }

    private func favoriteButton(for exerciseId: String) -> some View {
        Button {
            LibraryStore.toggleFavorite(exerciseId, in: modelContext)
        } label: {
            Label(
                metadata.isFavorite(exerciseId) ? "Retirer des favoris" : "Ajouter aux favoris",
                systemImage: metadata.isFavorite(exerciseId) ? "star.slash" : "star"
            )
        }
        .tint(.yellow)
    }

    private var activePlaces: [PlaceProfile] {
        places.filter { $0.deletedAt == nil }
    }

    private var allTags: [String] {
        Array(libraryEntries.reduce(into: Set<String>()) { $0.formUnion($1.tags) }).sorted()
    }

    /// Annotations personnelles, reconstruites depuis la requete : elles
    /// suivent donc les modifications sans rafraichissement manuel.
    private var metadata: LibraryMetadata {
        var favorites: Set<String> = []
        var tags: [String: Set<String>] = [:]
        var lastUsed: [String: Date] = [:]
        for entry in libraryEntries where entry.deletedAt == nil {
            if entry.isFavorite { favorites.insert(entry.exerciseId) }
            let entryTags = entry.tags
            if !entryTags.isEmpty { tags[entry.exerciseId] = entryTags }
            if let date = entry.lastUsedAt { lastUsed[entry.exerciseId] = date }
        }
        return LibraryMetadata(favorites: favorites, tags: tags, lastUsed: lastUsed)
    }

    private var filters: LibraryFilters {
        LibraryFilters(
            muscles: filterMuscle.map { [$0] } ?? [],
            equipment: filterEquipment.map { [$0] } ?? [],
            levels: filterLevel.map { [$0] } ?? [],
            categories: filterCategory.map { [$0] } ?? [],
            tags: filterTag.map { [$0] } ?? [],
            favoritesOnly: favoritesOnly,
            inventory: filterPlaceId.flatMap { id in activePlaces.first { $0.id == id }?.inventory }
        )
    }

    private var hasActiveFilters: Bool {
        !filters.isEmpty
    }

    private func clearFilters() {
        filterMuscle = nil
        filterEquipment = nil
        filterCategory = nil
        filterLevel = nil
        filterTag = nil
        filterPlaceId = nil
        favoritesOnly = false
    }

    private var emptyMessage: String {
        if !searchText.isEmpty {
            return "Aucun exercice ne correspond à « \(searchText) ». La recherche ignore les accents et tolère une faute simple."
        }
        return "Aucun exercice ne correspond aux filtres actifs."
    }

    /// La recherche et les filtres passent par `LibrarySearch` : l'onglet
    /// Exercices, le sélecteur d'exercice et Siri appliquent ainsi
    /// exactement les mêmes règles.
    private var filteredCatalogExercises: [CatalogExercise] {
        LibrarySearch.run(
            query: searchText,
            filters: filters,
            catalog: catalogStore.all,
            metadata: metadata
        )
        .map(\.exercise)
    }

    /// Les exercices perso passent par la même recherche : ils sont
    /// convertis en entrée de catalogue le temps du classement, puis
    /// retrouvés par identifiant pour garder leur écran dédié.
    private var filteredCustomExercises: [CustomExercise] {
        let converted = customExercises.map { exercise in
            CatalogExercise(
                id: exercise.id.uuidString,
                name: exercise.name,
                nameFr: exercise.name,
                level: "intermediate",
                equipment: exercise.equipment,
                primaryMuscles: exercise.primaryMuscles,
                category: "strength"
            )
        }
        // Un filtre de categorie ne s'applique pas aux exercices perso, qui
        // n'en portent pas : on les masque plutot que d'en inventer une.
        guard filterCategory == nil else { return [] }

        var customFilters = filters
        customFilters.categories = []
        let ranked = LibrarySearch.run(
            query: searchText,
            filters: customFilters,
            catalog: converted,
            metadata: metadata
        )
        let byId = Dictionary(customExercises.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { first, _ in first })
        return ranked.compactMap { byId[$0.exercise.id] }
    }

    private func deleteCustomExercises(at offsets: IndexSet) {
        guard let index = offsets.first else { return }
        pendingDeletion = filteredCustomExercises[index]
    }

    private func confirmDeletion() {
        guard let exercise = pendingDeletion else { return }
        let id = exercise.id.uuidString
        let isUsed = prescribedExercises.contains { $0.exerciseId == id }
            || completedSets.contains { $0.exerciseId == id }
            || activeWorkouts.flatMap(\.loggedSets).contains { $0.exerciseId == id }
        guard !isUsed else {
            pendingDeletion = nil
            deletionBlockedMessage = "Cet exercice est encore utilisé dans un programme ou un historique. Retire-le des programmes concernés avant de le supprimer; l’historique reste ainsi lisible."
            return
        }
        modelContext.delete(exercise)
        if PersistenceSupport.save(modelContext, action: "Suppression de l’exercice personnalisé") {
            pendingDeletion = nil
        }
    }

}

/// Destination de navigation vers une fiche d'exercice du catalogue.
/// `CatalogExercise` n'est pas `Hashable` ; son identifiant l'est.
struct CatalogExerciseRoute: Hashable {
    let id: String
}

/// Enveloppe identifiable pour presenter la feuille de tags.
private struct TaggedExercise: Identifiable {
    let id: String
}

private struct CatalogExerciseRow: View {
    let exercise: CatalogExercise
    var isFavorite: Bool = false
    var tags: [String] = []

    var body: some View {
        HStack(spacing: 12) {
            ExerciseImageView(imagePath: exercise.images.first)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(exercise.nameFr)
                        .font(.body)
                    if isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                            .accessibilityLabel("Favori")
                    }
                }
                if let muscle = exercise.primaryMuscles.first {
                    Text(FrenchLabels.muscle(muscle))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !tags.isEmpty {
                    Text(tags.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Edition des tags d'un exercice.
struct ExerciseTagEditor: View {
    let exerciseId: String
    let initialTags: Set<String>

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Tags séparés par des virgules", text: $text, axis: .vertical)
                        .accessibilityIdentifier("exercise.tags.field")
                } footer: {
                    Text("Les tags sont normalisés (sans accent ni majuscule) pour rester cherchables d’une seule façon.")
                }
            }
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        let tags = text
                            .split(separator: ",")
                            .map { String($0).trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                        LibraryStore.setTags(Set(tags), for: exerciseId, in: modelContext)
                        dismiss()
                    }
                    .accessibilityIdentifier("exercise.tags.save")
                }
            }
            .onAppear { text = initialTags.sorted().joined(separator: ", ") }
        }
    }
}

/// Collections personnalisees d'exercices.
struct ExerciseCollectionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(CatalogStore.self) private var catalogStore
    @Query(sort: \ExerciseCollection.name) private var collections: [ExerciseCollection]

    @State private var newName = ""

    private var active: [ExerciseCollection] {
        collections.filter { $0.deletedAt == nil }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("Nom de la collection", text: $newName)
                        .accessibilityIdentifier("collections.name")
                    Button("Créer") {
                        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        LibraryStore.createCollection(named: trimmed, in: modelContext)
                        newName = ""
                    }
                    .accessibilityIdentifier("collections.create")
                }
            }

            Section {
                if active.isEmpty {
                    Text("Aucune collection.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(active, id: \.id) { collection in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(collection.name)
                        Text("\(collection.exerciseIds.count) exercice(s)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                .onDelete { offsets in
                    for index in offsets { LibraryStore.delete(active[index], in: modelContext) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Collections")
        .navigationBarTitleDisplayMode(.inline)
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
