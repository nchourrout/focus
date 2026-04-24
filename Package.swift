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
        // Pin: newer versions (1.17.0+) use the `#Preview` macro, which requires the
        // full Xcode (for the PreviewsMacros plugin). 1.16.1 is the last release that
        // builds with just Command Line Tools.
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", exact: "1.14.0"),
    ],
    targets: [
        .executableTarget(
            name: "Focus",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
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
