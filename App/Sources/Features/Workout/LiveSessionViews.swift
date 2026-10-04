import SwiftUI
import MuscuEngine

// Vues de la seance en direct (lot 2 des inspirations open source) :
// bandeau des dernieres seances, celebration d'un record et calculateur de
// disques. Toute la logique vit dans le moteur ; ces vues ne font que la
// presenter.

// MARK: - Libelles partages

enum LiveSessionText {
    /// « il y a 3 sem. », traduit ici : le moteur ne renvoie qu'une duree.
    static func age(_ age: PreviousSessionsStrip.RelativeAge) -> String {
        switch age {
        case .today: return String(localized: "Aujourd’hui")
        case .yesterday: return String(localized: "Hier")
        case .days(let days): return String(localized: "il y a \(days) j")
        case .weeks(let weeks): return String(localized: "il y a \(weeks) sem.")
        case .months(let months): return String(localized: "il y a \(months) mois")
        }
    }

    /// « 20 kg × 15, 9 » ; « × 12, 10 » sans charge (poids du corps).
    static func run(_ run: PreviousSessionsStrip.Run, unit: MassUnit) -> String {
        let reps = run.reps.map(String.init).joined(separator: ", ")
        guard run.weightKilograms > 0 else { return "× " + reps }
        return WeightFormatter.string(kilograms: run.weightKilograms, unit: unit) + " × " + reps
    }

    /// Lecture VoiceOver d'une suite : « 20 kg, 15, 9 répétitions ».
    static func runAccessibility(_ run: PreviousSessionsStrip.Run, unit: MassUnit) -> String {
        let reps = run.reps.map(String.init).joined(separator: ", ")
        guard run.weightKilograms > 0 else { return String(localized: "\(reps) répétitions") }
        let weight = WeightFormatter.string(kilograms: run.weightKilograms, unit: unit)
        return String(localized: "\(weight), \(reps) répétitions")
    }

    /// « 80 kg × 8 », ou « × 8 » sans charge.
    static func set(weightKilograms: Double, reps: Int, unit: MassUnit) -> String {
        guard weightKilograms > 0 else { return "× \(reps)" }
        return WeightFormatter.string(kilograms: weightKilograms, unit: unit) + " × \(reps)"
    }

    /// Disque avec deux decimales au besoin (1,25 kg).
    static func plate(_ value: Double, unit: MassUnit) -> String {
        WeightFormatter.number(value, maximumFractionDigits: 2) + " " + unit.symbol
    }
}

// MARK: - Bandeau des dernieres seances

/// Defilement horizontal des dernieres seances de l'exercice, la plus
/// recente a droite et visible d'emblee. Adapte d'UpLift
/// (`PrevSessionsStrip.swift`, MIT).
struct PreviousSessionsStripView: View {
    let entries: [PreviousSessionsStrip.Entry]

    @Environment(\.massUnit) private var massUnit

    var body: some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Dernières séances")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(entries) { entry in
                            card(entry)
                        }
                    }
                }
                .defaultScrollAnchor(.trailing)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("workout.previousSessions")
        }
    }

    private func card(_ entry: PreviousSessionsStrip.Entry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LiveSessionText.age(entry.age))
                .font(.caption2.weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            ForEach(Array(entry.runs.enumerated()), id: \.offset) { _, run in
                Text(verbatim: LiveSessionText.run(run, unit: massUnit))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .fixedSize()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minWidth: 96, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: entry))
    }

    private func accessibilityLabel(for entry: PreviousSessionsStrip.Entry) -> String {
        let runs = entry.runs.map { LiveSessionText.runAccessibility($0, unit: massUnit) }.joined(separator: " ; ")
        return LiveSessionText.age(entry.age) + " : " + runs
    }
}

// MARK: - Record en direct

/// Bandeau de celebration d'un record, pose au-dessus du deroule ET de
/// l'ecran de repos (qui s'ouvre aussitot la serie validee). Il se ferme
/// seul ; il n'ecrit rien.
struct LiveRecordBannerHost: View {
    let state: WorkoutState

