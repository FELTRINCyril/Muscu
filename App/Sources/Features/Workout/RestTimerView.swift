import SwiftUI
import MuscuEngine

// Ecran plein ecran du chrono de repos entre deux series.
struct RestTimerView: View {
    let timer: RestTimer
    /// Ce qui suit le repos, quand c'est utile de l'annoncer (palier suivant
    /// d'une pyramide).
    var upNext: Text? = nil

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                VStack(spacing: 40) {
                    Spacer()

                    ZStack {
                        Circle()
                            .stroke(Theme.card, lineWidth: 14)

                        Circle()
                            .trim(from: 0, to: 1 - timer.progress)
                            .stroke(
                                Theme.accent,
                                style: StrokeStyle(lineWidth: 14, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 0.5), value: timer.progress)

                        // Decompte seul : a zero, le repos se termine et cet
                        // ecran disparait (pas de depassement affiche).
                        Text(verbatim: RestCountdown.clock(timer.remaining))
                            .timerFont()
                            .foregroundStyle(.white)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.4)
                            .frame(maxWidth: 260 - 14 * 2 - 24 * 2)
                            .padding(24)
                    }
                    .frame(width: 260, height: 260)

                    if let upNext {
                        upNext
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("rest.upNext")
                    }

                    Spacer()

                    // Memes reglages que la Live Activity et la montre :
                    // −15 s jusqu'a zero (le repos se termine), +15 s borne.
                    HStack(spacing: 16) {
                        Button("−15 s") {
                            timer.adjust(by: -RestAdjustment.stepSeconds)
                        }
                        .buttonStyle(.bordered)
                        .tint(Theme.accent)
                        .monospacedDigit()
                        .accessibilityLabel(Text("Retirer 15 secondes au repos"))
                        .accessibilityIdentifier("rest.minus15")

                        Button("+15 s") {
                            timer.adjust(by: RestAdjustment.stepSeconds)
                        }
                        .buttonStyle(.bordered)
                        .tint(Theme.accent)
                        .monospacedDigit()
                        .accessibilityLabel(Text("Ajouter 15 secondes au repos"))
                        .accessibilityIdentifier("rest.plus15")

                        Button("Passer") {
                            timer.skip()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                    }
                    .controlSize(.large)
                    .padding(.bottom, 40)
                }
                .padding()
            }
        }
    }

}

#Preview {
    RestTimerView(timer: {
        let t = RestTimer()
        t.start(seconds: 90)
        return t
    }())
}
