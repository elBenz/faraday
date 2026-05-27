// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Faraday",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "FaradayCore", targets: ["FaradayCore"]),
        .executable(name: "FaradayDaemon", targets: ["FaradayDaemon"]),
        .executable(name: "FaradayOverlayHelper", targets: ["FaradayOverlayHelper"])
    ],
    targets: [
        .target(name: "FaradayCore"),
        .executableTarget(name: "FaradayDaemon", dependencies: ["FaradayCore"]),
        .executableTarget(name: "FaradayOverlayHelper"),
        .testTarget(name: "FaradayCoreTests", dependencies: ["FaradayCore"])
    ]
)