    var body: some View {
        if let celebration = state.liveRecordCelebration {
            LiveRecordBanner(celebration: celebration) {
                state.dismissLiveRecordCelebration(id: celebration.id)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .task(id: celebration.id) {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard !Task.isCancelled else { return }
                state.dismissLiveRecordCelebration(id: celebration.id)
            }
        }
    }
}

struct LiveRecordBanner: View {
    let celebration: WorkoutState.LiveRecordCelebration
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.massUnit) private var massUnit
    @State private var isShown = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "trophy.fill")
                .font(.title2)
                .foregroundStyle(.yellow)
                .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? false : isShown)
            VStack(alignment: .leading, spacing: 2) {
                Text("Nouveau record !")
                    .font(.headline)
                Text(verbatim: detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Fermer")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.yellow.opacity(0.6), lineWidth: 1)
        )
        // Reduire les animations : apparition en fondu seulement, sans
        // rebond ni changement d'echelle.
        .scaleEffect(isShown || reduceMotion ? 1 : 0.85)
        .opacity(isShown ? 1 : 0)
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.35, dampingFraction: 0.6)) {
                isShown = true
            }
            AccessibilityNotification.Announcement(String(localized: "Nouveau record : \(detail)")).post()
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("workout.liveRecord")
    }

    private var detail: String {
        switch celebration.kind {
        case .estimatedOneRepMax(let new, let previous):
            let value = WeightFormatter.string(kilograms: new, unit: massUnit)
            let before = WeightFormatter.string(kilograms: previous, unit: massUnit)
            return String(localized: "\(celebration.exerciseName) — 1RM estimé \(value) (avant \(before))")
        case .maxLoad(let new, let previous):
            let value = WeightFormatter.string(kilograms: new, unit: massUnit)
            let before = WeightFormatter.string(kilograms: previous, unit: massUnit)
            return String(localized: "\(celebration.exerciseName) — charge \(value) (avant \(before))")
        }
    }
}

// MARK: - Calculateur de disques

/// Disques a mettre de chaque cote pour la charge saisie, selon la barre et
/// l'inventaire regles. Adapte d'Ischys (`PlateSheet.tsx`, MIT).
struct PlateCalculatorView: View {
    let targetKilograms: Double
    /// Reporte une charge chargeable voisine dans la saisie. Ne valide pas
    /// la serie.
    let onUse: (Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.massUnit) private var massUnit
    @State private var inventory: PlateInventory?

    var body: some View {
        NavigationStack {
            Form {
                if let inventory {
                    content(inventory)
                }
            }
            .navigationTitle("Disques")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
            .onAppear { inventory = WorkoutSettings.plateInventory(for: massUnit) }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func content(_ inventory: PlateInventory) -> some View {
        Section {
            LabeledContent("Charge visée", value: WeightFormatter.string(kilograms: targetKilograms, unit: massUnit))
            Picker("Barre", selection: Binding(
                get: { inventory.barWeight },
                set: { newValue in
                    var updated = inventory
                    updated.barWeight = newValue
                    WorkoutSettings.storePlateInventory(updated)
                    self.inventory = updated
                }
            )) {
                ForEach(barChoices(inventory), id: \.self) { weight in
                    Text(verbatim: LiveSessionText.plate(weight, unit: massUnit)).tag(weight)
                }
            }
            .accessibilityIdentifier("plates.bar")
        }

        switch PlateMath.solve(targetKilograms: targetKilograms, inventory: inventory) {
        case .exact(let load):
            Section("Par côté") {
                PlateLoadDetail(load: load)
            }
        case .rounded(let below, let above, let step):
            Section {
                if let below { option(below) }
                if let above { option(above) }
            } header: {
                Text("Charge impossible avec vos disques")
            } footer: {
                if step > 0 {
                    Text("Le plus petit disque impose des pas de \(LiveSessionText.plate(step, unit: massUnit)).")
                } else {
                    Text("Aucun disque disponible : seule la barre est chargeable.")
                }
            }
        case .belowBar(let barWeight):
            Section {
                Text("La charge visée est inférieure au poids de la barre (\(LiveSessionText.plate(barWeight, unit: massUnit))).")
                    .foregroundStyle(.secondary)
            }
        }

        Section {
            NavigationLink {
                PlateInventoryView()
                    .onDisappear { self.inventory = WorkoutSettings.plateInventory(for: massUnit) }
            } label: {
                Label("Mes disques", systemImage: "slider.horizontal.3")
            }
        }
    }

    private func option(_ load: PlateLoad) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            PlateLoadDetail(load: load)
            Button {
                onUse(load.totalKilograms)
                dismiss()
            } label: {
                Text("Utiliser \(LiveSessionText.plate(load.totalWeight, unit: massUnit))")
            }
            .buttonStyle(.bordered)
            .tint(Theme.accent)
        }
    }

    /// Barres usuelles, plus celle deja reglee si elle sort de la liste.
    private func barChoices(_ inventory: PlateInventory) -> [Double] {
        var choices = PlateInventory.commonBarWeights(for: inventory.unit)
        if !choices.contains(inventory.barWeight) { choices.append(inventory.barWeight) }
        return choices.sorted()
    }
}

/// Detail d'un chargement : total, par cote, dessin et liste des disques.
private struct PlateLoadDetail: View {
    let load: PlateLoad

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Total")
                Spacer()
                Text(verbatim: LiveSessionText.plate(load.totalWeight, unit: load.unit))
                    .monospacedDigit()
                    .fontWeight(.semibold)
            }
            HStack {
                Text("Par côté")
                Spacer()
                Text(verbatim: LiveSessionText.plate(load.perSideWeight, unit: load.unit))
                    .monospacedDigit()
            }
            .foregroundStyle(.secondary)
            PlateDrawing(plates: load.eachPlate)
            Text(verbatim: stackLabel)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var stackLabel: String {
        guard !load.plates.isEmpty else { return String(localized: "Barre seule") }
        return load.plates
            .map { "\($0.count) × " + LiveSessionText.plate($0.weight, unit: load.unit) }
            .joined(separator: "  ·  ")
    }
}

