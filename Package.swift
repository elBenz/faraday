// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Faraday",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "FaradayCore", targets: ["FaradayCore"])
    ],
    targets: [
        .target(name: "FaradayCore"),
        .testTarget(name: "FaradayCoreTests", dependencies: ["FaradayCore"])
    ]
)
