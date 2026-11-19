// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DogearCore",
    // macOS so seam 1 runs with `swift test` on the host.
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [.library(name: "DogearCore", targets: ["DogearCore"])],
    targets: [
        .target(name: "DogearCore"),
        .testTarget(
            name: "DogearCoreTests",
            dependencies: ["DogearCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
