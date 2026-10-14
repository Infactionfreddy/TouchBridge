// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TouchBridge",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TouchCore", targets: ["TouchCore"]),
        .library(name: "TouchDevice", targets: ["TouchDevice"]),
        .library(name: "TouchInject", targets: ["TouchInject"]),
        .executable(name: "TouchBridge", targets: ["TouchBridge"]),
        .executable(name: "hidrecord", targets: ["hidrecord"]),
    ],
    targets: [
        .target(name: "TouchCore"),
        .target(name: "TouchDevice", dependencies: ["TouchCore"]),
        .target(name: "TouchInject", dependencies: ["TouchCore"]),
        .executableTarget(
            name: "TouchBridge",
            dependencies: ["TouchCore", "TouchDevice", "TouchInject"]
        ),
        .executableTarget(name: "hidrecord", dependencies: ["TouchCore", "TouchDevice"]),
        .testTarget(
            name: "TouchCoreTests",
            dependencies: ["TouchCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "TouchInjectTests", dependencies: ["TouchInject"]),
    ],
    swiftLanguageModes: [.v6]
)
