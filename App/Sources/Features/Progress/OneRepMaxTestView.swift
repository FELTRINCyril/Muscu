import SwiftUI
import SwiftData
import MuscuEngine

/// Test de 1RM guidé : avertissement, protocole, puis enregistrement d'une
/// charge RÉELLEMENT portée.
///
/// L'application privilégie l'estimation : cet écran ne s'ouvre que si
/// l'utilisateur le demande, et il refuse de proposer un protocole quand il
/// n'a pas de référence fiable pour le construire.
struct OneRepMaxTestView: View {
    let exerciseId: String
    let displayName: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var hasAcknowledgedWarning = false
    @State private var validatedWeights: Set<Double> = []
    @State private var failedWeights: Set<Double> = []
    @State private var savedMessage: String?

    private var reference: Double? {
        OneRepMaxTestReference.value(exerciseId: exerciseId, in: modelContext)
    }

    private var increment: Double {
        ProfileStore.currentProfile(in: modelContext)?.nearestAvailableIncrement(to: 2.5) ?? 2.5
    }

    private var steps: [OneRepMaxTestStep] {
        OneRepMaxTest.protocolSteps(referenceOneRepMax: reference, increment: increment)
    }

    var body: some View {
        List {
            warningSection

            if steps.isEmpty {
                unavailableSection
            } else if hasAcknowledgedWarning {
                protocolSection
                resultSection
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Test de 1RM")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sections

    private var warningSection: some View {
        Section {
            Text(OneRepMaxTest.safetyWarning)
                .font(.callout)
                .accessibilityIdentifier("oneRepMaxTest.warning")

            if !steps.isEmpty {
                Toggle("J’ai lu et je choisis de tester", isOn: $hasAcknowledgedWarning)
                    .accessibilityIdentifier("oneRepMaxTest.acknowledge")
            }
        } header: {
            Text("Avant de commencer")
        }
    }

    private var unavailableSection: some View {
        Section {
            Text(unavailableMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("oneRepMaxTest.unavailable")
        } header: {
            Text("Protocole indisponible")
        }
    }

    private var unavailableMessage: String {
        guard let reference else {
            return "Aucune référence connue pour « \(displayName) ». Enregistrez d’abord quelques séries : l’estimation issue de vos performances sert de base au protocole."
        }
        return "La référence connue (\(WeightFormatter.number(reference)) kg) est trop faible pour justifier un test maximal : la montée en charge n’aurait pas assez de paliers."
    }

    private var protocolSection: some View {
        Section {
            ForEach(steps) { step in
                stepRow(step)
            }
        } header: {
            Text("Protocole")
        } footer: {
            Text("Construit à partir de votre référence de \(WeightFormatter.number(reference ?? 0)) kg, arrondi à vos paliers de \(WeightFormatter.number(increment)) kg. Arrêtez-vous dès qu’une tentative échoue : la suivante ne serait pas plus sûre.")
        }
    }

    private func stepRow(_ step: OneRepMaxTestStep) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(step.kind == .warmup ? "Montée en charge" : "Tentative")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(WeightFormatter.number(step.weightKilograms)) kg × \(step.reps)")
                    .font(.subheadline)
                    .foregroundStyle(Theme.accent)
            }
            Text("\(Int(step.fractionOfReference * 100)) % de la référence · repos conseillé \(step.restSeconds / 60) min")
                .font(.caption)
                .foregroundStyle(.secondary)

            if step.kind == .attempt {
                HStack {
                    Button("Réussie") {
                        validatedWeights.insert(step.weightKilograms)
                        failedWeights.remove(step.weightKilograms)
                    }
                    .buttonStyle(.bordered)
                    .tint(validatedWeights.contains(step.weightKilograms) ? Theme.accent : nil)

                    Button("Échouée") {
                        failedWeights.insert(step.weightKilograms)
                        validatedWeights.remove(step.weightKilograms)
                    }
                    .buttonStyle(.bordered)
                    .tint(failedWeights.contains(step.weightKilograms) ? .orange : nil)
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "\(step.kind == .warmup ? "Montée en charge" : "Tentative"), "
            + "\(WeightFormatter.number(step.weightKilograms)) kilogrammes, \(step.reps) répétition(s)"
        )
    }

    private var resultSection: some View {
        Section {
            if let best = OneRepMaxTest.result(validatedWeights: Array(validatedWeights)) {
                LabeledContent("Meilleure tentative validée", value: "\(WeightFormatter.number(best)) kg")
                Button("Enregistrer ce record") { save(best) }
                    .accessibilityIdentifier("oneRepMaxTest.save")
            } else {
                Text("Aucune tentative validée : rien ne sera enregistré.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let savedMessage {
                Text(savedMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("oneRepMaxTest.result")
            }
        } header: {
            Text("Résultat")
        } footer: {
            Text("La charge enregistrée est une performance MESURÉE, distincte d’un 1RM estimé à partir de séries de plusieurs répétitions.")
        }
    }

    private func save(_ weight: Double) {
        OneRepMaxTestReference.record(
            testedOneRepMax: weight,
            exerciseId: exerciseId,
            displayName: displayName,
            in: modelContext
        )
        savedMessage = "Record enregistré : \(WeightFormatter.number(weight)) kg, mesuré le \(Date.now.formatted(date: .abbreviated, time: .omitted))."
    }
}

/// Lecture de la référence et écriture du résultat d'un test de 1RM.
@MainActor
enum OneRepMaxTestReference {
    /// Référence de départ : le 1RM déjà connu pour cet exercice, estimé ou
    /// mesuré. `nil` quand rien n'est exploitable — on ne devine pas.
    static func value(exerciseId: String, in context: ModelContext) -> Double? {
        let records = (try? context.fetch(FetchDescriptor<ExerciseRecord>())) ?? []
        if let known = records.first(where: { $0.exerciseId == exerciseId })?.oneRepMax, known > 0 {
            return known
        }

        let bests = ((try? context.fetch(FetchDescriptor<PersonalBest>())) ?? [])
            .filter { $0.exerciseId == exerciseId && $0.deletedAt == nil }
        let candidates = bests
            .filter { $0.kind == .maxWeight || $0.kind == .estimatedOneRepMax }
            .map(\.value)
        return candidates.max()
    }

    /// Enregistre une charge réellement portée : record d'exercice mis à
    /// jour (c'est lui qui alimente les pourcentages du runner) et record
    /// typé `maxWeight` sur une répétition.
    static func record(
        testedOneRepMax weight: Double,
        exerciseId: String,
        displayName: String,
        in context: ModelContext,
        now: Date = .now
    ) {
        let records = (try? context.fetch(FetchDescriptor<ExerciseRecord>())) ?? []
        if let existing = records.first(where: { $0.exerciseId == exerciseId }) {
            // Un test remplace l'estimation même s'il est plus bas : une
            // valeur mesurée vaut mieux qu'une extrapolation optimiste.
            existing.oneRepMax = weight
            existing.displayName = displayName
        } else {
            context.insert(ExerciseRecord(exerciseId: exerciseId, displayName: displayName, oneRepMax: weight))
        }

        let bests = ((try? context.fetch(FetchDescriptor<PersonalBest>())) ?? [])
            .filter { $0.exerciseId == exerciseId && $0.deletedAt == nil && $0.kindRaw == PersonalBestKind.maxWeight.rawValue }
        if let best = bests.first(where: { $0.reps == 1 }) {
            if weight > best.value {
                best.value = weight
                best.achievedAt = now
                best.updatedAt = now
            }
        } else {
            let best = PersonalBest(
                exerciseId: exerciseId,
                displayName: displayName,
                kindRaw: PersonalBestKind.maxWeight.rawValue,
                value: weight,
                reps: 1,
                achievedAt: now
            )
            context.insert(best)
        }

        _ = PersistenceSupport.save(context, action: "Enregistrement du test de 1RM")
    }
}
