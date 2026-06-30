// swift-tools-version: 5.8

import PackageDescription

let package = Package(
    name: "PowerPreview",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "PowerPreview",
            targets: ["PowerPreview"]
        ),
        .library(
            name: "PowerPreviewCore",
            targets: ["PowerPreviewCore"]
        )
    ],
    targets: [
        .target(
            name: "PowerPreviewCore",
            path: "Sources/PowerPreviewCore"
        ),
        .executableTarget(
            name: "PowerPreview",
            dependencies: ["PowerPreviewCore"],
            path: "Sources/PowerPreview",
            resources: [
                .copy("Resources")
            ]
        ),
        .testTarget(
            name: "PowerPreviewTests",
            dependencies: ["PowerPreviewCore"],
            path: "Tests/PowerPreviewTests"
        )
    ]
)
