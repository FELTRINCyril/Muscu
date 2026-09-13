import Foundation
import MuscuEngine

/// Format d'execution d'une prescription. Les valeurs brutes sont stables :
/// les programmes deja enregistres restent lisibles.
///
/// Un format n'apparait ici qu'une fois son ecran d'execution reellement
/// livre : un format proposable dans l'editeur doit etre executable.
enum SetFormat: String, Codable, CaseIterable {
    case classic
    case pyramid
    case dropset
    case restPause
    case myoReps
    case intervals
    case emom
    case amrap
    case forTime

    var displayName: String {
        switch self {
        case .classic: return String(localized: "Classique")
        case .pyramid: return String(localized: "Pyramide")
        case .dropset: return String(localized: "Dropset")
        case .restPause: return String(localized: "Rest-pause")
        case .myoReps: return String(localized: "Myo-reps")
        case .intervals: return String(localized: "Intervalles")
        case .emom: return String(localized: "EMOM")
        case .amrap: return String(localized: "AMRAP")
        case .forTime: return String(localized: "For Time")
        }
    }

    /// Formats d'intensification : une serie classique prolongee par des
    /// paliers ou des mini-series. Ils partagent l'ecran de saisie classique.
    var isIntensityTechnique: Bool {
        switch self {
        case .dropset, .restPause, .myoReps: return true
        case .classic, .pyramid, .intervals, .emom, .amrap, .forTime: return false
        }
    }

    /// Un format chronometre mesure un resultat (temps, tours) plutot qu'une
    /// charge : ses records sont specifiques a sa configuration.
    var isTimed: Bool {
        switch self {
        case .intervals, .emom, .amrap, .forTime: return true
        case .classic, .pyramid, .dropset, .restPause, .myoReps: return false
        }
    }

    /// Un repos de zero seconde n'est semantiquement valide que pour les
    /// formats qui enchainent les efforts sans pause prevue.
    var allowsZeroRest: Bool {
        switch self {
        case .dropset, .restPause, .myoReps, .amrap, .intervals, .emom, .forTime: return true
        case .classic, .pyramid: return false
        }
    }

    /// Cle de configuration d'un record pour les formats chronometres : un
    /// AMRAP de 8 minutes n'est pas comparable a un AMRAP de 12 minutes.
    func recordConfigurationKey(for exercise: PrescribedExercise) -> String {
        switch self {
        case .amrap: return "amrap:\(exercise.amrapSeconds)"
        case .forTime: return "forTime:\(exercise.forTimeCapSeconds)"
        case .emom: return "emom:\(exercise.intervalRounds)"
        case .intervals: return "intervals:\(exercise.intervalWork)-\(exercise.intervalRest)x\(exercise.intervalRounds)"
        case .classic, .pyramid, .dropset, .restPause, .myoReps: return ""
        }
    }
}

extension PrescribedExercise {
    var format: SetFormat {
        get { SetFormat(rawValue: formatRaw) ?? .classic }
        set { formatRaw = newValue.rawValue }
    }
}
