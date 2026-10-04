import SwiftUI
import SwiftData
import MuscuEngine

// Liste des records (1RM estime / max repetitions) par exercice, avec ajout
// et edition manuels. La mise a jour automatique en fin de seance passe par
// RecordDetection + confirmation individuelle (cf. WorkoutSummaryView) :
// cette vue ne fait jamais d'ecriture silencieuse non plus.
struct RecordsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ExerciseRecord.displayName) private var records: [ExerciseRecord]
    /// Records TYPES (charge reelle, temps, tours, distance, tonnage de
    /// seance). Ils etaient enregistres par `PersonalBestUpdater` depuis la
    /// fin de seance, et aucun ecran ne les montrait.
    ///
    /// Le tri secondaire et le filtrage des suppressions logiques sont faits
    /// en Swift : un `@Query` combinant predicat et plusieurs descripteurs
    /// de tri depasse le budget de typage du compilateur ici.
    @Query(sort: \PersonalBest.displayName) private var storedPersonalBests: [PersonalBest]

    private var personalBests: [PersonalBest] {
        storedPersonalBests.filter { $0.deletedAt == nil }
    }

    // L'item de la sheet d'edition porte lui-meme isNew : un seul @State a
    // poser, aucune desynchronisation possible entre le record edite et son
    // statut nouveau/existant.
    private struct EditingTarget: Identifiable {
        let record: ExerciseRecord
        let isNew: Bool
        var id: PersistentIdentifier { record.id }
    }

    @State private var showingPicker = false
    @State private var editing: EditingTarget?
    @State private var pendingPick: (id: String, displayName: String)?

    var body: some View {
        List {
            Section {
                manualRecords
            } footer: {
                if !records.isEmpty {
                    Text("Ces deux valeurs pilotent les charges en pourcentage. Vous pouvez les corriger à la main.")
                }
            }

            typedRecordsSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .overlay {
            if records.isEmpty && personalBests.isEmpty {
                ContentUnavailableView(
                    "Aucun record",
                    systemImage: "trophy",
                    description: Text("Vos records de 1RM et de répétitions apparaîtront ici au fil des séances.")
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingPicker = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("records.addButton")
            }
        }
        // La selection est memorisee (pendingPick) puis traitee dans
        // onDismiss : poser editingRecord pendant que la sheet du picker est
        // encore presentee ferait entrer en concurrence les deux .sheet de
        // cette vue, et SwiftUI abandonne alors la presentation de l'editeur.
        .sheet(isPresented: $showingPicker, onDismiss: handlePendingPick) {
            ExercisePickerView { id, displayName in
                pendingPick = (id, displayName)
            }
        }
        .sheet(item: $editing) { target in
            RecordEditSheet(record: target.record, isNew: target.isNew)
        }
    }

    /// Records saisissables : 1RM estimé et max de répétitions. Ce sont eux
    /// qui pilotent les charges en pourcentage, donc ils restent corrigeables
    /// à la main.
    private var manualRecords: some View {
        ForEach(records) { record in
            Button {
                editing = EditingTarget(record: record, isNew: false)
            } label: {
                RecordRow(record: record)
            }
            .swipeActions(edge: .leading) {
                NavigationLink {
                    OneRepMaxTestView(exerciseId: record.exerciseId, displayName: record.displayName)
                } label: {
                    Label("Tester", systemImage: "figure.strengthtraining.traditional")
                }
                .tint(.orange)
            }
            .contextMenu {
                NavigationLink {
                    OneRepMaxTestView(exerciseId: record.exerciseId, displayName: record.displayName)
                } label: {
                    Label("Tester mon 1RM", systemImage: "figure.strengthtraining.traditional")
                }
            }
        }
        .onDelete(perform: delete)
    }


    /// Records typés : ils sont RECALCULÉS depuis l'historique, qui reste la
    /// source de vérité. On ne les édite donc pas ici — les corriger à la
    /// main ferait diverger l'affichage de ce qui a réellement été fait.
    @ViewBuilder
    private var typedRecordsSection: some View {
        if !personalBests.isEmpty {
            Section {
                ForEach(groupedBests) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.name)
                            .font(.subheadline.weight(.semibold))
                        ForEach(group.bests) { best in
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(best.kind.displayName)
                                    if let configuration = best.configurationLabel {
                                        Text(configuration)
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                Spacer(minLength: 8)
                                Text(best.formattedValue)
                                    .monospacedDigit()
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .accessibilityIdentifier("records.typed")
                }
            } header: {
                Text("Records par type")
            } footer: {
                Text("Recalculés depuis vos séances : charge réellement portée, meilleur temps, tours complets, distance et tonnage de séance.")
            }
        }
    }

    /// Un type nomme plutot qu'un tuple : le compilateur Swift n'arrive pas
    /// a typer en temps raisonnable un tuple construit dans deux fermetures
    /// imbriquees.
    private struct BestGroup: Identifiable {
        let name: String
        let bests: [PersonalBest]
        var id: String { name }
    }

    private var groupedBests: [BestGroup] {
        let byExercise = Dictionary(grouping: personalBests, by: { $0.displayName })
        var groups: [BestGroup] = []
        for (name, bests) in byExercise {
            groups.append(BestGroup(name: name, bests: bests.sorted { $0.kindRaw < $1.kindRaw }))
        }
        return groups.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }


    private func handlePendingPick() {
        guard let pick = pendingPick else { return }
        pendingPick = nil
        if let existing = records.first(where: { $0.exerciseId == pick.id }) {
            editing = EditingTarget(record: existing, isNew: false)
        } else {
            editing = EditingTarget(
                record: ExerciseRecord(exerciseId: pick.id, displayName: pick.displayName),
                isNew: true
            )
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(records[index])
        }
        _ = PersistenceSupport.save(modelContext, action: "Suppression du record")
    }
}

private struct RecordRow: View {
    let record: ExerciseRecord
    @Environment(\.massUnit) private var massUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(record.displayName)
                .foregroundStyle(.primary)

            HStack(spacing: 12) {
                if let oneRepMax = record.oneRepMax {
                    Text("1RM \(WeightFormatter.string(kilograms: oneRepMax, unit: massUnit))")
                }
                if let maxReps = record.maxReps {
                    Text("Max \(maxReps) reps")
                }
            }
            .font(.subheadline)
            .foregroundStyle(Theme.accent)

            Text(Self.relativeDate(record.updatedAt))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // RelativeDateTimeFormatter arrondit les ecarts de quelques secondes de
    // facon ambigue ("dans 0 seconde" pour un record tout juste enregistre) :
    // en dessous d'une minute, on affiche explicitement "à l'instant".
    private static func relativeDate(_ date: Date) -> String {
        guard abs(date.timeIntervalSinceNow) >= 60 else { return "À l'instant" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}

// Formulaire d'edition d'un record : 1RM et max reps sont saisis librement
// (un exercice peut avoir les deux, l'un des deux, ou aucun tant qu'il n'est
// pas enregistre). Un record juste cree via le picker n'est insere dans le
// contexte qu'a l'enregistrement (isNew), pour ne jamais laisser un record
// vide trainer si l'utilisateur annule.
private struct RecordEditSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let record: ExerciseRecord
    let isNew: Bool

    @State private var oneRepMaxText: String
    @State private var maxRepsText: String
    /// Unite de saisie, figee a l'ouverture. Le texte initial est garde pour
    /// ne pas reecrire un 1RM simplement affiche : un aller-retour par les
    /// livres l'arrondirait.
    private let unit: MassUnit
    private let initialOneRepMaxText: String
    @State private var showingDeleteConfirm = false
    @State private var validationMessage: String?

    init(record: ExerciseRecord, isNew: Bool) {
        self.record = record
        self.isNew = isNew
        let unit = WeightFormatter.preferredUnit
        let initialText = record.oneRepMax.map { WeightFormatter.number(kilograms: $0, unit: unit) } ?? ""
        self.unit = unit
        self.initialOneRepMaxText = initialText
        _oneRepMaxText = State(initialValue: initialText)
        _maxRepsText = State(initialValue: record.maxReps.map(String.init) ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Exercice") {
                    Text(record.displayName)
                }
                Section("1RM estimé (\(unit.symbol))") {
                    TextField("Ex : 100", text: $oneRepMaxText)
                        .keyboardType(.decimalPad)
                }
                Section("Max répétitions (poids du corps)") {
                    TextField("Ex : 20", text: $maxRepsText)
                        .keyboardType(.numberPad)
                }
                if !isNew {
                    Section {
                        Button("Supprimer le record", role: .destructive) {
                            showingDeleteConfirm = true
                        }
                    }
                }
                if let validationMessage {
                    Section {
                        Text(validationMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(isNew ? "Nouveau record" : "Modifier le record")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }
                }
            }
            .confirmationDialog(
                "Supprimer ce record ?",
                isPresented: $showingDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Supprimer", role: .destructive) {
                    modelContext.delete(record)
                    _ = PersistenceSupport.save(modelContext, action: "Modification du record")
                    dismiss()
                }
                Button("Annuler", role: .cancel) {}
            }
        }
    }

    private func save() {
        let oneRepMax = oneRepMaxText == initialOneRepMaxText
            ? record.oneRepMax
            : Self.parsedDouble(oneRepMaxText).map(unit.toKilograms)
        let maxReps = Self.parsedInt(maxRepsText)
        guard oneRepMax != nil || maxReps != nil else {
            validationMessage = "Renseigne au moins un 1RM ou un maximum de répétitions supérieur à zéro."
            return
        }
        record.oneRepMax = oneRepMax
        record.maxReps = maxReps
        record.updatedAt = .now
        if record.modelContext == nil {
            modelContext.insert(record)
        }
        if PersistenceSupport.save(modelContext, action: "Enregistrement du record") {
            dismiss()
        }
    }

    private static func parsedDouble(_ text: String) -> Double? {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty, let value = Double(normalized), value > 0 else { return nil }
        return value
    }

    private static func parsedInt(_ text: String) -> Int? {
        guard let value = Int(text), value > 0 else { return nil }
        return value
    }
}

#Preview {
    NavigationStack {
        RecordsView()
    }
    .environment(CatalogStore())
    .modelContainer(for: ExerciseRecord.self, inMemory: true)
    .preferredColorScheme(.dark)
}
