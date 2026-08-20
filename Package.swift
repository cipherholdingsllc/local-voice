// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "local-voice",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "local-voice", targets: ["open-wispr"]),
    ],
    targets: [
        .target(
            name: "OpenWisprLib",
            path: "Sources/OpenWisprLib",
            linkerSettings: [
                .linkedFramework("CoreAudio"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("AppKit"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("IOKit"),
            ]
        ),
        .executableTarget(
            name: "open-wispr",
            dependencies: ["OpenWisprLib"],
            path: "Sources/OpenWispr"
        ),
        .testTarget(
            name: "OpenWisprTests",
            dependencies: ["OpenWisprLib"],
            path: "Tests/OpenWisprTests"
        ),
    ]
)
