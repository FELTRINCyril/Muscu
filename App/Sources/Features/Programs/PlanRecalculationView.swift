import SwiftUI
import SwiftData
import MuscuEngine

/// Aperçu d'un recalcul des semaines à venir, appliqué seulement après
/// confirmation.
///
/// L'écran montre d'abord ce qui NE bougera pas : les semaines déjà
/// entamées. Un recalcul qui réécrirait le passé serait une perte de données
/// silencieuse.
struct PlanRecalculationView: View {
    @Bindable var plan: TrainingPlan

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var startDate = Date.now
    @State private var appliedMessage: String?

    private var preview: PlanRecalculationPreview {
        PlanRecalculationService.preview(
            for: plan,
            in: modelContext,
            firstFutureWeekStart: startDate
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DatePicker("Reprendre la semaine du", selection: $startDate, displayedComponents: [.date])
                        .accessibilityIdentifier("recalculate.startDate")
                } footer: {
                    Text("La première semaine à venir démarrera cette semaine-là ; les suivantes s’enchaînent de sept jours en sept jours.")
                }

                summarySection
                changesSection

                if let appliedMessage {
                    Section {
                        Text(appliedMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("recalculate.result")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Recalculer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Appliquer") { apply() }
                        .disabled(!preview.hasChanges)
                        .accessibilityIdentifier("recalculate.apply")
                }
            }
        }
    }

    private var summarySection: some View {
        Section {
            ForEach(Array(preview.rationale.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !preview.settledWeekNumbers.isEmpty {
                Text("Semaines intactes : " + preview.settledWeekNumbers.map(String.init).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
                    .accessibilityIdentifier("recalculate.settled")
            }
            if plan.periodizationStyle == nil {
                Text("Ce plan ne conserve pas son style de périodisation : les volumes et intensités des semaines à venir sont laissés tels quels, seules les dates sont réalignées.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Ce qui se passera")
        } footer: {
            Text("L’historique déjà enregistré n’est jamais modifié.")
        }
    }

    private var changesSection: some View {
        Section {
            if preview.changes.isEmpty {
                Text("Aucune semaine à venir.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(preview.changes) { change in
                VStack(alignment: .leading, spacing: 2) {
                    Text("Semaine \(change.number)")
                        .font(.subheadline.weight(.semibold))
                    if change.movesDates {
                        Text("\(Self.date.string(from: change.previousStartDate)) → \(Self.date.string(from: change.newStartDate)) (\(change.dayShift > 0 ? "+" : "")\(change.dayShift) j)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if change.changesLoad {
                        Text("Volume \(percent(change.previousVolumeMultiplier)) → \(percent(change.newVolumeMultiplier)), intensité \(percent(change.previousIntensityMultiplier)) → \(percent(change.newIntensityMultiplier))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !change.changesAnything {
                        Text("Inchangée.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        } header: {
            Text("Semaines à venir")
        }
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded())) %"
    }

    private func apply() {
        let result = PlanRecalculationService.apply(preview, to: plan, in: modelContext)
        appliedMessage = "Plan recalculé (version \(plan.version)) : \(result) séance(s) déplacée(s)."
    }

    private static let date: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.setLocalizedDateFormatFromTemplate("dMMM")
        return formatter
    }()
}
