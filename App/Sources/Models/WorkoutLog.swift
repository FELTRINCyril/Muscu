import Foundation
import SwiftData

@Model
final class CompletedSession {
    var id: UUID = UUID()
    var date: Date = Date()
    var programName: String = ""
    var sessionName: String = ""
    var durationSeconds: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \CompletedSet.session)
    var sets: [CompletedSet] = []

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        programName: String,
        sessionName: String,
        durationSeconds: Int = 0,
        sets: [CompletedSet] = []
    ) {
        self.id = id
        self.date = date
        self.programName = programName
        self.sessionName = sessionName
        self.durationSeconds = durationSeconds
        self.sets = sets
    }
}

// CompletedSet est partage entre CompletedSession.sets (historique) et
// ActiveWorkout.loggedSets (seance en cours). SwiftData exige des inverses
// distincts pour chaque relation vers un meme type : on modelise donc les
// deux parents comme optionnels sur CompletedSet plutot que de dupliquer
// un struct Codable. Un CompletedSet donne n'a en pratique qu'un seul des
// deux parents non-nil a la fois.
@Model
final class CompletedSet {
    var id: UUID = UUID()
    var exerciseId: String = ""
    var displayName: String = ""
    var orderIndex: Int = 0
    var setIndex: Int = 0
    var weight: Double = 0
    var reps: Int = 0
    var isWarmup: Bool = false

    var session: CompletedSession?
    var activeWorkout: ActiveWorkout?

    init(
        id: UUID = UUID(),
        exerciseId: String,
        displayName: String,
        orderIndex: Int,
        setIndex: Int,
        weight: Double,
        reps: Int,
        isWarmup: Bool = false
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.displayName = displayName
        self.orderIndex = orderIndex
        self.setIndex = setIndex
        self.weight = weight
        self.reps = reps
        self.isWarmup = isWarmup
    }
}
