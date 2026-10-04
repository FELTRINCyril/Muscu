import SwiftUI
import SwiftData
import MuscuEngine

// Profil de l'athlete : ce que le generateur et les regles de progression
// utilisent pour s'adapter.
//
// Tout est facultatif. L'application reste entierement utilisable sans
// profil ; les informations de sante sont clairement separees et ne sont
// jamais obligatoires.
struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext

    // Le profil est lu par une requete, pas par un @State : un @State qui
    // contient un modele SwiftData ne declenche AUCUN rafraichissement quand
    // ce modele change, et l'ecran resterait figé sur d'anciennes valeurs.
    @Query(filter: #Predicate<AthleteProfile> { $0.deletedAt == nil }, sort: \AthleteProfile.createdAt)
    private var profiles: [AthleteProfile]

    private var profile: AthleteProfile? { profiles.first }

    var body: some View {
        Form {
            if let profile {
                ProfileFormSections(profile: profile)
            } else {
                Section {
                    ContentUnavailableView(
                        "Aucun profil",
                        systemImage: "person.crop.circle",
                        description: Text("Le profil aide le générateur et les règles de progression à s'adapter. Il reste facultatif.")
                    )
                    Button("Créer mon profil") {
                        ProfileStore.ensureProfile(in: modelContext)
                        _ = PersistenceSupport.save(modelContext, action: "Création du profil")
                    }
                    .accessibilityIdentifier("profile.create")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Profil")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            profile?.touch()
            _ = PersistenceSupport.save(modelContext, action: "Enregistrement du profil")
        }
    }
}

/// Formulaire du profil. Prend le modele en `@Bindable` STOCKE : c'est ce qui
/// permet a l'ecran de refleter immediatement chaque modification.
private struct ProfileFormSections: View {
    @Bindable var profile: AthleteProfile
    @Environment(CatalogStore.self) private var catalogStore
    @State private var showingExclusionPicker = false

    var body: some View {
        Section("Identité") {
            TextField("Prénom (optionnel)", text: $profile.firstName)
        }

        Section {
            Picker("Objectif principal", selection: Binding(
                get: { profile.primaryGoal },
                set: { profile.primaryGoal = $0 }
            )) {
                ForEach(Goal.allCases, id: \.self) { goal in
                    Text(Self.goalLabel(goal)).tag(goal)
                }
            }

            Picker("Expérience", selection: Binding(
                get: { profile.experience },
                set: { profile.experience = $0 }
            )) {
                Text("Débutant").tag(Experience.beginner)
                Text("Intermédiaire").tag(Experience.intermediate)
                Text("Avancé").tag(Experience.advanced)
            }

            Picker("Matériel", selection: Binding(
                get: { profile.equipment },
                set: { profile.equipment = $0 }
            )) {
                Text("Salle complète").tag(TrainingEquipment.fullGym)
                Text("Matériel à la maison").tag(TrainingEquipment.homeGym)
                Text("Poids du corps").tag(TrainingEquipment.bodyweight)
            }
        } header: {
            Text("Entraînement")
        }

        Section {
            ForEach(Self.weekdays, id: \.value) { weekday in
                Toggle(weekday.label, isOn: Binding(
                    get: { profile.availableWeekdays.contains(weekday.value) },
                    set: { isOn in
                        var days = Set(profile.availableWeekdays)
                        if isOn { days.insert(weekday.value) } else { days.remove(weekday.value) }
                        profile.availableWeekdays = days.sorted()
                    }
                ))
            }
        } header: {
            Text("Jours disponibles")
        } footer: {
            Text("Le générateur place les séances sur ces jours. Sans sélection, il les répartit automatiquement.")
        }

        Section {
            Stepper("Durée minimale : \(profile.sessionMinutesMinimum) min", value: Binding(
                get: { profile.sessionMinutesMinimum },
                set: { newValue in
                    profile.sessionMinutesMinimum = newValue
                    if profile.sessionMinutesMaximum < newValue { profile.sessionMinutesMaximum = newValue }
                }
            ), in: 15...180, step: 5)
            Stepper("Durée maximale : \(profile.sessionMinutesMaximum) min", value: Binding(
                get: { profile.sessionMinutesMaximum },
                set: { newValue in
                    profile.sessionMinutesMaximum = newValue
                    if profile.sessionMinutesMinimum > newValue { profile.sessionMinutesMinimum = newValue }
                }
            ), in: 15...180, step: 5)
        } header: {
            Text("Durée de séance")
        }

        Section {
            Picker("Unité de charge", selection: Binding(
                get: { profile.massUnit },
                set: { newUnit in
                    // Les paliers suivent l'unite : un athlete en livres
                    // charge des disques de 2,5 / 5 / 10 lb, pas de 1,25 kg.
                    profile.availableIncrementsKilograms = Self.convertedIncrements(
                        profile.availableIncrementsKilograms,
                        to: newUnit
                    )
                    profile.massUnit = newUnit
                }
            )) {
                Text("Kilogrammes").tag(MassUnit.kilograms)
                Text("Livres").tag(MassUnit.pounds)
            }
            ForEach(Self.increments(for: profile.massUnit), id: \.self) { increment in
                Toggle("Palier de \(WeightFormatter.string(kilograms: increment, unit: profile.massUnit))", isOn: Binding(
                    get: { profile.availableIncrementsKilograms.contains(increment) },
                    set: { isOn in
                        var values = Set(profile.availableIncrementsKilograms)
                        if isOn { values.insert(increment) } else { values.remove(increment) }
                        // Au moins un palier doit rester disponible, sinon
                        // aucune progression de charge n'est calculable.
                        profile.availableIncrementsKilograms = values.isEmpty
                            ? [profile.massUnit.defaultIncrementKilograms]
                            : values.sorted()
                    }
                ))
            }
        } header: {
            Text("Charges disponibles")
        } footer: {
            Text("Les charges sont toujours stockées en kilogrammes ; l'unité choisie change l'affichage et la saisie.")
        }

        Section {
            Picker("Règle de progression", selection: Binding(
                get: { Self.ruleKey(profile.defaultProgressionRule) },
                set: { profile.defaultProgressionRule = Self.rule(forKey: $0, increment: profile.nearestAvailableIncrement(to: 2.5)) }
            )) {
                ForEach(Self.ruleOptions, id: \.key) { option in
                    Text(option.label).tag(option.key)
                }
            }
        } header: {
            Text("Progression par défaut")
        } footer: {
            Text("Chaque exercice peut définir sa propre règle. Une proposition n'est jamais appliquée sans votre accord.")
        }

        Section {
            MeasurementField(
                label: "Taille",
                unit: "cm",
                value: Binding(get: { profile.heightCentimeters }, set: { profile.heightCentimeters = $0 })
            )
            MeasurementField(
                label: "Poids de référence",
                unit: profile.massUnit.symbol,
                value: Binding(
                    get: { profile.bodyweightKilograms.map(profile.massUnit.fromKilograms) },
                    set: { profile.bodyweightKilograms = $0.map(profile.massUnit.toKilograms) }
                )
            )
        } header: {
            Text("Mesures (facultatives)")
        } footer: {
            Text("Le poids de référence sert à calculer correctement le tonnage des exercices au poids du corps, lestés ou assistés.")
        }

        Section {
            ChipToggleFlow(
                items: Self.avoidAreas,
                isSelected: { profile.avoidAreas.contains($0.key) },
                onToggle: { area in
                    var values = Set(profile.avoidAreas)
                    if values.contains(area.key) { values.remove(area.key) } else { values.insert(area.key) }
                    profile.avoidAreas = values.sorted()
                }
            )
        } header: {
            Text("Zones à ménager")
        } footer: {
            Text("Ces zones filtrent la sélection d'exercices. Ce n'est pas un avis médical : en cas de douleur ou de blessure, consultez un professionnel de santé.")
        }

        exclusionsSection
    }

    /// Exercices que le générateur ne doit jamais proposer.
    ///
    /// Le champ existait sur le profil et le moteur savait le respecter —
    /// mais aucun écran ne permettait de le remplir, et l'assistant ne le
    /// transmettait pas. Le réglage était inatteignable de bout en bout.
    @ViewBuilder
    private var exclusionsSection: some View {
        Section {
            if profile.excludedExerciseIds.isEmpty {
                Text("Aucun exercice exclu.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("profile.noExclusion")
            } else {
                ForEach(profile.excludedExerciseIds, id: \.self) { identifier in
                    Text(exerciseName(for: identifier))
                        .accessibilityIdentifier("profile.exclusion")
                }
                .onDelete { offsets in
                    profile.excludedExerciseIds.remove(atOffsets: offsets)
                    profile.touch()
                }
            }

            Button {
                showingExclusionPicker = true
            } label: {
                Label("Exclure un exercice", systemImage: "nosign")
            }
            .accessibilityIdentifier("profile.addExclusion")
        } header: {
            Text("Exercices exclus")
        } footer: {
            Text("Le générateur ne proposera jamais ces exercices. Balayez une ligne pour retirer une exclusion.")
        }
        .sheet(isPresented: $showingExclusionPicker) {
            ExercisePickerView { identifier, _ in
                if !profile.excludedExerciseIds.contains(identifier) {
                    profile.excludedExerciseIds.append(identifier)
                    profile.touch()
                }
            }
        }
    }

    /// Nom lisible d'un exercice exclu. Un identifiant de catalogue affiché
    /// tel quel ne dirait rien à personne.
    private func exerciseName(for identifier: String) -> String {
        catalogStore.exercise(id: identifier)?.nameFr ?? identifier
    }

    // MARK: - Options

    private static let weekdays: [(value: Int, label: String)] = [
        (2, "Lundi"), (3, "Mardi"), (4, "Mercredi"), (5, "Jeudi"),
        (6, "Vendredi"), (7, "Samedi"), (1, "Dimanche"),
    ]

    /// Paliers proposes, en kg canonique, exprimes dans l'unite choisie.
    static func increments(for unit: MassUnit) -> [Double] {
        switch unit {
        case .kilograms: return [1.25, 2.5, 5]
        case .pounds: return [2.5, 5, 10].map(MassUnit.pounds.toKilograms)
        }
    }

    /// Ramene chaque palier declare au palier le plus proche de la nouvelle
    /// unite, pour qu'un changement d'unite ne laisse aucune case cochee
    /// invisible.
    static func convertedIncrements(_ values: [Double], to unit: MassUnit) -> [Double] {
        let candidates = increments(for: unit)
        let converted = Set(values.compactMap { value in
            candidates.min { abs($0 - value) < abs($1 - value) }
        })
        return converted.isEmpty ? [unit.defaultIncrementKilograms] : converted.sorted()
    }

    private static let avoidAreas: [(key: String, label: String)] = [
        ("lower back", "Lombaires"),
        ("knees", "Genoux"),
        ("shoulders", "Épaules"),
        ("wrists", "Poignets"),
        ("neck", "Nuque"),
    ]

    private static let ruleOptions: [(key: String, label: String)] = [
        ("double", "Double progression"),
        ("linear", "Charge fixe à chaque réussite"),
        ("reps", "Progression en répétitions"),
        ("sets", "Progression en séries"),
        ("effort", "Cible d'effort (RIR)"),
        ("none", "Aucune"),
    ]

    private static func ruleKey(_ rule: ProgressionRule) -> String {
        switch rule {
        case .doubleProgression: return "double"
        case .linearLoad: return "linear"
        case .repsProgression: return "reps"
        case .setsProgression: return "sets"
        case .effortTarget: return "effort"
        case .percentOneRepMax, .assistedOrWeighted, .timeProgression: return "double"
        case .none: return "none"
        }
    }

    private static func rule(forKey key: String, increment: Double) -> ProgressionRule {
        switch key {
        case "linear": return .linearLoad(incrementKilograms: increment, requiredSuccesses: 1)
        case "reps": return .repsProgression(step: 1, maximumReps: 20)
        case "sets": return .setsProgression(step: 1, maximumSets: 5)
        case "effort": return .effortTarget(targetRepsInReserve: 2, incrementKilograms: increment)
        case "none": return .none
        default: return .doubleProgression(incrementKilograms: increment, requiredSuccesses: 1)
        }
    }

    private static func goalLabel(_ goal: Goal) -> String {
        switch goal {
        case .hypertrophy: return "Prise de masse"
        case .strength: return "Force"
        case .fatLoss: return "Perte de poids"
        case .endurance: return "Endurance"
        case .pullUpProgress: return "Progression tractions"
        case .calisthenics: return "Calisthenics"
        }
    }
}

/// Champ numerique optionnel : vide signifie « non renseigne », jamais zero.
private struct MeasurementField: View {
    let label: String
    let unit: String
    @Binding var value: Double?

    @State private var text: String = ""

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField("—", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 100)
                .onChange(of: text) { _, newValue in
                    // Le texte affiche est arrondi : le relire tel quel
                    // reecrirait une valeur simplement consultee.
                    guard newValue != Self.formatted(value) else { return }
                    let normalized = newValue.replacingOccurrences(of: ",", with: ".")
                    value = normalized.isEmpty ? nil : Double(normalized)
                }
            Text(unit)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            text = Self.formatted(value)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) en \(unit)")
    }

    private static func formatted(_ value: Double?) -> String {
        value.map { WeightFormatter.number($0) } ?? ""
    }
}

private struct ChipToggleFlow: View {
    let items: [(key: String, label: String)]
    let isSelected: ((key: String, label: String)) -> Bool
    let onToggle: ((key: String, label: String)) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items, id: \.key) { item in
                Toggle(item.label, isOn: Binding(
                    get: { isSelected(item) },
                    set: { _ in onToggle(item) }
                ))
            }
        }
    }
}
