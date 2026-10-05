import Foundation

/// Categorie de donnees pouvant partir vers un fournisseur d'IA.
///
/// Les categories sensibles valent `false` par defaut : la roadmap exige un
/// consentement GRANULAIRE, pas un interrupteur global.
public enum AIDataCategory: String, Codable, CaseIterable, Sendable, Identifiable {
    case trainingProfile
    case recentPerformance
    case bodyMeasurements
    case readinessCheckIns
    case personalNotes

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .trainingProfile: return "Profil d’entraînement"
        case .recentPerformance: return "Performances récentes"
        case .bodyMeasurements: return "Mensurations et poids"
        case .readinessCheckIns: return "Check-in de forme"
        case .personalNotes: return "Notes personnelles"
        }
    }

    public var explanation: String {
        switch self {
        case .trainingProfile:
            return "Objectif, niveau, jours disponibles, durée de séance et matériel."
        case .recentPerformance:
            return "Identifiants d’exercices, séries, répétitions et charges des dernières séances."
        case .bodyMeasurements:
            return "Poids corporel et mensurations. Sensible : exclu par défaut."
        case .readinessCheckIns:
            return "Énergie, sommeil, courbatures, stress et douleurs déclarées. Sensible : exclu par défaut."
        case .personalNotes:
            return "Vos commentaires libres sur les séances. Sensible : exclu par défaut."
        }
    }

    /// Categorie exclue par defaut, qui demande un accord explicite.
    public var isSensitive: Bool {
        switch self {
        case .trainingProfile, .recentPerformance: return false
        case .bodyMeasurements, .readinessCheckIns, .personalNotes: return true
        }
    }
}

/// Consentement, categorie par categorie.
public struct AIConsent: Codable, Equatable, Sendable {
    public private(set) var granted: Set<AIDataCategory>

    public init(granted: Set<AIDataCategory> = []) {
        self.granted = granted
    }

    /// Aucun partage : etat de depart, et etat apres revocation.
    public static let none = AIConsent()

    public func allows(_ category: AIDataCategory) -> Bool { granted.contains(category) }

    public mutating func grant(_ category: AIDataCategory) { granted.insert(category) }

    public mutating func revoke(_ category: AIDataCategory) { granted.remove(category) }

    /// Resume affichable de ce qui partira REELLEMENT.
    public func sharedSummary() -> [String] {
        let allowed = AIDataCategory.allCases.filter { granted.contains($0) }
        guard !allowed.isEmpty else { return ["Aucune donnée ne sera envoyée."] }
        return allowed.map { "\($0.displayName) : \($0.explanation)" }
    }

    /// Categories necessaires a une capacite. Une capacite ne peut pas
    /// exiger une categorie sensible : elle en tire parti si elle est
    /// accordee, jamais plus.
    public static func requiredCategories(for capability: AICoachCapability) -> Set<AIDataCategory> {
        switch capability {
        case .generateProgram, .shortenSession, .explain:
            return [.trainingProfile]
        case .adaptWeek, .substituteExercise, .summarizeSession:
            return [.trainingProfile, .recentPerformance]
        }
    }

    public func missingCategories(for capability: AICoachCapability) -> [AIDataCategory] {
        Self.requiredCategories(for: capability)
            .subtracting(granted)
            .sorted { $0.rawValue < $1.rawValue }
    }
}
