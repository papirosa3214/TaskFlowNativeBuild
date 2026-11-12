// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "NewChatCore",
    platforms: [.iOS("18.0"), .macOS(.v14)],
    products: [.library(name: "NewChatCore", targets: ["NewChatCore"])],
    targets: [
        .target(name: "NewChatCore"),
        .testTarget(name: "NewChatCoreTests", dependencies: ["NewChatCore"]),
    ]
)
