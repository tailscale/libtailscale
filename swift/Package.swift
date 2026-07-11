// swift-tools-version:6.3
import PackageDescription

let package = Package(
    name: "TailscaleKit",
    // NOTE: script/build-artifactbundle.sh builds arm64/x86_64 macOS variants of
    // CTailscale when run on a Darwin host, so `swift build`/`swift test` work on macOS
    // as well as Linux (confirmed on real hardware). iOS still has no SPM path; use
    // TailscaleKit.xcodeproj and the .xcframework built by this Makefile's
    // `ios-fat` target for that.
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "TailscaleKit", targets: ["TailscaleKit"])
    ],
    targets: [
        // Built by script/build-artifactbundle.sh, which builds libtailscale.a
        // per supported triple (Linux via cross-compilation; macOS natively when run
        // on a Mac). No Go toolchain needed to consume it.
        .binaryTarget(name: "CTailscale", path: "build/TailscaleKit.artifactbundle"),
        .systemLibrary(name: "CTstestControl", path: "Sources/CTstestControl"),
        .target(
            name: "TailscaleKit",
            dependencies: ["CTailscale"],
            path: "TailscaleKit",
            exclude: ["TailscaleKit.h"]
        ),
        .testTarget(
            name: "TailscaleKitTests",
            dependencies: ["TailscaleKit", "CTstestControl"],
            path: "TailscaleKitXCTests",
            // Links against build/libtstestcontrol.a, a copy of
            // ../tstestcontrol/libtstestcontrol.a with its cgo runtime glue
            // symbols renamed to avoid colliding with libtailscale.a's copy.
            // Run script/fix-tstestcontrol-archive.sh to (re)generate it.
            linkerSettings: [.unsafeFlags(["-L", "build"])]
        ),
    ]
)
