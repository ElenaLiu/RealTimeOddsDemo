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
    dependencies: [
        .package(url: "https://github.com/apple/swift-collections", from: "1.0.6"),
        .package(url: "https://github.com/groue/GRDB.swift", from: "6.0.0")
    ],
    targets: [
        .target(
            name: "RealTimeOddsPackage",
            dependencies: [
                .product(name: "OrderedCollections", package: "swift-collections"),
                .product(name: "GRDB", package: "GRDB.swift")
            ],
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
