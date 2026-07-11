// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PadScreen",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PadScreenProtocol", targets: ["PadScreenProtocol"]),
        .library(name: "PadScreenHostCore", targets: ["PadScreenHostCore"]),
        .executable(name: "PadScreenHost", targets: ["PadScreenHost"]),
    ],
    targets: [
        .target(name: "PadScreenProtocol"),
        .target(
            name: "VirtualDisplayBridge",
            publicHeadersPath: "include",
            cSettings: [.unsafeFlags(["-fobjc-arc", "-fblocks"])],
            linkerSettings: [
                .linkedFramework("Foundation"),
                .linkedFramework("CoreGraphics"),
            ]
        ),
        .target(
            name: "PadScreenHostCore",
            dependencies: ["PadScreenProtocol", "VirtualDisplayBridge"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("VideoToolbox"),
            ]
        ),
        .executableTarget(
            name: "PadScreenHost",
            dependencies: ["PadScreenHostCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(
            name: "PadScreenProtocolTests",
            dependencies: ["PadScreenProtocol"]
        ),
        .testTarget(
            name: "PadScreenHostCoreTests",
            dependencies: ["PadScreenHostCore", "PadScreenProtocol"]
        ),
    ]
)
