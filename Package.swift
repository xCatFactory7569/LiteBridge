// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LiteBridge",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "LiteBridge", path: "Sources/LiteBridge")
    ]
)
