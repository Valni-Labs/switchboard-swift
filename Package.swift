// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Switchboard",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Switchboard", targets: ["Switchboard"]),
        .library(name: "SwitchboardLocal", targets: ["SwitchboardLocal"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.31.3"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "3.31.3"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.3"),
    ],
    targets: [
        .target(name: "SwitchboardNative"),
        .target(
            name: "Switchboard",
            dependencies: [
                "SwitchboardNative",
            ]
        ),
        .target(
            name: "SwitchboardLocal",
            dependencies: [
                "Switchboard",
                "SwitchboardNative",
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "Hub", package: "swift-transformers"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ]
        ),
        .testTarget(name: "SwitchboardTests", dependencies: ["Switchboard"]),
        .testTarget(name: "SwitchboardLocalTests", dependencies: ["SwitchboardLocal"]),
    ]
)
