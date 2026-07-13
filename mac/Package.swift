// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ClipShare",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "clipshare-mac", targets: ["clipshare-mac"]),
        .library(name: "ClipShareCore", targets: ["ClipShareCore"])
    ],
    targets: [
        .executableTarget(
            name: "clipshare-mac",
            dependencies: ["ClipShareCore"]
        ),
        .target(name: "ClipShareCore"),
        .testTarget(
            name: "ClipShareCoreTests",
            dependencies: ["ClipShareCore"]
        )
    ]
)
