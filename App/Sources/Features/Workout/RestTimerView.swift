import SwiftUI

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

                        Text(formattedTime(timer.remaining))
                            .font(Theme.timerFont)
                            .foregroundStyle(.white)
                            .monospacedDigit()
                            .minimumScaleFactor(0.5)
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

    private func formattedTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

#Preview {
    RestTimerView(timer: {
        let t = RestTimer()
        t.start(seconds: 90)
        return t
    }())
}
