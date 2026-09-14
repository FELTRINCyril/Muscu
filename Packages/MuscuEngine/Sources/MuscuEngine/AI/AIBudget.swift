import Foundation

/// Suivi d'usage mensuel du coach IA.
///
/// Une requete d'IA a un cout. L'utilisateur doit pouvoir le borner, et
/// savoir ou il en est AVANT d'envoyer, pas apres.
public struct AIUsage: Codable, Equatable, Sendable {
    /// Mois de reference, au format `yyyy-MM` : le compteur se remet a zero
    /// de lui-meme quand le mois change, sans tache de fond.
    public var month: String
    public var requestCount: Int
    /// Caracteres envoyes, pour donner un ordre de grandeur honnete plutot
    /// qu'un cout en euros que nous ne connaissons pas.
    public var charactersSent: Int

    public init(month: String, requestCount: Int = 0, charactersSent: Int = 0) {
        self.month = month
        self.requestCount = requestCount
        self.charactersSent = charactersSent
    }
}

public struct AIBudget: Codable, Equatable, Sendable {
    /// Zero = aucune limite.
    public var monthlyRequestLimit: Int
    /// Au-dela, l'envoi demande une confirmation : une requete longue coute
    /// plus cher, et l'utilisateur doit le voir venir.
    public var longRequestCharacterThreshold: Int

    public init(monthlyRequestLimit: Int = 50, longRequestCharacterThreshold: Int = 4_000) {
        self.monthlyRequestLimit = max(0, monthlyRequestLimit)
        self.longRequestCharacterThreshold = max(0, longRequestCharacterThreshold)
    }

    public static let `default` = AIBudget()
}

public enum AIBudgetGuard {
    public static func month(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }

    /// Usage a jour pour ce mois : remet a zero au changement de mois.
    public static func normalized(_ usage: AIUsage, now: Date, calendar: Calendar = .current) -> AIUsage {
        let current = month(for: now, calendar: calendar)
        guard usage.month == current else { return AIUsage(month: current) }
        return usage
    }

    /// Verifie qu'une requete peut partir.
    public static func check(
        usage: AIUsage,
        budget: AIBudget,
        now: Date,
        calendar: Calendar = .current
    ) -> AICoachError? {
        guard budget.monthlyRequestLimit > 0 else { return nil }
        let current = normalized(usage, now: now, calendar: calendar)
        guard current.requestCount < budget.monthlyRequestLimit else {
            return .budgetExceeded(limit: budget.monthlyRequestLimit)
        }
        return nil
    }

    /// Vrai quand la requete merite une confirmation explicite avant envoi.
    public static func requiresConfirmation(payloadCharacters: Int, budget: AIBudget) -> Bool {
        budget.longRequestCharacterThreshold > 0
            && payloadCharacters >= budget.longRequestCharacterThreshold
    }

    public static func recording(
        _ usage: AIUsage,
        payloadCharacters: Int,
        now: Date,
        calendar: Calendar = .current
    ) -> AIUsage {
        var updated = normalized(usage, now: now, calendar: calendar)
        updated.requestCount += 1
        updated.charactersSent += max(0, payloadCharacters)
        return updated
    }

    /// Resume affichable, sans inventer de cout monetaire.
    public static func summary(usage: AIUsage, budget: AIBudget, now: Date, calendar: Calendar = .current) -> String {
        let current = normalized(usage, now: now, calendar: calendar)
        guard budget.monthlyRequestLimit > 0 else {
            return "\(current.requestCount) demande(s) ce mois-ci, aucune limite fixée."
        }
        return "\(current.requestCount) demande(s) sur \(budget.monthlyRequestLimit) ce mois-ci."
    }
}
