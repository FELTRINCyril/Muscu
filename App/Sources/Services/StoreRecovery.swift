import Foundation
import UniformTypeIdentifiers
import SwiftUI
import SwiftData

/// Recuperation d'un store local illisible (schema inattendu, fichier
/// corrompu). Le principe est toujours le meme : ne JAMAIS supprimer le
/// fichier d'origine, mais permettre a l'utilisateur d'en sortir une copie
/// avant toute decision.
enum StoreRecovery {
    /// Emplacement REEL du store : celui de la configuration par defaut que
    /// recoit le `ModelContainer` de l'application. Avec le groupe
    /// d'applications (`group.com.cyril.Muscu`), SwiftData range la base
    /// dans le conteneur du groupe (Library/Application Support/
    /// default.store), pas dans l'Application Support de l'application :
    /// un chemin recompose a la main viserait un fichier qui n'existe pas.
    static var storeURL: URL {
        ModelConfiguration().url
    }

    /// Fichiers reellement presents pour ce store : la base et ses journaux
    /// SQLite, qui peuvent contenir les ecritures les plus recentes.
    static var existingStoreFiles: [URL] {
        let base = storeURL
        return ["", "-wal", "-shm"]
            .map { URL(fileURLWithPath: base.path + $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    static var storeExists: Bool { !existingStoreFiles.isEmpty }

    /// Taille totale des fichiers du store, pour informer l'utilisateur.
    static var totalBytes: Int {
        existingStoreFiles.reduce(0) { partial, url in
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            return partial + ((attributes?[.size] as? Int) ?? 0)
        }
    }

    enum RecoveryError: LocalizedError {
        case noStoreFound

        var errorDescription: String? {
            switch self {
            case .noStoreFound:
                return String(localized: "Aucune base locale n’a été trouvée sur cet appareil.")
            }
        }
    }

    /// Copie les fichiers du store dans un dossier temporaire, pret a etre
    /// partage. L'original n'est jamais deplace ni modifie.
    static func makeRecoveryCopy(now: Date = .now) throws -> [URL] {
        let files = existingStoreFiles
        guard !files.isEmpty else { throw RecoveryError.noStoreFound }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("muscu-recuperation-\(formatter.string(from: now))", isDirectory: true)

        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        var copies: [URL] = []
        for file in files {
            let destination = folder.appendingPathComponent(file.lastPathComponent)
            try FileManager.default.copyItem(at: file, to: destination)
            copies.append(destination)
        }
        return copies
    }
}

/// Document minimal servant a proposer la copie de secours via l'export
/// systeme, sans dependre d'un type de fichier reconnu par iOS.
struct RecoveryStoreDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
