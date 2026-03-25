// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HeadSafe",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "HeadSafe",
            path: "Sources",
            linkerSettings: [
                .linkedFramework("CoreAudio"),
                .linkedFramework("IOBluetooth"),
                .linkedFramework("AppKit"),
            ]
        ),
    ]
)