/// Dessin d'un cote de la barre : manchon puis disques, du plus lourd au
/// plus leger. La taille suit une courbe aplatie et non le poids reel : un
/// 25 et un 1,25 different d'un facteur 20 en poids, pas en diametre.
private struct PlateDrawing: View {
    let plates: [Double]

    var body: some View {
        let largest = max(plates.max() ?? 1, 1)
        HStack(spacing: 2) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.gray)
                .frame(width: 24, height: 10)
            ForEach(Array(plates.enumerated()), id: \.offset) { _, weight in
                let ratio = weight / largest
                RoundedRectangle(cornerRadius: 3)
                    .fill(Theme.accent.opacity(0.5 + 0.5 * ratio))
                    .frame(
                        width: max(6, 16 * pow(ratio, 0.45)),
                        height: max(26, 84 * pow(ratio, 0.42))
                    )
            }
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.gray)
                .frame(width: 30, height: 10)
            Spacer(minLength: 0)
        }
        .frame(height: 88)
        .accessibilityHidden(true)
    }
}

// MARK: - Inventaire de disques

/// Reglage des disques possedes et du poids de barre, dans l'unite du
/// profil. Un inventaire par unite.
struct PlateInventoryView: View {
    @Environment(\.massUnit) private var massUnit
    @State private var inventory: PlateInventory = .standard(for: .kilograms)
    @State private var newPlateText = ""
    @State private var didLoad = false

    var body: some View {
        Form {
            Section {
                Picker("Barre par défaut", selection: Binding(
                    get: { inventory.barWeight },
                    set: { inventory.barWeight = $0; save() }
                )) {
                    ForEach(barChoices, id: \.self) { weight in
                        Text(verbatim: LiveSessionText.plate(weight, unit: massUnit)).tag(weight)
                    }
                }
            } footer: {
                Text("Modifiable aussi depuis le calculateur, pendant la séance.")
            }

            Section {
                ForEach(inventory.plates.indices, id: \.self) { index in
                    let plate = inventory.plates[index]
                    Stepper(
                        value: Binding(
                            get: { inventory.plates[index].pairs },
                            set: { inventory.plates[index].pairs = $0; save() }
                        ),
                        in: 0...20
                    ) {
                        HStack {
                            Text(verbatim: LiveSessionText.plate(plate.weight, unit: massUnit))
                            Spacer()
                            Text("\(plate.pairs) paires")
                                .foregroundStyle(plate.pairs == 0 ? .tertiary : .secondary)
                                .monospacedDigit()
                        }
                    }
                }
                .onDelete { offsets in
                    inventory.plates.remove(atOffsets: offsets)
                    save()
                }

                HStack {
                    TextField("Autre disque (\(massUnit.symbol))", text: $newPlateText)
                        .keyboardType(.decimalPad)
                    Button("Ajouter") { addPlate() }
                        .disabled(parsedNewPlate == nil)
                }
            } header: {
                Text("Disques possédés")
            } footer: {
                Text("Nombre de paires : les disques se chargent des deux côtés. Zéro paire = disque absent de votre salle.")
            }

            Section {
                Button("Rétablir le jeu standard", role: .destructive) {
                    WorkoutSettings.resetPlateInventory(for: massUnit)
                    inventory = WorkoutSettings.plateInventory(for: massUnit)
                }
            }
        }
        .navigationTitle("Disques et barre")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            inventory = WorkoutSettings.plateInventory(for: massUnit)
        }
    }

    private var barChoices: [Double] {
        var choices = PlateInventory.commonBarWeights(for: massUnit)
        if !choices.contains(inventory.barWeight) { choices.append(inventory.barWeight) }
        return choices.sorted()
    }

    private var parsedNewPlate: Double? {
        let value = Double(newPlateText.replacingOccurrences(of: ",", with: "."))
        guard let value, value.isFinite, value > 0, value <= 100 else { return nil }
        return value
    }

    private func addPlate() {
        guard let weight = parsedNewPlate else { return }
        if let index = inventory.plates.firstIndex(where: { abs($0.weight - weight) < 0.000_1 }) {
            inventory.plates[index].pairs = max(1, inventory.plates[index].pairs)
        } else {
            inventory.plates.append(.init(weight: weight, pairs: 1))
        }
        newPlateText = ""
        save()
        inventory = inventory.sanitized()
    }

    private func save() {
        WorkoutSettings.storePlateInventory(inventory)
    }
}
