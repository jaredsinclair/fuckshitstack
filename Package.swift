// swift-tools-version:5.1

import PackageDescription

let package = Package(
    name: "FuckShitStack",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "FuckShitStack",
            targets: ["FuckShitStack"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jaredsinclair/etcetera.git", .branch("spm")),
    ],
    targets: [
        .target(
            name: "FuckShitStack",
            dependencies: ["Etcetera"]),
        .testTarget(
            name: "FuckShitStackTests",
            dependencies: ["FuckShitStack"]),
    ]
)
