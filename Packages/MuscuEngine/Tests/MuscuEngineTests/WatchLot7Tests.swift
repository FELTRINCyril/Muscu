import Foundation
import Testing
@testable import MuscuEngine

@Suite("Hôte de la séance Santé (décision 0017)")
struct HealthWorkoutCoordinationTests {
    private func context(
        allowed: Bool = true,
        paired: Bool = true,
        installed: Bool = true,
        phoneLive: Bool = true
    ) -> HealthWorkoutCoordination.Context {
        .init(healthAllowed: allowed, watchPaired: paired, watchAppInstalled: installed, phoneLiveSupported: phoneLive)
    }

    @Test("Montre appairée avec Muscu installé : la montre enregistre")
    func watchFirst() {
        #expect(HealthWorkoutCoordination.host(for: context()) == .watch)
        #expect(HealthWorkoutCoordination.host(for: context(phoneLive: false)) == .watch)
    }

    @Test("Sans montre utilisable : l'iPhone, sinon après coup")
    func phoneThenAfterTheFact() {
        #expect(HealthWorkoutCoordination.host(for: context(paired: false)) == .phone)
        #expect(HealthWorkoutCoordination.host(for: context(installed: false)) == .phone)
        #expect(HealthWorkoutCoordination.host(for: context(paired: false, phoneLive: false)) == .afterTheFact)
    }

    @Test("Santé désactivée : personne n'enregistre en direct")
    func healthDisabled() {
        #expect(HealthWorkoutCoordination.host(for: context(allowed: false)) == .afterTheFact)
        #expect(HealthWorkoutCoordination.fallbackHost(for: context(allowed: false)) == .afterTheFact)
        #expect(HealthWorkoutCoordination.hostForWatchStart(healthAllowed: false) == .afterTheFact)
    }

    @Test("Montre injoignable au démarrage : repli sur l'iPhone, jamais les deux")
    func fallbackAfterWatchFailure() {
        #expect(HealthWorkoutCoordination.fallbackHost(for: context()) == .phone)
        #expect(HealthWorkoutCoordination.fallbackHost(for: context(phoneLive: false)) == .afterTheFact)
    }

    @Test("Séance démarrée à la montre : la montre l'enregistre")
    func watchStart() {
        #expect(HealthWorkoutCoordination.hostForWatchStart(healthAllowed: true) == .watch)
    }

    @Test("La montre n'enregistre que la séance qui lui a été confiée")
    func watchMayRecord() {
        let id = UUID()
        #expect(HealthWorkoutCoordination.watchMayRecord(designatedHost: .watch, designatedWorkoutId: id, mirroredWorkoutId: id))
        #expect(!HealthWorkoutCoordination.watchMayRecord(designatedHost: .phone, designatedWorkoutId: id, mirroredWorkoutId: id))
        #expect(!HealthWorkoutCoordination.watchMayRecord(designatedHost: .watch, designatedWorkoutId: id, mirroredWorkoutId: UUID()))
        #expect(!HealthWorkoutCoordination.watchMayRecord(designatedHost: .watch, designatedWorkoutId: nil, mirroredWorkoutId: nil))
    }
}

@Suite("Séance Santé tenue par la montre, vue de l'iPhone")
struct RemoteHealthWorkoutTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Séance en cours : on attend")
    func running() {
        let active = UUID()
        let marker = LiveWorkoutMarker(activeWorkoutId: active, host: .watch)
        #expect(RemoteHealthWorkout.resolve(marker: marker, pendingActiveWorkoutIds: [active], existingCompletedSessionIds: [], now: now) == .keepWaiting)
    }

    @Test("Séance abandonnée pendant l'arrêt : la montre jette son entraînement")
    func abandoned() {
        let marker = LiveWorkoutMarker(activeWorkoutId: UUID(), host: .watch)
        #expect(RemoteHealthWorkout.resolve(marker: marker, pendingActiveWorkoutIds: [], existingCompletedSessionIds: [], now: now) == .discardOnWatch)
    }

    @Test("Confirmation attendue dans le délai, abandonnée au-delà")
    func timeout() {
        let completed = UUID()
        let recent = LiveWorkoutMarker(
            activeWorkoutId: UUID(),
            completedSessionId: completed,
            host: .watch,
            finishRequestedAt: now.addingTimeInterval(-60)
        )
        #expect(RemoteHealthWorkout.resolve(marker: recent, pendingActiveWorkoutIds: [], existingCompletedSessionIds: [completed], now: now) == .keepWaiting)

        var stale = recent
        stale.finishRequestedAt = now.addingTimeInterval(-RemoteHealthWorkout.confirmationTimeout)
        #expect(RemoteHealthWorkout.resolve(marker: stale, pendingActiveWorkoutIds: [], existingCompletedSessionIds: [completed], now: now) == .giveUp)
    }

    @Test("Séance terminée puis supprimée : plus rien à relier")
    func deletedSession() {
        let marker = LiveWorkoutMarker(activeWorkoutId: UUID(), completedSessionId: UUID(), host: .watch, finishRequestedAt: now)
        #expect(RemoteHealthWorkout.resolve(marker: marker, pendingActiveWorkoutIds: [], existingCompletedSessionIds: [], now: now) == .giveUp)
    }

    @Test("Une confirmation tardive reste acceptée si la séance existe")
    func lateConfirmation() {
        let id = UUID()
        #expect(RemoteHealthWorkout.acceptsConfirmation(completedSessionId: id, existingCompletedSessionIds: [id]))
        #expect(!RemoteHealthWorkout.acceptsConfirmation(completedSessionId: id, existingCompletedSessionIds: []))
    }

    @Test("Un marqueur antérieur au lot 7 reste lisible et désigne l'iPhone")
    func legacyMarker() throws {
        let id = UUID()
        let json = Data(#"{"activeWorkoutId":"\#(id.uuidString)"}"#.utf8)
        let marker = try JSONDecoder().decode(LiveWorkoutMarker.self, from: json)
        #expect(marker.activeWorkoutId == id)
        #expect(marker.host == nil)
        #expect(!marker.isHostedByWatch)

        let roundTrip = try JSONDecoder().decode(
            LiveWorkoutMarker.self,
            from: JSONEncoder().encode(LiveWorkoutMarker(activeWorkoutId: id, host: .watch))
        )
        #expect(roundTrip.isHostedByWatch)
    }
}
