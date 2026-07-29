import SwiftUI
import MuscuEngine

// Creation depuis un modele : choix du nombre de jours puis d'un split recommande
// (SplitTemplates.recommended), generation immediate d'un DraftProgram avec des
// valeurs par defaut raisonnables (hypertrophie, intermediaire, salle complete).
struct TemplatePickerView: View {
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(CatalogStore.self) private var catalogStore

    @State private var daysPerWeek = 3
    @State private var generatedDraft: DraftProgram?
    @State private var draftInput: GeneratorInput?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Stepper("Séances par semaine : \(daysPerWeek)", value: $daysPerWeek, in: 2...6)
                    if daysPerWeek == 6 {
                        Text("7 jours ? 6 jours + 1 repos est préférable.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Splits recommandés") {
                    ForEach(Array(templates.enumerated()), id: \.offset) { _, template in
                        Button {
                            generate(with: template.preference)
                        } label: {
                            TemplateCard(name: template.name, sessionNames: template.sessions.map(\.name))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Depuis un modèle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
            .navigationDestination(item: $generatedDraft) { draft in
                DraftPreviewView(
                    draft: draft,
                    regenerate: { regenerate() },
                    onSaved: {
                        onSaved()
                        dismiss()
                    }
                )
            }
        }
    }

    private var templates: [(preference: SplitPreference, name: String, sessions: [SessionBlueprint])] {
        SplitTemplates.recommended(daysPerWeek: daysPerWeek)
    }

    private func generate(with preference: SplitPreference) {
        let input = GeneratorInput(
            goal: .hypertrophy,
            experience: .intermediate,
            daysPerWeek: daysPerWeek,
            sessionMinutes: 60,
            equipment: .fullGym,
            splitPreference: preference,
            priorityMuscles: [],
            avoidAreas: []
        )
        draftInput = input
        generatedDraft = try? RuleBasedGenerator(catalog: catalogStore.catalog).generate(input)
    }

    private func regenerate() -> DraftProgram? {
        guard let draftInput else { return nil }
        return try? RuleBasedGenerator(catalog: catalogStore.catalog).generate(draftInput)
    }
}

private struct TemplateCard: View {
    let name: String
    let sessionNames: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .font(.headline)
                .foregroundStyle(.primary)
            Text(sessionNames.joined(separator: " · "))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

#Preview {
    TemplatePickerView(onSaved: {})
        .environment(CatalogStore())
        .preferredColorScheme(.dark)
}
