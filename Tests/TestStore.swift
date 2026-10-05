import SwiftData
@testable import Muscu

@MainActor
enum TestStore {
    static func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Schema(versionedSchema: MuscuCurrentSchema.self), configurations: configuration)
    }
}
