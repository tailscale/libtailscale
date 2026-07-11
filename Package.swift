// swift-tools-version:6.3
import PackageDescription

let package = Package(
    name: "TailscaleKit",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "TailscaleKit", targets: ["TailscaleKit"])
    ],
    targets: [
        .systemLibrary(name: "CTailscale", path: "swift/Sources/CTailscale"),
        .systemLibrary(name: "CTstestControl", path: "swift/Sources/CTstestControl"),
        .target(
            name: "TailscaleKit",
            dependencies: ["CTailscale"],
            path: "swift/TailscaleKit",
            exclude: ["TailscaleKit.h"],
            linkerSettings: [.unsafeFlags(["-L", "."])]
        ),
        .testTarget(
            name: "TailscaleKitTests",
            dependencies: ["TailscaleKit", "CTstestControl"],
            path: "swift/TailscaleKitXCTests",
            linkerSettings: [.unsafeFlags(["-L", "tstestcontrol"])]
        ),
    ]
)
