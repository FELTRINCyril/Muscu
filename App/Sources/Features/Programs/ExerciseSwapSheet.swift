import SwiftUI
import MuscuEngine

// Sheet compacte de remplacement d'un exercice par une alternative du meme
// groupe de mouvement (ou repli meme muscle), avec acces au picker complet.
// Utilisee par DraftPreviewView (brouillons) et SessionEditorView (programmes).
struct ExerciseSwapSheet: View {
    let currentExerciseId: String
    let onSwap: (_ id: String, _ displayName: String) -> Void

    @Environment(CatalogStore.self) private var catalogStore
    @Environment(\.dismiss) private var dismiss

    @State private var showingFullPicker = false

    private var alternatives: [CatalogExercise] {
        ExerciseAlternatives.alternatives(for: currentExerciseId, in: catalogStore.catalog)
    }

    private var currentPrimaryMuscle: String? {
        catalogStore.exercise(id: currentExerciseId)?.primaryMuscles.first
    }

    var body: some View {
        NavigationStack {
            List {
                if alternatives.isEmpty {
                    Text("Aucune alternative directe pour cet exercice.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Section("Alternatives") {
                        ForEach(alternatives, id: \.id) { exercise in
                            Button {
                                onSwap(exercise.id, exercise.nameFr)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(exercise.nameFr)
                                        .foregroundStyle(.primary)
                                    if let equipment = exercise.equipment {
                                        Text(FrenchLabels.equipment(equipment))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }

                Section {
                    Button {
                        showingFullPicker = true
                    } label: {
                        Label("Autre exercice...", systemImage: "magnifyingglass")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Remplacer par")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
            .sheet(isPresented: $showingFullPicker) {
                ExercisePickerView(initialMuscleFilter: currentPrimaryMuscle) { id, displayName in
                    onSwap(id, displayName)
                    dismiss()
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
