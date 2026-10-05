import SwiftUI
import SwiftData
import MuscuEngine

/// Lieux d'entrainement et inventaire de materiel.
struct PlacesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PlaceProfile.name) private var places: [PlaceProfile]

    @State private var editing: PlaceProfile?

    private var activePlaces: [PlaceProfile] {
        places.filter { $0.deletedAt == nil }
    }

    var body: some View {
        List {
            Section {
                if activePlaces.isEmpty {
                    Text("Aucun lieu. Sans lieu déclaré, aucun exercice n’est masqué.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(activePlaces, id: \.id) { place in
                    Button {
                        editing = place
                    } label: {
                        row(place)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: delete)
            } footer: {
                Text("Un inventaire vide ne filtre rien. Le poids du corps reste toujours disponible, quel que soit le lieu.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Lieux et matériel")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editing = PlaceStore.create(name: "Nouveau lieu", kind: .gym, in: modelContext)
                } label: {
                    Label("Ajouter", systemImage: "plus")
                }
                .accessibilityIdentifier("places.add")
            }
        }
        .sheet(item: $editing) { place in
            PlaceEditorView(place: place)
        }
    }

    private func row(_ place: PlaceProfile) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(place.name.isEmpty ? "Lieu" : place.name)
                if place.isDefault {
                    Text("Par défaut")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.accent.opacity(0.2))
                        .foregroundStyle(Theme.accent)
                        .clipShape(Capsule())
                }
            }
            Text(subtitle(place))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func subtitle(_ place: PlaceProfile) -> String {
        let count = place.inventory.items.count
        let inventory = count == 0 ? "inventaire non renseigné" : "\(count) matériel(s)"
        return "\(place.displayKind) · \(inventory)"
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            PlaceStore.delete(activePlaces[index], in: modelContext)
        }
    }
}

/// Edition d'un lieu et de son inventaire.
struct PlaceEditorView: View {
    @Bindable var place: PlaceProfile

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(CatalogStore.self) private var catalogStore
    @Environment(\.massUnit) private var massUnit

    @State private var items: [EquipmentAvailability] = []
    @State private var isAddingEquipment = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nom", text: $place.name)
                        .accessibilityIdentifier("place.name")
                    Picker("Type", selection: kindSelection) {
                        ForEach(PlaceKind.allCases, id: \.self) { kind in
                            Text(label(kind)).tag(kind)
                        }
                    }
                    .accessibilityIdentifier("place.kind")
                    Toggle("Lieu par défaut", isOn: defaultBinding)
                        .accessibilityIdentifier("place.default")
                }

                Section {
                    if items.isEmpty {
                        Text("Aucun matériel déclaré : tous les exercices restent proposés.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach($items) { $item in
                        equipmentRow($item)
                    }
                    .onDelete { offsets in
                        items.remove(atOffsets: offsets)
                    }
                    Button("Ajouter un matériel") { isAddingEquipment = true }
                        .accessibilityIdentifier("place.addEquipment")
                } header: {
                    Text("Inventaire")
                } footer: {
                    Text("Charges minimale, maximale et incrément servent à proposer des charges réellement disponibles ici.")
                }

                Section {
                    TextField("Notes", text: $place.notes, axis: .vertical)
                }
            }
            .navigationTitle(place.name.isEmpty ? "Lieu" : place.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminé") { save() }
                        .accessibilityIdentifier("place.done")
                }
            }
            .onAppear { items = place.inventory.items }
            .sheet(isPresented: $isAddingEquipment) {
                equipmentPicker
            }
        }
    }

    private func equipmentRow(_ item: Binding<EquipmentAvailability>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(FrenchLabels.equipment(item.wrappedValue.equipmentId))
                .font(.subheadline.weight(.semibold))
            HStack {
                numberField("Min", value: item.minimumLoad)
                numberField("Max", value: item.maximumLoad)
                numberField("Pas", value: item.increment)
            }
        }
        .padding(.vertical, 2)
    }

    private func numberField(_ title: String, value: Binding<Double?>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 2) {
                Text(title)
                Text(verbatim: "(\(massUnit.symbol))")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            // Saisie dans l'unite du profil, stockage en kg canonique.
            TextField(
                "—",
                text: Binding(
                    get: { value.wrappedValue.map { WeightFormatter.number(kilograms: $0, unit: massUnit) } ?? "" },
                    set: { text in
                        let cleaned = text.replacingOccurrences(of: ",", with: ".")
                        value.wrappedValue = cleaned.isEmpty ? nil : Double(cleaned).map(massUnit.toKilograms)
                    }
                )
            )
            .keyboardType(.decimalPad)
            .textFieldStyle(.roundedBorder)
        }
    }

    private var equipmentPicker: some View {
        NavigationStack {
            List(catalogStore.equipments, id: \.self) { equipment in
                Button {
                    if !items.contains(where: { $0.equipmentId == equipment }) {
                        items.append(EquipmentAvailability(equipmentId: equipment))
                    }
                    isAddingEquipment = false
                } label: {
                    Text(FrenchLabels.equipment(equipment))
                }
            }
            .navigationTitle("Matériel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { isAddingEquipment = false }
                }
            }
        }
    }

    private var kindSelection: Binding<PlaceKind> {
        Binding(get: { place.kind }, set: { place.kind = $0 })
    }

    private var defaultBinding: Binding<Bool> {
        Binding(
            get: { place.isDefault },
            set: { isOn in
                if isOn {
                    PlaceStore.makeDefault(place, in: modelContext)
                } else {
                    place.isDefault = false
                }
            }
        )
    }

    private func label(_ kind: PlaceKind) -> String {
        switch kind {
        case .home: return "Domicile"
        case .gym: return "Salle"
        case .travel: return "Voyage"
        case .custom: return "Personnalisé"
        }
    }

    private func save() {
        place.inventory = EquipmentInventory(items: items)
        place.updatedAt = .now
        _ = PersistenceSupport.save(modelContext, action: "Enregistrement du lieu")
        dismiss()
    }
}
