// swift-tools-version: 5.9
// LocalFlow shared bridge — optional SPM entry for CI lint / future extraction.
// Primary build path: LocalFlow.xcodeproj (app + keyboard extension targets).

import PackageDescription

let package = Package(
    name: "LocalFlowShared",
    platforms: [
        .iOS(.v17),
    ],
    products: [
        .library(name: "LocalFlowShared", targets: ["LocalFlowShared"]),
    ],
    targets: [
        .target(
            name: "LocalFlowShared",
            path: "Shared"
        ),
    ]
)
