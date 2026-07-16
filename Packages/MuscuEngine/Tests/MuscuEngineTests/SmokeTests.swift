import Testing
@testable import MuscuEngine

@Suite
struct SmokeTests {
    @Test
    func testPackageLoads() {
        #expect(MuscuEngineInfo.version == "0.1.0")
    }
}
