// swift-tools-version: 5.9

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
    dependencies: [
        .package(url: "https://github.com/mpvkit/MPVKit.git", from: "0.41.0")
    ],
    targets: [
        .target(
            name: "PowerPreviewCore",
            path: "Sources/PowerPreviewCore"
        ),
        .executableTarget(
            name: "PowerPreview",
            dependencies: [
                "PowerPreviewCore",
                .product(name: "MPVKit-GPL", package: "MPVKit")
            ],
            path: "Sources/PowerPreview",
            exclude: [
                "Resources/README.md"
            ],
            resources: [
                .copy("Resources")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Metal"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("UniformTypeIdentifiers")
            ]
        ),
        .testTarget(
            name: "PowerPreviewTests",
            dependencies: ["PowerPreviewCore"],
            path: "Tests/PowerPreviewTests"
        )
    ]
)
