import SwiftUI
import MuscuEngine

// Questionnaire generateur : une question par ecran, gros boutons tappables,
// indicateur de progression et bouton retour. Derniere etape -> RuleBasedGenerator.
struct GeneratorWizardView: View {
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(CatalogStore.self) private var catalogStore

    private static let totalSteps = 9

    @State private var step = 1

    @State private var goal: Goal?
    @State private var experience: Experience?
    @State private var daysPerWeek: Int?
    @State private var sessionMinutes: Int?
    @State private var equipment: TrainingEquipment?
    @State private var splitPreference: SplitPreference = .auto
    @State private var priorityMuscles: Set<String> = []
    @State private var avoidAreas: Set<String> = []

    @State private var planWeeks: Int = 8
    @State private var periodizationStyle: PeriodizationStyle = .linear
    @State private var deloadEveryWeeks: Int? = 4
    @State private var createsPlan = true

    @State private var generatedDraft: DraftProgram?
    @State private var generatedPlan: DraftPlan?
    @State private var draftInput: GeneratorInput?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                progressHeader

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        stepContent
                    }
                    .padding()
                }
            }
            .background(Theme.background)
            .navigationTitle("Générateur")
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
                    plan: generatedPlan,
                    onSaved: {
                        onSaved()
                        dismiss()
                    }
                )
            }
            .alert(
                "Génération impossible",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - En-tete de progression

    private var progressHeader: some View {
        VStack(spacing: 8) {
            HStack {
                if step > 1 {
                    Button {
                        withAnimation { step -= 1 }
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                } else {
                    Color.clear.frame(width: 22, height: 22)
                }
                Spacer()
                Text("\(step)/\(Self.totalSteps)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Color.clear.frame(width: 22, height: 22)
            }
            ProgressView(value: Double(step), total: Double(Self.totalSteps))
                .tint(Theme.accent)
        }
        .padding()
    }

    // MARK: - Contenu par etape

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 1: goalStep
        case 2: experienceStep
        case 3: daysStep
        case 4: durationStep
        case 5: equipmentStep
        case 6: splitStep
        case 7: priorityMusclesStep
        case 8: avoidAreasStep
        case 9: planStep
        default: EmptyView()
        }
    }

    private var goalStep: some View {
        WizardStep(title: "Quel est ton objectif ?") {
            optionCard("Prise de masse", isSelected: goal == .hypertrophy) { select(goal: .hypertrophy) }
            optionCard("Force", isSelected: goal == .strength) { select(goal: .strength) }
            optionCard("Perte de poids", isSelected: goal == .fatLoss) { select(goal: .fatLoss) }
            optionCard("Endurance", isSelected: goal == .endurance) { select(goal: .endurance) }
            optionCard("Progression tractions", isSelected: goal == .pullUpProgress) { select(goal: .pullUpProgress) }
            optionCard("Calisthenics", isSelected: goal == .calisthenics) { select(goal: .calisthenics) }
        }
    }

    private var experienceStep: some View {
        WizardStep(title: "Quel est ton niveau ?") {
            optionCard("Débutant (moins d'un an)", isSelected: experience == .beginner) { select(experience: .beginner) }
            optionCard("Intermédiaire (1 à 3 ans)", isSelected: experience == .intermediate) { select(experience: .intermediate) }
            optionCard("Avancé (3 ans et plus)", isSelected: experience == .advanced) { select(experience: .advanced) }
        }
    }

    private var daysStep: some View {
        WizardStep(title: "Combien de séances par semaine ?") {
            ForEach(2...6, id: \.self) { count in
                optionCard("\(count) séances par semaine", isSelected: daysPerWeek == count) {
                    select(daysPerWeek: count)
                }
            }
        }
    }

    private var durationStep: some View {
        WizardStep(title: "Durée maximale par séance ?") {
            optionCard("45 min", isSelected: sessionMinutes == 45) { select(sessionMinutes: 45) }
            optionCard("1 h", isSelected: sessionMinutes == 60) { select(sessionMinutes: 60) }
            optionCard("1 h 30", isSelected: sessionMinutes == 90) { select(sessionMinutes: 90) }
        }
    }

    private var equipmentStep: some View {
        WizardStep(title: "Quel matériel as-tu ?") {
            optionCard("Salle complète", isSelected: equipment == .fullGym) { select(equipment: .fullGym) }
            optionCard("Maison avec matériel", isSelected: equipment == .homeGym) { select(equipment: .homeGym) }
            optionCard("Poids du corps", isSelected: equipment == .bodyweight) { select(equipment: .bodyweight) }
        }
    }

    private var splitStep: some View {
        WizardStep(title: "Quel type de split ?") {
            optionCard("Choisis pour moi", isSelected: splitPreference == .auto) {
                select(splitPreference: .auto)
            }
            ForEach(Array(availableSplits.enumerated()), id: \.offset) { _, template in
                optionCard(template.name, isSelected: splitPreference == template.preference) {
                    select(splitPreference: template.preference)
                }
            }
        }
    }

    private var priorityMusclesStep: some View {
        WizardStep(title: "Points faibles à prioriser ?", subtitle: "Optionnel - sélection multiple") {
            ChipFlow(
                items: catalogStore.muscles,
                label: FrenchLabels.muscle,
                isSelected: { priorityMuscles.contains($0) },
                onToggle: { toggle(&priorityMuscles, $0) }
            )
            nextButton(title: "Suivant") { advance() }
        }
    }

    private var avoidAreasStep: some View {
        WizardStep(title: "Zones à ménager ?", subtitle: "Optionnel - sélection multiple") {
            ChipFlow(
                items: Self.avoidAreaOptions.map(\.key),
                label: { key in Self.avoidAreaOptions.first { $0.key == key }?.label ?? key },
                isSelected: { avoidAreas.contains($0) },
                onToggle: { toggle(&avoidAreas, $0) }
            )
            nextButton(title: "Suivant") { advance() }
        }
    }

    // Derniere etape : structurer le programme en plan pluri-semaines.
    private var planStep: some View {
        WizardStep(title: "Sur combien de semaines ?", subtitle: "La périodisation fait varier volume et intensité") {
            optionCard("Programme simple, sans plan daté", isSelected: !createsPlan) {
                createsPlan = false
            }

            ForEach([4, 8, 12, 16], id: \.self) { weeks in
                optionCard("Plan de \(weeks) semaines", isSelected: createsPlan && planWeeks == weeks) {
                    createsPlan = true
                    planWeeks = weeks
                }
            }

            if createsPlan {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Périodisation", selection: $periodizationStyle) {
                        Text("Linéaire").tag(PeriodizationStyle.linear)
                        Text("Ondulatoire").tag(PeriodizationStyle.undulating)
                        Text("Constante").tag(PeriodizationStyle.flat)
                    }
                    .pickerStyle(.segmented)

                    Toggle("Semaine de décharge toutes les 4 semaines", isOn: Binding(
                        get: { deloadEveryWeeks != nil },
                        set: { deloadEveryWeeks = $0 ? 4 : nil }
                    ))
                    .font(.subheadline)
                }
                .padding(.top, 4)
            }

            nextButton(title: "Générer") { generate() }
        }
    }

    private static let avoidAreaOptions: [(key: String, label: String)] = [
        ("lower back", "Lombaires"),
        ("knees", "Genoux"),
        ("shoulders", "Épaules"),
        ("wrists", "Poignets"),
        ("neck", "Nuque"),
    ]

    // MARK: - Selections (avance automatiquement pour les etapes a choix unique)

    private func select(goal: Goal) {
        self.goal = goal
        advance()
    }

    private func select(experience: Experience) {
        self.experience = experience
        advance()
    }

    private func select(daysPerWeek: Int) {
        self.daysPerWeek = daysPerWeek
        advance()
    }

    private func select(sessionMinutes: Int) {
        self.sessionMinutes = sessionMinutes
        advance()
    }

    private func select(equipment: TrainingEquipment) {
        self.equipment = equipment
        advance()
    }

    private func select(splitPreference: SplitPreference) {
        self.splitPreference = splitPreference
        advance()
    }

    private func toggle(_ set: inout Set<String>, _ value: String) {
        if set.contains(value) {
            set.remove(value)
        } else {
            set.insert(value)
        }
    }

    private func advance() {
        withAnimation {
            step = min(step + 1, Self.totalSteps)
        }
    }

    private var availableSplits: [(preference: SplitPreference, name: String, sessions: [SessionBlueprint])] {
        guard let daysPerWeek else { return [] }
        return SplitTemplates.recommended(daysPerWeek: daysPerWeek)
    }

    // MARK: - Generation

    private func generate() {
        guard let goal, let experience, let daysPerWeek, let sessionMinutes, let equipment else {
            errorMessage = "Toutes les questions doivent être renseignées."
            return
        }
        let input = GeneratorInput(
            goal: goal,
            experience: experience,
            daysPerWeek: daysPerWeek,
            sessionMinutes: sessionMinutes,
            equipment: equipment,
            splitPreference: splitPreference,
            priorityMuscles: Array(priorityMuscles),
            avoidAreas: Array(avoidAreas)
        )
        draftInput = input
        do {
            if createsPlan {
                let plan = try PlanGenerator(catalog: catalogStore.catalog).generate(
                    PlanGeneratorInput(
                        base: input,
                        totalWeeks: planWeeks,
                        style: periodizationStyle,
                        deloadEveryWeeks: deloadEveryWeeks,
                        startDate: .now,
                        availableWeekdays: availableWeekdays
                    )
                )
                // Le programme produit est verifie par le meme validateur que
                // celui qui servira de garde-fou a toute proposition externe.
                let report = ProgramValidator(catalog: catalogStore.catalog)
                    .validate(program: plan.program, input: input)
                guard report.isAcceptable else {
                    errorMessage = report.blockingIssues.map(\.message).joined(separator: "\n")
                    return
                }
                generatedPlan = plan
                generatedDraft = plan.program
            } else {
                generatedPlan = nil
                generatedDraft = try RuleBasedGenerator(catalog: catalogStore.catalog).generate(input)
            }
        } catch {
            errorMessage = "Le programme n'a pas pu être généré : \(error.localizedDescription)"
        }
    }

    /// Jours declares par l'athlete dans son profil, s'il en a saisi.
    private var availableWeekdays: [Int] {
        ProfileStore.currentProfile(in: modelContext)?.availableWeekdays ?? []
    }

    private func regenerate() -> DraftProgram? {
        guard let draftInput else { return nil }
        return try? RuleBasedGenerator(catalog: catalogStore.catalog).generate(draftInput)
    }

    // MARK: - Composants

    private func optionCard(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(isSelected ? Theme.accent.opacity(0.15) : Theme.card)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Theme.accent : .clear, lineWidth: 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func nextButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.accent)
        .padding(.top, 8)
    }
}

private struct WizardStep<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// Nuage de chips multi-selection (utilise pour points faibles / zones a menager).
private struct ChipFlow: View {
    let items: [String]
    let label: (String) -> String
    let isSelected: (String) -> Bool
    let onToggle: (String) -> Void

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                Button {
                    onToggle(item)
                } label: {
                    Text(label(item))
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(isSelected(item) ? Theme.accent.opacity(0.2) : Theme.card)
                        .foregroundStyle(isSelected(item) ? Theme.accent : .primary)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(isSelected(item) ? Theme.accent : .clear, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

#Preview {
    GeneratorWizardView(onSaved: {})
        .environment(CatalogStore())
        .preferredColorScheme(.dark)
}
