// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Decanter",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "DecanterKit"),
        .executableTarget(name: "Decanter", dependencies: ["DecanterKit"]),
        .testTarget(name: "DecanterKitTests", dependencies: ["DecanterKit"]),
    ],
    swiftLanguageModes: [.v5]
)
