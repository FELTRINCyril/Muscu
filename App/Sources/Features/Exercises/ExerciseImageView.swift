import SwiftUI
import ImageIO

// Affiche l'image d'un exercice depuis le cache disque (ImageStore), avec
// telechargement a la demande et repli silencieux sur un placeholder.
struct ExerciseImageView: View {
    let imagePath: String?

    @State private var phase: Phase = .loading
    private static let memoryCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 100
        cache.totalCostLimit = 64 * 1_024 * 1_024
        return cache
    }()

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

        // Ne jamais conserver visuellement l'image du chemin precedent
        // pendant qu'une cellule recyclee charge sa nouvelle ressource.
        phase = .loading

        do {
            let url = try await ImageStore.shared.localURL(for: imagePath)
            let key = url.path as NSString
            if let cached = Self.memoryCache.object(forKey: key) {
                phase = .loaded(cached)
                return
            }
            let cgImage = await Task.detached(priority: .utility) {
                Self.downsampledImage(at: url, maximumPixelSize: 600)
            }.value
            if let cgImage {
                let uiImage = UIImage(cgImage: cgImage)
                Self.memoryCache.setObject(uiImage, forKey: key, cost: cgImage.bytesPerRow * cgImage.height)
                phase = .loaded(uiImage)
            } else {
                phase = .failed
            }
        } catch {
            phase = .failed
        }
    }

    nonisolated private static func downsampledImage(at url: URL, maximumPixelSize: Int) -> CGImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options) else { return nil }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions)
    }
}

#Preview {
    ExerciseImageView(imagePath: nil)
        .frame(width: 200, height: 200)
        .preferredColorScheme(.dark)
}
