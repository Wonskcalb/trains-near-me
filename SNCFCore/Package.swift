// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SNCFCore",
    defaultLocalization: "en",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [.library(name: "SNCFCore", targets: ["SNCFCore"])],
    targets: [
        .target(
            name: "SNCFCore",
            resources: [
                .process("Theme/Tableau.xcassets"),
                .process("Theme/Fonts"),
                .process("Localizable.xcstrings"),
            ]
        ),
        .testTarget(
            name: "SNCFCoreTests",
            dependencies: ["SNCFCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
