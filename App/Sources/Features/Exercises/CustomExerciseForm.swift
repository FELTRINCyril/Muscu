import SwiftUI
import SwiftData
import MuscuEngine

// Formulaire de creation d'un exercice perso.
struct CustomExerciseForm: View {
    @Environment(CatalogStore.self) private var catalogStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var selectedMuscles: Set<String> = []
    @State private var equipment = ""
    @State private var notes = ""

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValid: Bool {
        !trimmedName.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Nom") {
                    TextField("Nom de l'exercice", text: $name)
                }

                Section("Muscles") {
                    ForEach(catalogStore.muscles, id: \.self) { muscle in
                        Button {
                            toggle(muscle)
                        } label: {
                            HStack {
                                Text(FrenchLabels.muscle(muscle))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedMuscles.contains(muscle) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Theme.accent)
                                }
                            }
                        }
                    }
                }

                Section("Matériel") {
                    Picker("Matériel", selection: $equipment) {
                        Text("Aucun").tag("")
                        ForEach(catalogStore.equipments, id: \.self) { key in
                            Text(FrenchLabels.equipment(key)).tag(key)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Notes") {
                    TextField("Notes (optionnel)", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Nouvel exercice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }
                        .disabled(!isValid)
                }
            }
        }
    }

    private func toggle(_ muscle: String) {
        if selectedMuscles.contains(muscle) {
            selectedMuscles.remove(muscle)
        } else {
            selectedMuscles.insert(muscle)
        }
    }

    private func save() {
        let exercise = CustomExercise(
            name: trimmedName,
            primaryMuscles: Array(selectedMuscles),
            equipment: equipment,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        modelContext.insert(exercise)
        dismiss()
    }
}

#Preview {
    CustomExerciseForm()
        .environment(CatalogStore())
        .modelContainer(for: CustomExercise.self, inMemory: true)
        .preferredColorScheme(.dark)
}
