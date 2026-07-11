// swift-tools-version:6.3
import PackageDescription

let swiftSettings: [SwiftSetting] = [
    /// https://github.com/apple/swift-evolution/blob/main/proposals/0335-existential-any.md
    /// Require `any` for existential types.
    .enableUpcomingFeature("ExistentialAny")
]

let package = Package(
    name: "TailscaleKit",
    platforms: [.macOS(.v15), .iOS(.v18)],  // same as xcodeproj
    products: [
        .library(name: "TailscaleKit", targets: ["TailscaleKit"])
    ],
    targets: [
        // No Go toolchain needed to consume it.
        .binaryTarget(name: "CTailscale", path: "build/TailscaleKit.artifactbundle"),
        .systemLibrary(name: "CTstestControl", path: "Sources/CTstestControl"),
        .target(
            name: "TailscaleKit",
            dependencies: ["CTailscale"],
            path: "TailscaleKit",
            exclude: ["TailscaleKit.h"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "TailscaleKitTests",
            dependencies: ["TailscaleKit", "CTstestControl"],
            path: "TailscaleKitXCTests",
            swiftSettings: swiftSettings,
            // Links against build/libtstestcontrol.a, a copy with its cgo runtime
            // symbols renamed to avoid colliding with libtailscale.a's copy.
            linkerSettings: [.unsafeFlags(["-L", "build"])]
        ),
    ]
)
