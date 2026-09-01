// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UniversalAssistantBackend",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "UniversalAssistantServer", targets: ["UniversalAssistantServer"])],
    targets: [
        .executableTarget(name: "UniversalAssistantServer"),
        .testTarget(name: "UniversalAssistantServerTests", dependencies: ["UniversalAssistantServer"])
    ]
)
