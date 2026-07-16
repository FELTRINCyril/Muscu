import Foundation

// Cache disque des images d'exercices, telechargees depuis le CDN GitHub
// (free-exercise-db) et jamais purgees par l'app.
actor ImageStore {
    static let shared = ImageStore()

    private static let cdnBase = URL(string: "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/")!

    private let fileManager = FileManager.default
    private let session: URLSession
    private var inFlight: [String: Task<URL, Error>] = [:]

    private var storageRoot: URL { Self.storageRootURL }

    private static let storageRootURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("ExerciseImages", isDirectory: true)
    }()

    init(session: URLSession = .shared) {
        self.session = session
    }

    // Chemin local d'une image, en la telechargeant si necessaire.
    func localURL(for imagePath: String) async throws -> URL {
        let destination = localFileURL(for: imagePath)

        if fileManager.fileExists(atPath: destination.path) {
            return destination
        }

        if let existing = inFlight[imagePath] {
            return try await existing.value
        }

        let task = Task<URL, Error> { [weak self] in
            guard let self else { throw ImageStoreError.deallocated }
            return try await self.download(imagePath: imagePath, to: destination)
        }
        inFlight[imagePath] = task

        defer { inFlight[imagePath] = nil }

        return try await task.value
    }

    // Verification purement disque, sans acces a l'etat de l'actor (rapide, utilisable depuis une vue).
    nonisolated func isCached(_ imagePath: String) -> Bool {
        FileManager.default.fileExists(atPath: localFileURL(for: imagePath).path)
    }

    // Precharge une liste de chemins, ignore ceux deja en cache, tolere les echecs individuels.
    func prefetchAll(paths: [String], progress: @Sendable @escaping (Int, Int) -> Void) async {
        let total = paths.count
        var done = 0
        progress(done, total)

        for path in paths {
            if isCached(path) {
                done += 1
                progress(done, total)
                continue
            }
            do {
                _ = try await localURL(for: path)
            } catch {
                // Echec tolere : on continue avec les images suivantes.
            }
            done += 1
            progress(done, total)
        }
    }

    // Taille totale du cache sur le disque, en octets.
    func cacheSizeBytes() -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: storageRoot,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
            total += Int64(values?.fileSize ?? 0)
        }
        return total
    }

    // MARK: - Prive

    private func download(imagePath: String, to destination: URL) async throws -> URL {
        let remoteURL = Self.remoteURL(for: imagePath)
        let (tempURL, response) = try await session.download(from: remoteURL)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw ImageStoreError.badResponse
        }

        let directory = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        // Ecriture atomique : on deplace le fichier temporaire vers la destination finale.
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: tempURL, to: destination)

        return destination
    }

    private nonisolated func localFileURL(for imagePath: String) -> URL {
        Self.storageRootURL.appendingPathComponent(imagePath)
    }

    private static func remoteURL(for imagePath: String) -> URL {
        let components = imagePath.split(separator: "/").map(String.init)
        var url = cdnBase
        for component in components {
            url.appendPathComponent(component)
        }
        return url
    }
}

enum ImageStoreError: Error {
    case badResponse
    case deallocated
}
