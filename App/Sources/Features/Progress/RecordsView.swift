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

    @State private var showingPicker = false
    @State private var editingRecord: ExerciseRecord?
    @State private var editingIsNew = false

    var body: some View {
        List {
            ForEach(records) { record in
                Button {
                    editingIsNew = false
                    editingRecord = record
                } label: {
                    RecordRow(record: record)
                }
            }
            .onDelete(perform: delete)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .overlay {
            if records.isEmpty {
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
            }
        }
        .sheet(isPresented: $showingPicker) {
            ExercisePickerView { exercise in
                if let existing = records.first(where: { $0.exerciseId == exercise.id }) {
                    editingIsNew = false
                    editingRecord = existing
                } else {
                    editingIsNew = true
                    editingRecord = ExerciseRecord(exerciseId: exercise.id, displayName: exercise.nameFr)
                }
            }
        }
        .sheet(item: $editingRecord) { record in
            RecordEditSheet(record: record, isNew: editingIsNew)
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(records[index])
        }
        try? modelContext.save()
    }
}

private struct RecordRow: View {
    let record: ExerciseRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(record.displayName)
                .foregroundStyle(.primary)

            HStack(spacing: 12) {
                if let oneRepMax = record.oneRepMax {
                    Text("1RM \(WorkoutState.formatWeight(oneRepMax)) kg")
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
    @State private var showingDeleteConfirm = false

    init(record: ExerciseRecord, isNew: Bool) {
        self.record = record
        self.isNew = isNew
        _oneRepMaxText = State(initialValue: record.oneRepMax.map { WorkoutState.formatWeight($0) } ?? "")
        _maxRepsText = State(initialValue: record.maxReps.map(String.init) ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Exercice") {
                    Text(record.displayName)
                }
                Section("1RM estimé (kg)") {
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
                    try? modelContext.save()
                    dismiss()
                }
                Button("Annuler", role: .cancel) {}
            }
        }
    }

    private func save() {
        record.oneRepMax = Self.parsedDouble(oneRepMaxText)
        record.maxReps = Self.parsedInt(maxRepsText)
        record.updatedAt = .now
        if record.modelContext == nil {
            modelContext.insert(record)
        }
        try? modelContext.save()
        dismiss()
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
