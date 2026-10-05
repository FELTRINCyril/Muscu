import XCTest
@testable import Muscu

@MainActor
final class HomeAndRecordTests: XCTestCase {
    func testNextSessionUsesStableIdentifiersAfterRename() {
        let first = ProgramSession(name: "A renommée", orderIndex: 0)
        let second = ProgramSession(name: "B", orderIndex: 1)
        let program = Program(name: "Programme renommé", sessions: [first, second])
        let history = CompletedSession(
            programId: program.id,
            programSessionId: first.id,
            programName: "Ancien programme",
            sessionName: "Ancienne A"
        )

        XCTAssertEqual(HomeView.nextSession(for: program, completedSessions: [history])?.id, second.id)
    }

    func testLegacyHistoryStillFallsBackToNames() {
        let first = ProgramSession(name: "A", orderIndex: 0)
        let second = ProgramSession(name: "B", orderIndex: 1)
        let program = Program(name: "Programme", sessions: [first, second])
        let history = CompletedSession(programName: "Programme", sessionName: "A")

        XCTAssertEqual(HomeView.nextSession(for: program, completedSessions: [history])?.id, second.id)
    }
}
