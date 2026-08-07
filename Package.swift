// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "JuicerKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "JuicerKit", targets: ["JuicerKit"])
    ],
    targets: [
        .target(name: "JuicerKit"),
        .testTarget(name: "JuicerKitTests", dependencies: ["JuicerKit"])
    ]
)
