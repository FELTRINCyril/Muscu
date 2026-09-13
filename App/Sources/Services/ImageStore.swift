import Foundation

// Cache disque borne des images d'exercices, telechargees depuis un snapshot
// immuable du depot free-exercise-db.
actor ImageStore {
    static let shared = ImageStore()

    // Snapshot correspondant au catalogue integre en juillet 2026.
    private static let sourceRevision = "b0eed061e1c832b3ed815fbaa4b45b3cdc14df49"
    private static let cdnBase = URL(string: "https://raw.githubusercontent.com/yuhonas/free-exercise-db/\(sourceRevision)/exercises/")!
    private static let maximumImageBytes: Int64 = 10 * 1_024 * 1_024
    static let maximumCacheBytes: Int64 = 250 * 1_024 * 1_024

    struct PrefetchResult: Sendable {
        let available: Int
        let downloaded: Int
        let failed: Int
        let total: Int
    }

    private let fileManager = FileManager.default
    private let session: URLSession
    private var inFlight: [String: Task<URL, Error>] = [:]
    private var knownCacheSize: Int64?

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
        guard Self.isSafePath(imagePath) else { throw ImageStoreError.invalidPath }
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
        guard Self.isSafePath(imagePath) else { return false }
        return FileManager.default.fileExists(atPath: localFileURL(for: imagePath).path)
    }

    // Precharge une liste de chemins, ignore ceux deja en cache, tolere les echecs individuels.
    func prefetchAll(paths: [String], progress: @Sendable @escaping (Int, Int) -> Void) async -> PrefetchResult {
        let uniquePaths = Array(Set(paths)).sorted()
        let total = uniquePaths.count
        var completed = 0
        var available = 0
        var downloaded = 0
        var failed = 0
        progress(completed, total)

        for path in uniquePaths {
            if Task.isCancelled { break }
            if isCached(path) {
                available += 1
                completed += 1
                progress(completed, total)
                continue
            }
            do {
                _ = try await localURL(for: path)
                available += 1
                downloaded += 1
            } catch {
                failed += 1
            }
            completed += 1
            progress(completed, total)
        }
        return PrefetchResult(available: available, downloaded: downloaded, failed: failed, total: total)
    }

    // Taille totale du cache sur le disque, en octets.
    func cacheSizeBytes() -> Int64 {
        if let knownCacheSize { return knownCacheSize }
        guard let enumerator = fileManager.enumerator(
            at: storageRoot,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            knownCacheSize = 0
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
            total += Int64(values?.fileSize ?? 0)
        }
        knownCacheSize = total
        return total
    }

    func clearCache() throws {
        if fileManager.fileExists(atPath: storageRoot.path) {
            try fileManager.removeItem(at: storageRoot)
        }
        knownCacheSize = 0
    }

    // MARK: - Prive

    private func download(imagePath: String, to destination: URL) async throws -> URL {
        let remoteURL = Self.remoteURL(for: imagePath)
        let (tempURL, response) = try await session.download(from: remoteURL)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode),
              httpResponse.mimeType?.hasPrefix("image/") == true else {
            throw ImageStoreError.badResponse
        }
        let values = try tempURL.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values.fileSize, size > 0, Int64(size) <= Self.maximumImageBytes else {
            throw ImageStoreError.invalidSize
        }
        guard cacheSizeBytes() + Int64(size) <= Self.maximumCacheBytes else {
            throw ImageStoreError.cacheFull
        }

        let directory = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        // Ecriture atomique : on deplace le fichier temporaire vers la destination finale.
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: tempURL, to: destination)
        knownCacheSize = (knownCacheSize ?? 0) + Int64(size)

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

    private static func isSafePath(_ imagePath: String) -> Bool {
        guard !imagePath.isEmpty, !imagePath.hasPrefix("/") else { return false }
        return imagePath.split(separator: "/").allSatisfy { $0 != ".." && $0 != "." }
    }
}

enum ImageStoreError: LocalizedError {
    case cacheFull
    case badResponse
    case deallocated
    case invalidPath
    case invalidSize

    var errorDescription: String? {
        switch self {
        case .cacheFull: "Le cache d’images a atteint sa limite de 250 Mo. Videz-le avant de continuer."
        case .badResponse: "Le serveur n’a pas renvoyé une image valide."
        case .deallocated: "Le service d’images n’est plus disponible."
        case .invalidPath: "Le chemin de l’image est invalide."
        case .invalidSize: "L’image est vide ou dépasse la limite de 10 Mo."
        }
    }
}
