// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Click2Chat",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Click2Chat", targets: ["Click2Chat"])
    ],
    targets: [
        .executableTarget(
            name: "Click2Chat",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("IOKit")
            ]
        )
    ]
)
