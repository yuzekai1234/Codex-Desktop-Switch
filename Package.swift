// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CSwitch",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "C-Switch", targets: ["CSwitch"]),
    ],
    targets: [
        .executableTarget(
            name: "CSwitch",
            path: "Sources/CSwitch"
        ),
    ]
)
