// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Screenshots",
    platforms: [.macOS(.v15)],
    dependencies: [.package(path: "../../SNCFCore")],
    targets: [.executableTarget(name: "Screenshots", dependencies: [.product(name: "SNCFCore", package: "SNCFCore")])]
)
