// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TonyStark",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "TonyStark", targets: ["TonyStark"])],
    targets: [
        .target(name: "GestureCore"),
        .target(name: "CMediaPipe"),
        .target(name: "HandTracking", dependencies: ["GestureCore", "CMediaPipe"]),
        .executableTarget(name: "TonyStark", dependencies: ["GestureCore", "HandTracking"]),
        .testTarget(name: "GestureCoreTests", dependencies: ["GestureCore"]),
        .testTarget(name: "HandTrackingTests", dependencies: ["HandTracking"])
    ],
    swiftLanguageModes: [.v5]
)
