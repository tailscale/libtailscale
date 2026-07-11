// swift-tools-version:6.3
import PackageDescription

let package = Package(
    name: "TailscaleKitCLI",
    // Linux only: this depends on the root package's CTailscale binaryTarget, which
    // only ships Linux triples today. See ../../../Package.swift.
    dependencies: [
        .package(name: "TailscaleKit", path: "../../.."),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.8.0"),
    ],
    targets: [
        .executableTarget(
            name: "tsdemo",
            dependencies: [
                .product(name: "TailscaleKit", package: "TailscaleKit"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        )
    ]
)
