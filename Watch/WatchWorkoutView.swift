import SwiftUI

/// Séance à la montre seule, quand l'iPhone est injoignable.
///
/// Volontairement minimale : exercice choisi dans la prochaine séance
/// (son VRAI nom, reçu de l'iPhone), poids, répétitions, série suivante.
/// La séance part ensuite vers l'iPhone, qui la conserve une seule fois
/// dans l'historique. Si Santé est active dans Muscu, la montre enregistre
/// aussi la séance Santé ; l'iPhone la relie à la séance importée.
struct WatchWorkoutView: View {
    let route: AutonomousRoute

    @Environment(WatchConnectivityService.self) private var connectivity
    @Environment(WatchHealthSession.self) private var health

    /// Identifiant frappé à la montre : celui de la séance dans
    /// l'historique ET celui que porte l'entraînement Santé.
    @State private var payloadId = UUID()
    @State private var startedAt = Date.now
    @State private var exerciseIndex = 0
    /// Charge dans l'unité affichée (celle du profil iPhone).
    @State private var weight: Double = 20
    @State private var reps: Int = 10
    @State private var recorded: [WatchSetPayload] = []
    @State private var isSent = false
    @State private var isSending = false

    /// Exercices proposés : ceux de la prochaine séance, et un exercice
    /// libre pour tout le reste.
    private var choices: [WatchPlannedExercise] {
        var list = route.exercises
        list.append(WatchPlannedExercise(
            id: "free",
            name: String(localized: "Exercice libre"),
            setCount: 3,
            weightKilograms: nil,
            reps: nil
        ))
        return list
    }

    private var selected: WatchPlannedExercise {
        choices[min(exerciseIndex, choices.count - 1)]
    }

    var body: some View {
        List {
            Section {
                Picker("Exercice", selection: $exerciseIndex) {
                    ForEach(Array(choices.enumerated()), id: \.offset) { index, exercise in
                        Text(exercise.name).tag(index)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 60)
                .disabled(isSent)

                Text("Série \(setsDone(for: selected) + 1)/\(max(selected.setCount, setsDone(for: selected) + 1))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Stepper(value: $weight, in: 0...unit.maximum, step: unit.step) {
                    Text("\(weight, format: .number.precision(.fractionLength(0...1))) \(unit.symbol)")
                        .font(.headline)
                }
                Stepper(value: $reps, in: 1...100) {
                    Text("\(reps) répétitions")
                        .font(.headline)
                }
                Button("Valider la série") { record() }
                    .disabled(isSent)
            } header: {
                Text(route.sessionName)
            }

            if !recorded.isEmpty {
                Section {
                    ForEach(Array(recorded.enumerated()), id: \.offset) { _, set in
                        Text("\(set.exerciseName) · \(unit.fromKilograms(set.weightKilograms), format: .number.precision(.fractionLength(0...1))) \(unit.symbol) × \(set.reps)")
                            .font(.caption)
                    }
                } header: {
                    Text("Enregistré")
                }
            }

            if health.isRecording, health.workoutId == payloadId {
                Section {
                    HStack {
                        if let bpm = health.heartRate {
                            Label("\(Int(bpm))", systemImage: "heart.fill")
                                .foregroundStyle(.red)
                        }
                        if let kcal = health.activeEnergyKilocalories {
                            Label("\(Int(kcal)) kcal", systemImage: "flame.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                    .font(.caption.monospacedDigit())
                } header: {
                    Text("Santé")
                }
            }

            Section {
                Button(isSent ? "Envoyée" : "Terminer et envoyer") { finish() }
                    .disabled(recorded.isEmpty || isSent || isSending)
            } footer: {
                Text(isSent
                     ? "La séance part vers l’iPhone. Elle n’y sera ajoutée qu’une seule fois, même si l’envoi est rejoué."
                     : "La séance sera envoyée à l’iPhone, qui la conservera dans l’historique.")
            }

            if let error = connectivity.lastError {
                Section {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle("Séance")
        .onAppear {
            applyPlannedValues()
            startHealthIfAllowed()
        }
        .onChange(of: exerciseIndex) { _, _ in applyPlannedValues() }
        .onDisappear {
            // Quittée sans envoi : rien n'est enregistré dans Santé non plus.
            guard !isSent, health.workoutId == payloadId else { return }
            Task { await health.discard() }
        }
    }

    private var unit: WatchMassUnit {
        connectivity.unit
    }

    private func setsDone(for exercise: WatchPlannedExercise) -> Int {
        recorded.filter { $0.exerciseName == exercise.name }.count
    }

    /// Valeurs du programme, quand elles sont connues ; sinon la dernière
    /// saisie est conservée — jamais une charge inventée.
    private func applyPlannedValues() {
        if let kilograms = selected.weightKilograms {
            weight = min(unit.maximum, (unit.fromKilograms(kilograms) / unit.step).rounded() * unit.step)
        }
        if let plannedReps = selected.reps {
            reps = min(100, max(1, plannedReps))
        }
    }

    private func startHealthIfAllowed() {
        guard connectivity.plan.healthEnabled, !health.isRecording, !isSent else { return }
        let id = payloadId
        Task { await health.start(workoutId: id, mirrorToPhone: false) }
    }

    private func record() {
        recorded.append(WatchSetPayload(
            exerciseName: selected.name,
            setIndex: setsDone(for: selected),
            weightKilograms: unit.toKilograms(weight),
            reps: reps
        ))
    }

    private func finish() {
        isSending = true
        let id = payloadId
        let start = startedAt
        let sets = recorded
        let name = route.sessionName
        Task {
            var payload = WatchSessionPayload(
                id: id,
                sessionName: name,
                startedAt: start,
                durationSeconds: max(1, Int(Date.now.timeIntervalSince(start))),
                sets: sets
            )
            if health.isRecording, health.workoutId == id {
                let result = await health.finish(endDate: .now, externalId: id)
                payload.healthWorkoutIdentifier = result.identifier
                payload.cardio = result.cardio
            }
            connectivity.send(payload)
            isSent = true
            isSending = false
        }
    }
}
