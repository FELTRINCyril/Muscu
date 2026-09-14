import SwiftUI

/// Saisie d'une séance à la montre : poids, répétitions, série suivante.
///
/// Volontairement minimale. Une montre sert à enregistrer vite, pas à
/// reproduire l'application : le téléphone reste la source de vérité.
struct WatchWorkoutView: View {
    let sessionName: String

    @Environment(WatchConnectivityService.self) private var connectivity
    @Environment(\.dismiss) private var dismiss

    @State private var startedAt = Date.now
    @State private var exerciseName = "Exercice"
    @State private var weight: Double = 20
    @State private var reps: Int = 10
    @State private var recorded: [WatchSetPayload] = []
    @State private var isSent = false

    var body: some View {
        List {
            Section {
                Stepper(value: $weight, in: 0...400, step: 2.5) {
                    Text("\(weight, format: .number.precision(.fractionLength(0...1))) kg")
                        .font(.headline)
                }
                Stepper(value: $reps, in: 1...100) {
                    Text("\(reps) répétitions")
                        .font(.headline)
                }
                Button("Valider la série") { record() }
                    .disabled(isSent)
            } header: {
                Text(sessionName)
            }

            if !recorded.isEmpty {
                Section {
                    ForEach(Array(recorded.enumerated()), id: \.offset) { index, set in
                        Text("Série \(index + 1) · \(set.weightKilograms, format: .number.precision(.fractionLength(0...1))) kg × \(set.reps)")
                            .font(.caption)
                    }
                } header: {
                    Text("Enregistré")
                }
            }

            Section {
                Button(isSent ? "Envoyée" : "Terminer et envoyer") { finish() }
                    .disabled(recorded.isEmpty || isSent)
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
    }

    private func record() {
        recorded.append(WatchSetPayload(
            exerciseName: exerciseName,
            setIndex: recorded.count,
            weightKilograms: weight,
            reps: reps
        ))
    }

    private func finish() {
        let payload = WatchSessionPayload(
            sessionName: sessionName,
            startedAt: startedAt,
            durationSeconds: max(1, Int(Date.now.timeIntervalSince(startedAt))),
            sets: recorded
        )
        connectivity.send(payload)
        isSent = true
    }
}
