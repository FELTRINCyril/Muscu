import Foundation
import SwiftData
import MuscuEngine
#if canImport(UIKit)
import UIKit
#endif

/// Sauvegardes automatiques, a la demande de l'utilisateur (desactivees par
/// defaut).
///
/// Au plus une fois par jour — au passage en arriere-plan ou apres une
/// seance terminee — l'export JSON complet (`ExportImport.exportAll`, le
/// meme que « Exporter mes donnees ») est ecrit dans le dossier Documents de
/// l'application, visible dans l'app Fichiers. Les `AutoBackupPolicy.
/// defaultRetainedCount` plus recentes sont gardees. Les photos de
/// progression restent exclues, comme dans l'export.
///
/// La restauration passe par l'import existant en mode Remplacer, qui cree
/// deja une sauvegarde de securite et la restaure en cas d'echec.
@MainActor
enum AutoBackupService {
    static let enabledKey = "autoBackup.enabled"
    static let lastBackupKey = "autoBackup.lastBackupAt"

    /// Desactivee par defaut : ecrire des fichiers dans un dossier visible
    /// de l'utilisateur doit rester un choix explicite.
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// Faux quand l'application tourne sur le conteneur de secours en
    /// memoire (store illisible au lancement) : sauvegarder ce conteneur
    /// VIDE puis appliquer la rotation effacerait, jour apres jour, les
    /// bonnes sauvegardes. Rien n'est alors ecrit.
    static var isStoreReliable = true

    static var lastBackupAt: Date? {
        get { UserDefaults.standard.object(forKey: lastBackupKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastBackupKey) }
    }

    /// `Documents/Sauvegardes` : visible dans Fichiers (« Sur mon iPhone »
    /// › Muscu) grace a `UIFileSharingEnabled` et
    /// `LSSupportsOpeningDocumentsInPlace`.
    static var directory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("Sauvegardes", isDirectory: true)
    }

    struct Backup: Identifiable, Equatable {
        let url: URL
        let date: Date
        let sizeBytes: Int64

        var id: URL { url }
    }

    // MARK: - Écriture

    /// Ecrit une sauvegarde si elle est activee et due. Ne leve jamais : un
    /// echec est journalise (Diagnostic) et retente a la prochaine occasion.
    @discardableResult
    static func runIfDue(context: ModelContext, now: Date = .now, calendar: Calendar = .current) -> URL? {
        guard isEnabled, isStoreReliable, AutoBackupPolicy.isDue(lastBackupAt: lastBackupAt, now: now, calendar: calendar) else { return nil }
        #if canImport(UIKit)
        // Au passage en arriere-plan, le systeme laisse quelques secondes :
        // on les demande explicitement pour finir l'ecriture.
        let task = UIApplication.shared.beginBackgroundTask(withName: "Sauvegarde automatique")
        defer {
            if task != .invalid { UIApplication.shared.endBackgroundTask(task) }
        }
        #endif
        do {
            return try backUpNow(context: context, now: now)
        } catch {
            DiagnosticsCenter.record(.transfer, code: "backup.automatic.failed", error: error)
            return nil
        }
    }

    /// Ecrit une sauvegarde immediatement, puis applique la rotation.
    @discardableResult
    static func backUpNow(context: ModelContext, now: Date = .now) throws -> URL {
        guard isStoreReliable else { throw BackupUnavailable() }
        let data = try ExportImport.exportAll(context: context)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(AutoBackupPolicy.fileName(for: now))
        try data.write(to: url, options: .atomic)
        lastBackupAt = now
        prune()
        DiagnosticsCenter.record(.transfer, .info, code: "backup.automatic.written", detail: "\(data.count) octets")
        return url
    }

    /// Sauvegardes automatiques presentes, de la plus recente a la plus
    /// ancienne. Un fichier depose a la main dans le dossier n'est pas liste.
    static func backups() -> [Backup] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        let contents = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
        return contents
            .filter { AutoBackupPolicy.isAutomaticBackup(fileName: $0.lastPathComponent) }
            .map { url in
                let values = try? url.resourceValues(forKeys: Set(keys))
                return Backup(
                    url: url,
                    date: values?.contentModificationDate ?? .distantPast,
                    sizeBytes: Int64(values?.fileSize ?? 0)
                )
            }
            .sorted { $0.date != $1.date ? $0.date > $1.date : $0.url.lastPathComponent > $1.url.lastPathComponent }
    }

    /// Restaure une sauvegarde : import en mode Remplacer (sauvegarde de
    /// securite prealable, restauration automatique si l'import echoue).
    static func restore(
        _ backup: Backup,
        context: ModelContext
    ) throws -> (summary: ExportImport.ImportSummary, safetyBackup: URL?) {
        let data = try Data(contentsOf: backup.url)
        return try ExportImport.importAll(data: data, context: context, mode: .replace)
    }

    struct BackupUnavailable: LocalizedError {
        var errorDescription: String? {
            String(localized: "Vos données n’ont pas pu être ouvertes au lancement : aucune sauvegarde n’est écrite tant que l’application fonctionne sur une base temporaire.")
        }
    }

    // MARK: - Rotation

    private static func prune() {
        let files = backups().map { (name: $0.url.lastPathComponent, date: $0.date) }
        for name in AutoBackupPolicy.filesToPrune(files) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }
}
