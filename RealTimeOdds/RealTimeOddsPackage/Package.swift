// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "RealTimeOddsPackage",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "RealTimeOddsPackage",
            targets: ["RealTimeOddsPackage"]
        ),
    ],
    targets: [
        .target(
            name: "RealTimeOddsPackage",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "RealTimeOddsPackageTests",
            dependencies: ["RealTimeOddsPackage"]
        ),
    ]
)
