// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SNCFCore",
    platforms: [.macOS(.v15)],
    products: [.library(name: "SNCFCore", targets: ["SNCFCore"])],
    targets: [
        .target(name: "SNCFCore"),
        .testTarget(
            name: "SNCFCoreTests",
            dependencies: ["SNCFCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
