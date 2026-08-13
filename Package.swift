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
        // Pin: 1.16.0+ use the `#Preview` macro and 3.x also uses SwiftUI's `@Entry`.
        // Both need macro plugins that only ship with the full Xcode, so anything
        // above 1.15.0 fails to build with just Command Line Tools. Revisit when
        // Xcode is a build requirement anyway.
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", exact: "1.15.0"),
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
