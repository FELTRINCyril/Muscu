import SwiftUI
import MuscuEngine

// Ecran plein ecran du chrono de repos entre deux series.
struct RestTimerView: View {
    let timer: RestTimer

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

                        // Meme libelle que le bandeau du deroule : decompte,
                        // puis depassement signe en couleur d'alerte.
                        Text(verbatim: timer.countdown()?.label ?? RestCountdown.clock(timer.remaining))
                            .timerFont()
                            .foregroundStyle(timer.isOvertime ? .orange : .white)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.4)
                            .frame(maxWidth: 260 - 14 * 2 - 24 * 2)
                            .padding(24)
                    }
                    .frame(width: 260, height: 260)

                    Spacer()

                    HStack(spacing: 16) {
                        Button("+30 s") {
                            timer.addThirtySeconds()
                        }
                        .buttonStyle(.bordered)
                        .tint(Theme.accent)

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
