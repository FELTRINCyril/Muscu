import Foundation
import Testing
@testable import MuscuEngine

@Suite("Lien de démonstration")
struct DemoLinkTests {
    @Test("Un lien web absolu est accepté")
    func acceptsWebLinks() {
        #expect(DemoLink.isAcceptable("https://www.youtube.com/watch?v=abc"))
        #expect(DemoLink.isAcceptable("http://example.com/squat"))
        #expect(DemoLink.normalized("  https://example.com/a  ") == "https://example.com/a")
    }

    @Test("Les schémas non web, les liens relatifs et le vide sont refusés")
    func rejectsOtherSchemes() {
        #expect(!DemoLink.isAcceptable(""))
        #expect(!DemoLink.isAcceptable("javascript:alert(1)"))
        #expect(!DemoLink.isAcceptable("file:///etc/passwd"))
        #expect(!DemoLink.isAcceptable("muscu://exercise/bench"))
        #expect(!DemoLink.isAcceptable("/relative/path"))
        #expect(!DemoLink.isAcceptable("https://"))
        #expect(!DemoLink.isAcceptable("https://exa mple.com"))
        #expect(DemoLink.normalized("ftp://example.com") == nil)
    }

    @Test("Un lien trop long est refusé")
    func rejectsOversizedLinks() {
        let long = "https://example.com/" + String(repeating: "a", count: DemoLink.maximumLength)
        #expect(!DemoLink.isAcceptable(long))
    }
}
