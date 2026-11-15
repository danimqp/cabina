// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Cabina",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CabinaCore"),
        .executableTarget(name: "Cabina", dependencies: ["CabinaCore"]),
        .testTarget(name: "CabinaCoreTests", dependencies: ["CabinaCore"]),
    ]
)
