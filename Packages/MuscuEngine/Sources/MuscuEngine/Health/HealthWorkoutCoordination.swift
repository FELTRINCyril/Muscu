import Foundation

// MARK: - Qui enregistre la seance Sante ?

/// Appareil qui enregistre la seance Sante en direct d'une seance Muscu.
///
/// Une seance Muscu n'a JAMAIS qu'un seul hote : deux `HKWorkoutSession`
/// simultanees (montre et iPhone) ecriraient deux entrainements dans Sante
/// pour une seule seance.
public enum HealthWorkoutHost: String, Codable, Equatable, Sendable {
    /// La montre : capteur cardiaque au poignet, entrainement enregistre par
    /// elle et relie a la seance par l'iPhone a la fin.
    case watch
    /// L'iPhone (iOS 26+, decision 0015) : capteur connecte eventuel.
    case phone
    /// Personne en direct : la seance est ecrite apres coup par la
    /// synchronisation, comme avant le lot 5.
    case afterTheFact
}

/// Regle de coordination entre la seance Sante de la montre et celle de
/// l'iPhone (decision 0017).
///
/// 1. Sante desactivee, refusee ou absente : personne n'enregistre en
///    direct, et la synchronisation n'ecrit rien non plus.
/// 2. Montre appairee ET application Muscu installee dessus : la montre
///    est l'hote — c'est elle qui porte le capteur. L'iPhone la lance dans
///    la seance (`startWatchApp`).
/// 3. Sinon, ou si la montre n'a pas pu etre lancee : l'iPhone, s'il sait
///    enregistrer en direct (iOS 26+, hors Mac).
/// 4. Sinon : ecriture apres coup.
///
/// L'hote est choisi au demarrage et ne change plus pendant la seance :
/// basculer en cours de route laisserait deux entrainements partiels.
public enum HealthWorkoutCoordination {
    /// Etat des appareils au moment du choix.
    public struct Context: Equatable, Sendable {
        /// Sante active, ecriture des seances active et autorisee.
        public var healthAllowed: Bool
        public var watchPaired: Bool
        public var watchAppInstalled: Bool
        /// L'iPhone sait enregistrer une seance en direct (iOS 26+).
        public var phoneLiveSupported: Bool

        public init(healthAllowed: Bool, watchPaired: Bool, watchAppInstalled: Bool, phoneLiveSupported: Bool) {
            self.healthAllowed = healthAllowed
            self.watchPaired = watchPaired
            self.watchAppInstalled = watchAppInstalled
            self.phoneLiveSupported = phoneLiveSupported
        }
    }

    /// Hote d'une seance demarree sur l'iPhone.
    public static func host(for context: Context) -> HealthWorkoutHost {
        guard context.healthAllowed else { return .afterTheFact }
        if context.watchPaired, context.watchAppInstalled { return .watch }
        return fallbackHost(for: context)
    }

    /// Hote quand la montre n'a pas pu etre lancee dans la seance (montre
    /// hors de portee, au chargeur, autorisation refusee sur la montre).
    public static func fallbackHost(for context: Context) -> HealthWorkoutHost {
        guard context.healthAllowed else { return .afterTheFact }
        return context.phoneLiveSupported ? .phone : .afterTheFact
    }

    /// Hote d'une seance demarree DEPUIS la montre : elle l'enregistre
    /// elle-meme, si l'utilisateur a active Sante dans Muscu.
    public static func hostForWatchStart(healthAllowed: Bool) -> HealthWorkoutHost {
        healthAllowed ? .watch : .afterTheFact
    }

    /// La montre peut-elle demarrer sa propre seance Sante ? Uniquement si
    /// l'iPhone l'a designee comme hote pour CETTE seance — jamais de sa
    /// propre initiative pendant une seance tenue par l'iPhone.
    public static func watchMayRecord(
        designatedHost: HealthWorkoutHost?,
        designatedWorkoutId: UUID?,
        mirroredWorkoutId: UUID?
    ) -> Bool {
        guard designatedHost == .watch, let designatedWorkoutId else { return false }
        return designatedWorkoutId == mirroredWorkoutId
    }
}

// MARK: - Seance Sante tenue par la montre, vue de l'iPhone

/// Que faire, cote iPhone, d'une seance Sante tenue par la montre quand la
/// seance Muscu a change (lancement, synchronisation) ?
public enum RemoteHealthWorkoutResolution: Equatable, Sendable {
    /// Rien a decider : la seance est en cours, ou la montre n'a pas encore
    /// repondu dans le delai.
    case keepWaiting
    /// La seance Muscu a ete abandonnee : la montre doit jeter son
    /// entrainement, rien n'est enregistre.
    case discardOnWatch
    /// La montre n'a pas confirme son entrainement dans le delai : la
    /// seance redevient une seance ordinaire, ecrite apres coup. Si la
    /// montre confirme plus tard, son entrainement remplace celui ecrit
    /// apres coup (jamais deux entrainements).
    case giveUp
}

public enum RemoteHealthWorkout {
    /// Delai laisse a la montre pour terminer et confirmer son entrainement
    /// apres la fin de la seance (montre hors de portee, application
    /// suspendue). Au-dela, la seance est ecrite apres coup.
    public static let confirmationTimeout: TimeInterval = 15 * 60

    public static func resolve(
        marker: LiveWorkoutMarker,
        pendingActiveWorkoutIds: Set<UUID>,
        existingCompletedSessionIds: Set<UUID>,
        now: Date
    ) -> RemoteHealthWorkoutResolution {
        if let completed = marker.completedSessionId {
            // Seance terminee puis supprimee : plus rien a relier.
            guard existingCompletedSessionIds.contains(completed) else { return .giveUp }
            let requested = marker.finishRequestedAt ?? now
            return now.timeIntervalSince(requested) >= confirmationTimeout ? .giveUp : .keepWaiting
        }
        return pendingActiveWorkoutIds.contains(marker.activeWorkoutId) ? .keepWaiting : .discardOnWatch
    }

    /// Une confirmation de la montre est-elle attendue pour cette seance ?
    /// Une confirmation tardive (apres abandon du delai) reste acceptee si
    /// la seance terminee existe : elle remplace l'ecriture apres coup.
    public static func acceptsConfirmation(
        completedSessionId: UUID,
        existingCompletedSessionIds: Set<UUID>
    ) -> Bool {
        existingCompletedSessionIds.contains(completedSessionId)
    }
}
