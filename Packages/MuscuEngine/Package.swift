// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MuscuEngine",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [.library(name: "MuscuEngine", targets: ["MuscuEngine"])],
    targets: [
        .target(name: "MuscuEngine", resources: [.copy("Resources")]),
        .testTarget(name: "MuscuEngineTests", dependencies: ["MuscuEngine"]),
    ]
)
