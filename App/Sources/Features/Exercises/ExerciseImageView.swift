import SwiftUI

// Affiche l'image d'un exercice depuis le cache disque (ImageStore), avec
// telechargement a la demande et repli silencieux sur un placeholder.
struct ExerciseImageView: View {
    let imagePath: String?

    @State private var phase: Phase = .loading

    private enum Phase {
        case loading
        case loaded(UIImage)
        case failed
    }

    var body: some View {
        ZStack {
            Theme.card

            switch phase {
            case .loading:
                ProgressView()
            case .loaded(let uiImage):
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            case .failed:
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: imagePath) {
            await load()
        }
    }

    private func load() async {
        guard let imagePath else {
            phase = .failed
            return
        }

        // Si pas encore en cache, on affiche le spinner pendant le telechargement.
        phase = ImageStore.shared.isCached(imagePath) ? phase : .loading

        do {
            let url = try await ImageStore.shared.localURL(for: imagePath)
            if let data = try? Data(contentsOf: url), let uiImage = UIImage(data: data) {
                phase = .loaded(uiImage)
            } else {
                phase = .failed
            }
        } catch {
            phase = .failed
        }
    }
}

#Preview {
    ExerciseImageView(imagePath: nil)
        .frame(width: 200, height: 200)
        .preferredColorScheme(.dark)
}
