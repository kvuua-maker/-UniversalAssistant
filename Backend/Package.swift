// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UniversalAssistantBackend",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "UniversalAssistantServer", targets: ["UniversalAssistantServer"])],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.119.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.15.1"),
        .package(url: "https://github.com/iansampson/AppAttest.git", revision: "f4fc1ea12c712d6833905d9c11c73c1601ae4001")
    ],
    targets: [
        .executableTarget(
            name: "UniversalAssistantServer",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "AppAttest", package: "AppAttest")
            ]
        ),
        .testTarget(name: "UniversalAssistantServerTests", dependencies: ["UniversalAssistantServer"])
    ]
)
