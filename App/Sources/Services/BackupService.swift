import Foundation
import SwiftData
import MuscuEngine

/// Sauvegardes de sécurité automatiques.
///
/// Un import en mode **remplacement** efface des données. La roadmap exige
/// qu'une sauvegarde soit créée AVANT, pour qu'aucune manipulation ne soit
/// irréversible.
@MainActor
enum BackupService {
    /// Dossier des sauvegardes automatiques, hors de portée de l'utilisateur
    /// mais inclus dans les sauvegardes de l'appareil.
    static var directory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("SauvegardesAutomatiques", isDirectory: true)
    }

    /// Nombre de sauvegardes automatiques conservées. Au-delà, la plus
    /// ancienne est supprimée : une sauvegarde de sécurité ne doit pas
    /// remplir le stockage de l'appareil.
    static let retainedBackups = 5

    enum BackupError: LocalizedError {
        case exportFailed(String)

        var errorDescription: String? {
            switch self {
            case .exportFailed(let details):
                return String(localized: "La sauvegarde de sécurité n'a pas pu être créée : \(details)")
            }
        }
    }

    /// Crée une sauvegarde complète au format v3 et renvoie son emplacement.
    @discardableResult
    static func createSafetyBackup(context: ModelContext, now: Date = .now) throws -> URL {
        let data: Data
        do {
            data = try ExportImport.exportAll(context: context)
        } catch {
            throw BackupError.exportFailed(error.localizedDescription)
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let url = directory.appendingPathComponent("muscu-avant-remplacement-\(formatter.string(from: now)).json")
        try data.write(to: url, options: .atomic)

        pruneOldBackups()
        return url
    }

    /// Sauvegardes disponibles, de la plus récente à la plus ancienne.
    static func existingBackups() -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        return contents
            .filter { $0.pathExtension == "json" }
            .sorted { lhs, rhs in
                let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhsDate > rhsDate
            }
    }

    private static func pruneOldBackups() {
        let backups = existingBackups()
        guard backups.count > retainedBackups else { return }
        for url in backups.dropFirst(retainedBackups) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

extension ExportImport {
    /// Mode d'import choisi par l'utilisateur.
    enum ImportMode: String, CaseIterable, Identifiable {
        /// Ajoute ce qui manque, ne touche pas à l'existant.
        case merge
        /// Remplace l'intégralité des données par celles du fichier.
        case replace

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .merge: return String(localized: "Fusionner")
            case .replace: return String(localized: "Remplacer")
            }
        }

        var explanation: String {
            switch self {
            case .merge:
                return String(localized: "Ajoute ce qui manque sans toucher à vos données actuelles. Réimporter deux fois le même fichier ne crée aucun doublon.")
            case .replace:
                return String(localized: "Efface les données de cet appareil et les remplace par celles du fichier. Une sauvegarde de sécurité est créée avant.")
            }
        }
    }

    /// Importe selon le mode choisi. En mode remplacement, une sauvegarde de
    /// sécurité est créée AVANT toute suppression : si l'import échoue, rien
    /// n'est perdu.
    @MainActor
    @discardableResult
    static func importAll(
        data: Data,
        context: ModelContext,
        mode: ImportMode,
        now: Date = .now
    ) throws -> (summary: ImportSummary, safetyBackup: URL?) {
        // Le fichier est validé d'abord : inutile de sauvegarder et de tout
        // effacer pour découvrir ensuite que l'archive est illisible.
        _ = try preview(data: data)

        switch mode {
        case .merge:
            let summary = try importAll(data: data, context: context)
            applyMergeRedirects(context: context)
            return (summary, nil)

        case .replace:
            let backup = try BackupService.createSafetyBackup(context: context, now: now)
            _ = try DataDeletion.deleteEverything(context: context)
            do {
                let summary = try importAll(data: data, context: context)
                applyMergeRedirects(context: context)
                return (summary, backup)
            } catch {
                // L'import a échoué après la suppression : on restaure
                // immédiatement la sauvegarde de sécurité.
                if let restored = try? Data(contentsOf: backup) {
                    _ = try? importAll(data: restored, context: context)
                }
                throw error
            }
        }
    }

    /// Une archive peut porter des fusions d'exercices (redirections), ou
    /// des seances qui designent encore un exercice fusionne ailleurs : les
    /// references sont reecrites vers l'exercice conserve. Sans effet si rien
    /// n'est a rediriger ; un echec d'ecriture est deja signale par
    /// `PersistenceSupport` et sera retente au lancement suivant.
    @MainActor
    private static func applyMergeRedirects(context: ModelContext) {
        ExerciseMergeService.applyPendingRedirects(in: context)
    }
}
