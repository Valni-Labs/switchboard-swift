// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Switchboard",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Switchboard", targets: ["Switchboard"]),
    ],
    targets: [
        .target(name: "Switchboard"),
        .testTarget(name: "SwitchboardTests", dependencies: ["Switchboard"]),
    ]
)
