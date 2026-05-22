// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ObviousSaveMD",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ObviousSaveMD", targets: ["ObviousSaveMD"]),
        .library(name: "ObviousSaveMDCore", targets: ["ObviousSaveMDCore"]),
    ],
    targets: [
        .target(
            name: "ObviousSaveMDCore"
        ),
        .executableTarget(
            name: "ObviousSaveMD",
            dependencies: ["ObviousSaveMDCore"]
        ),
        .testTarget(
            name: "ObviousSaveMDCoreTests",
            dependencies: ["ObviousSaveMDCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
