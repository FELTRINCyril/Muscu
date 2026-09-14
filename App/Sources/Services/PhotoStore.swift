import Foundation
import SwiftData
import UIKit

enum PhotoStoreError: LocalizedError {
    case unreadableImage
    case tooLarge(Int)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .unreadableImage:
            return String(localized: "Cette image n’a pas pu être lue.")
        case .tooLarge(let bytes):
            let megabytes = Double(bytes) / 1_048_576
            return String(format: String(localized: "L’image dépasse la limite de %.0f Mo."), megabytes)
        case .writeFailed(let reason):
            return String(localized: "Enregistrement impossible : \(reason)")
        }
    }
}

/// Stockage des photos de progression sur le disque.
///
/// Les images ne vont PAS dans la base : une base SwiftData qui grossit de
/// plusieurs mega-octets par cliché deviendrait lente à migrer et à
/// sauvegarder. Le dossier est exclu de la sauvegarde iCloud : synchroniser
/// des photos demande un consentement séparé, qui n'existe pas encore.
@MainActor
enum PhotoStore {
    /// Cote maximal apres redimensionnement. Au-dela, on stocke des pixels
    /// que personne ne regardera jamais.
    static let maximumDimension: CGFloat = 1_600
    static let compressionQuality: CGFloat = 0.75
    /// Limite dure par photo, apres compression.
    static let maximumBytes = 4 * 1_024 * 1_024

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ProgressPhotos", isDirectory: true)
    }

    static func url(for assetName: String) -> URL {
        directory.appendingPathComponent(assetName)
    }

    /// Compresse puis ecrit l'image. Renvoie le nom de fichier et sa taille.
    @discardableResult
    static func write(_ imageData: Data) throws -> (assetName: String, byteCount: Int) {
        guard let image = UIImage(data: imageData) else { throw PhotoStoreError.unreadableImage }
        guard let encoded = compressed(image) else { throw PhotoStoreError.unreadableImage }
        guard encoded.count <= maximumBytes else { throw PhotoStoreError.tooLarge(maximumBytes) }

        do {
            try ensureDirectory()
            let name = UUID().uuidString + ".jpg"
            try encoded.write(to: url(for: name), options: .atomic)
            return (name, encoded.count)
        } catch {
            throw PhotoStoreError.writeFailed(error.localizedDescription)
        }
    }

    static func data(for assetName: String) -> Data? {
        try? Data(contentsOf: url(for: assetName))
    }

    /// Supprime le fichier. Ne renvoie pas d'erreur si le fichier a deja
    /// disparu : le resultat voulu est le meme.
    static func delete(assetName: String) {
        try? FileManager.default.removeItem(at: url(for: assetName))
    }

    static func totalBytes() -> Int {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return 0 }
        return names.reduce(0) { total, name in
            let attributes = try? FileManager.default.attributesOfItem(atPath: url(for: name).path)
            return total + ((attributes?[.size] as? Int) ?? 0)
        }
    }

    /// Supprime toutes les photos du disque. Utilise par la suppression de
    /// donnees : effacer la ligne sans effacer le fichier laisserait l'image
    /// sur l'appareil.
    static func deleteAll() {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        for name in names { delete(assetName: name) }
    }

    // MARK: - Interne

    private static func ensureDirectory() throws {
        var directory = directory
        guard !FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // Exclu de la sauvegarde : les photos restent sur l'appareil tant que
        // l'utilisateur n'a pas consenti a leur synchronisation.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? directory.setResourceValues(values)
    }

    private static func compressed(_ image: UIImage) -> Data? {
        let size = image.size
        let largestSide = max(size.width, size.height)
        guard largestSide > 0 else { return nil }

        let scale = min(1, maximumDimension / largestSide)
        guard scale < 1 else { return image.jpegData(compressionQuality: compressionQuality) }

        let target = CGSize(width: size.width * scale, height: size.height * scale)

        // Echelle 1 EXPLICITE : par defaut le rendu suit l'ecran (2x ou 3x)
        // et produirait une image trois fois plus grande que la limite
        // demandee, donc un fichier trois fois plus lourd.
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1

        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: compressionQuality)
    }
}

/// Acces aux photos de progression enregistrees.
@MainActor
enum ProgressPhotoStore {
    static func photos(in context: ModelContext) -> [ProgressPhoto] {
        let descriptor = FetchDescriptor<ProgressPhoto>(sortBy: [SortDescriptor(\.takenAt, order: .reverse)])
        return ((try? context.fetch(descriptor)) ?? []).filter { $0.deletedAt == nil }
    }

    @discardableResult
    static func add(
        imageData: Data,
        takenAt: Date = .now,
        note: String = "",
        measurementId: UUID? = nil,
        in context: ModelContext
    ) throws -> ProgressPhoto {
        let written = try PhotoStore.write(imageData)
        let photo = ProgressPhoto(
            assetName: written.assetName,
            takenAt: takenAt,
            note: note,
            measurementId: measurementId,
            byteCount: written.byteCount
        )
        context.insert(photo)
        guard PersistenceSupport.save(context, action: "Enregistrement de la photo") else {
            // La ligne n'a pas ete enregistree : le fichier ne doit pas
            // rester orphelin sur le disque.
            PhotoStore.delete(assetName: written.assetName)
            throw PhotoStoreError.writeFailed("la photo n’a pas pu être enregistrée")
        }
        return photo
    }

    /// Suppression DEFINITIVE : la ligne et le fichier. Une photo effacee ne
    /// doit rien laisser derriere elle.
    static func delete(_ photo: ProgressPhoto, in context: ModelContext) {
        PhotoStore.delete(assetName: photo.assetName)
        context.delete(photo)
        _ = PersistenceSupport.save(context, action: "Suppression de la photo")
    }

    /// Fichiers presents sur le disque sans ligne correspondante : residus
    /// d'une suppression interrompue.
    static func orphanAssetNames(in context: ModelContext) -> [String] {
        let known = Set(photos(in: context).map(\.assetName))
        let names = (try? FileManager.default.contentsOfDirectory(atPath: PhotoStore.directory.path)) ?? []
        return names.filter { !known.contains($0) }
    }
}
