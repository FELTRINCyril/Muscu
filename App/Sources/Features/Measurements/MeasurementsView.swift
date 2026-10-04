import SwiftUI
import SwiftData
import Charts
import MuscuEngine

// Mesures corporelles : séries temporelles facultatives, avec date, unité,
// source et commentaire. Rien n'est obligatoire et rien n'est déduit.
struct MeasurementsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.massUnit) private var massUnit

    @Query(
        filter: #Predicate<BodyMeasurement> { $0.deletedAt == nil },
        sort: \BodyMeasurement.measuredAt,
        order: .reverse
    )
    private var measurements: [BodyMeasurement]

    @State private var kind: BodyMeasurementKind = .bodyweight
    @State private var showingEditor = false

    var body: some View {
        List {
            Section {
                Picker("Mesure", selection: $kind) {
                    ForEach(Self.orderedKinds, id: \.self) { kind in
                        Text(Self.label(kind)).tag(kind)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("measurements.kindPicker")
            }

            if filtered.isEmpty {
                Section {
                    ContentUnavailableView(
                        "Aucune mesure",
                        systemImage: "ruler",
                        description: Text("Ajoutez une première valeur pour suivre son évolution.")
                    )
                }
            } else {
                Section("Évolution") {
                    chart
                    Text(textAlternative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Évolution de \(Self.label(kind)). \(textAlternative)")
                }

                Section("Valeurs") {
                    ForEach(filtered) { measurement in
                        row(measurement)
                    }
                    .onDelete(perform: delete)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        // Pas de `navigationTitle` ici : cette vue est un SEGMENT de l'onglet
        // Progression, pas un écran poussé. Poser un titre écraserait celui
        // du parent et casserait la navigation par onglets.
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingEditor = true
                } label: {
                    Label("Ajouter", systemImage: "plus")
                }
                .accessibilityIdentifier("measurements.add")
            }
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink {
                    ProgressPhotosView()
                } label: {
                    Label("Photos", systemImage: "photo.on.rectangle")
                }
                .accessibilityIdentifier("measurements.photos")
            }
        }
        .sheet(isPresented: $showingEditor) {
            MeasurementEditorView(kind: kind)
        }
    }

    private var chart: some View {
        Chart(filtered.reversed(), id: \.id) { measurement in
            LineMark(
                x: .value("Date", measurement.measuredAt),
                y: .value(Self.label(kind), measurement.displayValue(massUnit: massUnit))
            )
            .foregroundStyle(Theme.accent)
            PointMark(
                x: .value("Date", measurement.measuredAt),
                y: .value(Self.label(kind), measurement.value)
            )
            .foregroundStyle(Theme.accent)
        }
        .chartYAxisLabel(unitSymbol)
        .frame(height: 180)
        .accessibilityHidden(true)
    }

    private func row(_ measurement: BodyMeasurement) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("\(WeightFormatter.number(measurement.displayValue(massUnit: massUnit))) \(measurement.displayUnitSymbol(massUnit: massUnit))")
                    .font(.body.weight(.medium))
                Spacer()
                Text(Self.dateFormatter.string(from: measurement.measuredAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                Text(Self.sourceLabel(measurement.source))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if !measurement.notes.isEmpty {
                    Text("· \(measurement.notes)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var filtered: [BodyMeasurement] {
        measurements.filter { $0.kind == kind }
    }

    private var unitSymbol: String {
        filtered.first?.displayUnitSymbol(massUnit: massUnit) ?? (kind == .bodyweight ? massUnit.symbol : "cm")
    }

    private var textAlternative: String {
        guard let last = filtered.first, let first = filtered.last else {
            return String(localized: "Aucune valeur enregistrée.")
        }
        let unit = last.displayUnitSymbol(massUnit: massUnit)
        let start = WeightFormatter.number(first.displayValue(massUnit: massUnit))
        let end = WeightFormatter.number(last.displayValue(massUnit: massUnit))
        return "\(filtered.count) valeur(s), de \(start) \(unit) le \(Self.dateFormatter.string(from: first.measuredAt)) à \(end) \(unit) le \(Self.dateFormatter.string(from: last.measuredAt))."
    }

    /// Suppression logique : la mesure disparaît de l'app mais la suppression
    /// reste propagée aux autres appareils (cf. stratégie de fusion).
    private func delete(at offsets: IndexSet) {
        let ordered = filtered
        for index in offsets {
            ordered[index].deletedAt = .now
            ordered[index].updatedAt = .now
        }
        _ = PersistenceSupport.save(modelContext, action: "Suppression de la mesure")
    }

    static let orderedKinds: [BodyMeasurementKind] = [
        .bodyweight, .waist, .chest, .arm, .thigh, .hips, .calf, .neck, .bodyFatPercent,
    ]

    static func label(_ kind: BodyMeasurementKind) -> String {
        switch kind {
        case .bodyweight: return "Poids corporel"
        case .waist: return "Tour de taille"
        case .chest: return "Tour de poitrine"
        case .arm: return "Tour de bras"
        case .thigh: return "Tour de cuisse"
        case .hips: return "Tour de hanches"
        case .calf: return "Tour de mollet"
        case .neck: return "Tour de cou"
        case .bodyFatPercent: return "Masse grasse"
        case .custom: return "Mesure personnalisée"
        }
    }

    static func sourceLabel(_ source: MeasurementSource) -> String {
        switch source {
        case .manual: return "Saisie manuelle"
        case .healthKit: return "Apple Santé"
        case .imported: return "Importée"
        }
    }

    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

/// Saisie d'une mesure. La valeur est stockée dans son unité canonique
/// (kg, cm ou %) ; la source est toujours explicite.
struct MeasurementEditorView: View {
    let kind: BodyMeasurementKind

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.massUnit) private var massUnit

    @State private var text = ""
    @State private var measuredAt = Date.now
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Valeur", text: $text)
                            .keyboardType(.decimalPad)
                            .accessibilityIdentifier("measurement.value")
                        Text(unitSymbol)
                            .foregroundStyle(.secondary)
                    }
                    DatePicker("Date", selection: $measuredAt, displayedComponents: [.date])
                } header: {
                    Text(MeasurementsView.label(kind))
                } footer: {
                    Text("La valeur est saisie en \(unitSymbol). Elle reste sur cet appareil sauf si vous exportez vos données.")
                }

                Section("Commentaire") {
                    TextField("Optionnel", text: $notes, axis: .vertical)
                        .lineLimit(1...3)
                }
            }
            .navigationTitle("Nouvelle mesure")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }
                        .disabled(value == nil)
                        .accessibilityIdentifier("measurement.save")
                }
            }
        }
    }

    private var value: Double? {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        guard let parsed = Double(normalized), parsed.isFinite, parsed > 0 else { return nil }
        return parsed
    }

    private var unitSymbol: String {
        switch kind {
        case .bodyweight: return massUnit.symbol
        case .bodyFatPercent: return "%"
        case .custom: return ""
        default: return "cm"
        }
    }

    private func save() {
        guard let value else { return }
        // Stockage canonique : une masse saisie en livres est enregistree en kg.
        let canonical = kind == .bodyweight ? massUnit.toKilograms(value) : value
        let measurement = BodyMeasurement(
            kindRaw: kind.rawValue,
            measuredAt: measuredAt,
            value: canonical,
            sourceRaw: MeasurementSource.manual.rawValue,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        modelContext.insert(measurement)
        if PersistenceSupport.save(modelContext, action: "Enregistrement de la mesure") {
            dismiss()
        }
    }
}
