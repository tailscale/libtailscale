// swift-tools-version:6.3
import PackageDescription

let package = Package(
    name: "TailscaleKit",
    // NOTE: `swift build`/`swift test` only work on Linux today, regardless of this
    // declaration: CTailscale's artifactbundle only ships Linux triples (see
    // swift/script/build-artifactbundle.sh). macOS/iOS consumers use
    // swift/TailscaleKit.xcodeproj and the .xcframework built by swift/Makefile's
    // `macos`/`ios-fat` targets instead.
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "TailscaleKit", targets: ["TailscaleKit"])
    ],
    targets: [
        // Built by swift/script/build-artifactbundle.sh, which cross-compiles
        // libtailscale.a per Linux triple (no Go toolchain needed to consume it).
        .binaryTarget(name: "CTailscale", path: "swift/build/TailscaleKit.artifactbundle"),
        .systemLibrary(name: "CTstestControl", path: "swift/Sources/CTstestControl"),
        .target(
            name: "TailscaleKit",
            dependencies: ["CTailscale"],
            path: "swift/TailscaleKit",
            exclude: ["TailscaleKit.h"]
        ),
        .testTarget(
            name: "TailscaleKitTests",
            dependencies: ["TailscaleKit", "CTstestControl"],
            path: "swift/TailscaleKitXCTests",
            // Links against swift/build/libtstestcontrol.a, a copy of
            // tstestcontrol/libtstestcontrol.a with its cgo runtime glue
            // symbols renamed to avoid colliding with libtailscale.a's copy.
            // Run swift/script/fix-tstestcontrol-archive.sh to (re)generate it.
            linkerSettings: [.unsafeFlags(["-L", "swift/build"])]
        ),
    ]
)
