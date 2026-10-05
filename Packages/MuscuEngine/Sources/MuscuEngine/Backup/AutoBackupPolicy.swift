import Foundation

/// Regles des sauvegardes automatiques : quand en ecrire une, lesquelles
/// garder, comment les nommer.
///
/// Idee reprise d'Iron (GPL-3.0) : idee seulement, aucune ligne de code.
public enum AutoBackupPolicy {
    /// Nombre de sauvegardes automatiques conservees.
    public static let defaultRetainedCount = 7
    /// Prefixe des fichiers : seuls ceux-ci sont listes et effaces par la
    /// rotation — un fichier depose par l'utilisateur dans le meme dossier
    /// n'est jamais touche.
    public static let filePrefix = "muscu-sauvegarde-"
    public static let fileExtension = "json"

    /// Une sauvegarde est due s'il n'y en a encore aucune, ou si la derniere
    /// date d'un autre jour calendaire : au plus une par jour.
    public static func isDue(lastBackupAt: Date?, now: Date, calendar: Calendar) -> Bool {
        guard let lastBackupAt else { return true }
        // Horloge reculee (fuseau, reglage manuel) : la date enregistree est
        // dans le futur. On sauvegarde plutot que de s'interdire de le faire
        // jusqu'a ce que l'horloge la rattrape.
        if lastBackupAt > now { return true }
        return !calendar.isDate(lastBackupAt, inSameDayAs: now)
    }

    /// Nom du fichier d'une sauvegarde. Horodatage triable, sans caractere
    /// interdit par l'app Fichiers.
    public static func fileName(for date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return "\(filePrefix)\(formatter.string(from: date)).\(fileExtension)"
    }

    /// Vrai pour un fichier ecrit par la sauvegarde automatique.
    public static func isAutomaticBackup(fileName: String) -> Bool {
        fileName.hasPrefix(filePrefix) && fileName.hasSuffix(".\(fileExtension)")
    }

    /// Fichiers a supprimer pour n'en garder que `retained`, les plus
    /// recents. `files` : noms et dates, dans n'importe quel ordre. Les
    /// fichiers etrangers a la sauvegarde automatique sont ignores.
    public static func filesToPrune(
        _ files: [(name: String, date: Date)],
        retained: Int = defaultRetainedCount
    ) -> [String] {
        let ours = files
            .filter { isAutomaticBackup(fileName: $0.name) }
            .sorted { lhs, rhs in
                lhs.date != rhs.date ? lhs.date > rhs.date : lhs.name > rhs.name
            }
        return ours.dropFirst(max(1, retained)).map(\.name)
    }
}
