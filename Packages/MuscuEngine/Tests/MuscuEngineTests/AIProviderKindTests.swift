import Testing
@testable import MuscuEngine

struct AIProviderKindTests {
    @Test func fourProvidersExist() {
        #expect(AIProviderKind.allCases.count == 4)
    }

    @Test func defaultsAreCoherent() {
        #expect(AIProviderKind.anthropic.defaultModel == "claude-opus-5")
        #expect(AIProviderKind.anthropic.requiresBaseURL == false)
        #expect(AIProviderKind.openAICompatible.requiresBaseURL == true)
        #expect(AIProviderKind.openAICompatible.defaultModel == nil)
    }
}
