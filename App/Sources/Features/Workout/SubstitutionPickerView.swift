import SwiftUI
import SwiftData
import MuscuEngine

/// Remplacement d'un exercice pendant la seance.
///
/// Deux decisions distinctes, jamais confondues :
/// 1. remplacer POUR CETTE SEANCE — immediat, l'historique gardera prévu et
///    réalisé ;
/// 2. modifier AUSSI le programme — uniquement sur confirmation explicite.
struct SubstitutionPickerView: View {
    let currentExerciseId: String
    let prescriptionId: UUID
    let onReplace: (String, String) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(CatalogStore.self) private var catalogStore
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \PlaceProfile.name) private var places: [PlaceProfile]

    @State private var applyToProgram = false
    @State private var restrictToPlace = true
    @State private var showingFullPicker = false
    @State private var confirming: SubstitutionCandidate?

    private var place: PlaceProfile? {
        places.first { $0.deletedAt == nil && $0.isDefault } ?? places.first { $0.deletedAt == nil }
    }

    private var inventory: EquipmentInventory {
        restrictToPlace ? (place?.inventory ?? EquipmentInventory()) : EquipmentInventory()
    }

    private var candidates: [SubstitutionCandidate] {
        guard let current = catalogStore.exercise(id: currentExerciseId) else { return [] }
        return SubstitutionFinder.candidates(
            for: current,
            in: catalogStore.all,
            inventory: inventory,
            level: current.level,
            limit: 12
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Modifier aussi le programme", isOn: $applyToProgram)
                        .accessibilityIdentifier("substitution.applyToProgram")
                    if let place, !place.inventory.isEmpty {
                        Toggle("Limiter au matériel de « \(place.name) »", isOn: $restrictToPlace)
                            .accessibilityIdentifier("substitution.restrictPlace")
                    }
                } footer: {
                    Text(applyToProgram
                         ? "Le programme sera modifié après confirmation."
                         : "Seule cette séance est concernée. Le programme reste intact.")
                }

                Section {
                    if candidates.isEmpty {
                        Text("Aucun remplacement proposé ici. Vous pouvez choisir librement un exercice.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(candidates) { candidate in
                        Button {
                            confirming = candidate
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(candidate.exercise.nameFr)
                                ForEach(Array(candidate.reasons.prefix(2).enumerated()), id: \.offset) { _, reason in
                                    Text(reason.explanation)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text("Remplacements proposés")
                } footer: {
                    Text("Classés par muscles travaillés, type de mouvement, matériel disponible et niveau.")
                }

                Section {
                    Button("Choisir un autre exercice") { showingFullPicker = true }
                        .accessibilityIdentifier("substitution.freeChoice")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Remplacer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
            .sheet(isPresented: $showingFullPicker) {
                ExercisePickerView(initialMuscleFilter: catalogStore.exercise(id: currentExerciseId)?.primaryMuscles.first) { id, displayName in
                    replace(exerciseId: id, displayName: displayName)
                }
            }
            .confirmationDialog(
                applyToProgram ? "Remplacer dans la séance ET dans le programme ?" : "Remplacer pour cette séance ?",
                isPresented: Binding(
                    get: { confirming != nil },
                    set: { if !$0 { confirming = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Remplacer") {
                    if let candidate = confirming {
                        replace(exerciseId: candidate.exercise.id, displayName: candidate.exercise.nameFr)
                    }
                    confirming = nil
                }
                Button("Annuler", role: .cancel) { confirming = nil }
            } message: {
                Text(applyToProgram
                     ? "Le programme sera modifié durablement. L’historique déjà enregistré n’est jamais touché."
                     : "Le programme n’est pas modifié. L’historique gardera l’exercice prévu et l’exercice réalisé.")
            }
        }
    }

    private func replace(exerciseId: String, displayName: String) {
        onReplace(exerciseId, displayName)
        if applyToProgram { applyToPrescription(exerciseId: exerciseId, displayName: displayName) }
        LibraryStore.markUsed(exerciseId, in: modelContext)
        dismiss()
    }

    /// Modifie la prescription du programme. Uniquement appelee apres la
    /// confirmation explicite ci-dessus.
    private func applyToPrescription(exerciseId: String, displayName: String) {
        ProgramEditing.applySubstitution(
            prescriptionId: prescriptionId,
            exerciseId: exerciseId,
            displayName: displayName,
            in: modelContext
        )
    }
}
