import Foundation

/// Repartition d'une seance entre temps de repos et temps actif, a partir
/// du repos reellement mesure entre deux validations (`ActualRest`).
///
/// Le repos mesure va d'une validation a la suivante : pour une serie en
/// repetitions, il inclut donc son execution (son debut reel n'est pas
/// connu). Le temps « actif » est le reste de la seance : approche,
/// echauffement, series chronometrees, transitions.
///
/// Aucune estimation : si une seule serie (hors la premiere) n'a pas de
/// repos mesure — seance importee, anterieure a la mesure, interruption de
/// plus d'une heure, serie ajoutee apres coup — la repartition n'est pas
/// calculee plutot que d'etre inventee.
public struct SessionTimeBreakdown: Equatable, Sendable {
    public let activeSeconds: Int
    public let restSeconds: Int

    public var totalSeconds: Int { activeSeconds + restSeconds }

    public init(activeSeconds: Int, restSeconds: Int) {
        self.activeSeconds = activeSeconds
        self.restSeconds = restSeconds
    }

    /// Serie vue par le calcul : son rang de saisie et son repos mesure.
    public struct SetRest: Equatable, Sendable {
        public var sequenceIndex: Int
        public var restSeconds: Int?

        public init(sequenceIndex: Int, restSeconds: Int?) {
            self.sequenceIndex = sequenceIndex
            self.restSeconds = restSeconds
        }
    }

    /// `nil` quand la repartition ne peut pas etre etablie honnetement.
    public static func make(totalSeconds: Int, sets: [SetRest]) -> SessionTimeBreakdown? {
        guard totalSeconds > 0, sets.count >= 2 else { return nil }
        let ordered = sets.sorted { $0.sequenceIndex < $1.sequenceIndex }
        var rest = 0
        for set in ordered.dropFirst() {
            guard let seconds = set.restSeconds, seconds >= 0 else { return nil }
            rest += seconds
        }
        guard rest <= totalSeconds else { return nil }
        return SessionTimeBreakdown(activeSeconds: totalSeconds - rest, restSeconds: rest)
    }
}
