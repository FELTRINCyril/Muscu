import Foundation

/// Repos par defaut quand une prescription n'en fixe pas.
///
/// Deux valeurs, parce qu'un mouvement a la barre (squat, souleve de terre,
/// developpe) demande en general une recuperation plus longue qu'un
/// exercice aux halteres, a la machine ou a la poulie. Le type de materiel
/// vient du catalogue (ou de l'exercice personnalise).
public struct RestDefaults: Equatable, Sendable {
    /// Bornes acceptees par les reglages, en secondes.
    public static let allowedRange = 15...600
    /// Valeur historique, unique avant la distinction barre / autres.
    public static let legacySeconds = 90

    public var barbellSeconds: Int
    public var otherSeconds: Int

    /// Materiels du catalogue traites comme « barre ».
    public static let barbellEquipment: Set<String> = ["barbell", "e-z curl bar"]

    public init(barbellSeconds: Int = legacySeconds, otherSeconds: Int = legacySeconds) {
        self.barbellSeconds = Self.clamped(barbellSeconds)
        self.otherSeconds = Self.clamped(otherSeconds)
    }

    public static func clamped(_ seconds: Int) -> Int {
        min(max(seconds, allowedRange.lowerBound), allowedRange.upperBound)
    }

    public static func isBarbell(equipment: String?) -> Bool {
        guard let equipment else { return false }
        return barbellEquipment.contains(equipment.lowercased())
    }

    /// Repos par defaut pour ce materiel. Un materiel inconnu prend la
    /// valeur « autres » : c'est la plus courte, donc la plus prudente pour
    /// ne pas allonger une seance sans raison.
    public func seconds(forEquipment equipment: String?) -> Int {
        Self.isBarbell(equipment: equipment) ? barbellSeconds : otherSeconds
    }

    /// Complete le repos d'un exercice qui n'en prescrit pas.
    ///
    /// Seuls les formats a series classiques sont concernes : la pyramide a
    /// son repos adaptatif, les formats chronometres gerent leurs propres
    /// segments, et un repos explicitement prescrit n'est jamais remplace.
    public func filling(_ exercise: WorkoutExercisePlan, equipment: String?) -> WorkoutExercisePlan {
        guard exercise.restSeconds <= 0 else { return exercise }
        switch exercise.format {
        case .classic, .dropset, .restPause, .myoReps:
            var filled = exercise
            filled.restSeconds = seconds(forEquipment: equipment)
            return filled
        case .pyramid, .intervals, .emom, .amrap, .forTime:
            return exercise
        }
    }
}

/// Etat d'un repos a un instant donne : temps restant, puis depassement
/// une fois la fin atteinte. L'application n'affiche plus le depassement :
/// le repos se ferme a zero et l'ecran de saisie revient aussitot. Le repos
/// reellement pris est enregistre avec la serie suivante (`ActualRest`).
public struct RestCountdown: Equatable, Sendable {
    /// Secondes restantes (>= 0) tant que le repos n'est pas termine.
    public var remainingSeconds: Int
    /// Secondes ecoulees depuis la fin prevue (>= 0), une fois depassee.
    public var overtimeSeconds: Int

    public var isOvertime: Bool { overtimeSeconds > 0 }

    /// Au-dela, un depassement n'a plus de sens (application oubliee,
    /// seance reprise le lendemain) : il n'est plus affiche.
    public static let maximumOvertimeSeconds = 3_600

    public init(endDate: Date, now: Date) {
        let delta = endDate.timeIntervalSince(now)
        if delta > 0 {
            remainingSeconds = Int(delta.rounded(.up))
            overtimeSeconds = 0
        } else {
            remainingSeconds = 0
            overtimeSeconds = Int((-delta).rounded(.down))
        }
    }

    /// « 1:05 » pendant le repos, « +0:12 » en depassement.
    public var label: String {
        isOvertime ? "+" + Self.clock(overtimeSeconds) : Self.clock(remainingSeconds)
    }

    public static func clock(_ seconds: Int) -> String {
        let value = max(0, seconds)
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}
