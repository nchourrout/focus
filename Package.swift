// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Focus",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "focus", targets: ["Focus"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "Focus",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/Focus",
            resources: [
                .copy("Resources/block.txt"),
            ]
        ),
        .testTarget(
            name: "FocusTests",
            dependencies: ["Focus"],
            path: "Tests/FocusTests"
        ),
    ]
)
