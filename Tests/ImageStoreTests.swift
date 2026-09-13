import XCTest
@testable import Muscu

final class ImageStoreTests: XCTestCase {
    func testPathTraversalIsRejectedBeforeDiskOrNetworkAccess() async {
        let store = ImageStore()
        do {
            _ = try await store.localURL(for: "../Documents/secret.jpg")
            XCTFail("Un chemin sortant du cache aurait dû être refusé")
        } catch ImageStoreError.invalidPath {
            // attendu
        } catch {
            XCTFail("Erreur inattendue : \(error)")
        }
    }
}
