# Switchboard

[![Release](https://img.shields.io/github/v/release/valni-labs/switchboard-swift?sort=semver)](https://github.com/valni-labs/switchboard-swift/releases) [![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org) [![Platforms](https://img.shields.io/badge/platforms-macOS%2014%2B-blue.svg)](https://github.com/valni-labs/switchboard-swift)

One API for every frontier model. This is the Swift SDK for [Switchboard](https://valni.ai/quickstart), the unified inference API.

> **Pre-1.0.** APIs may still change between 0.x releases; the package reaches 1.0.0 once it is battle-tested.

## Install

```swift
dependencies: [
    .package(url: "https://github.com/valni-labs/switchboard-swift", from: "0.6.0")
],
targets: [
    .target(name: "MyApp", dependencies: [
        .product(name: "Switchboard", package: "switchboard-swift"),
    ])
]
```

The `Switchboard` product has no dependencies beyond Foundation.

## Quickstart

Create a key at [valni.ai/platform](https://valni.ai/platform/account/switchboard). Keys start with `swb_` and are shown once at mint. Keys are server credentials: keep them in your backend's environment, never in a shipped client.

Every model in the catalog is served through one endpoint, `POST /v1/switchboard/inference`:

```swift
import Switchboard

func askSwitchboard() async throws {
    guard let apiKey = ProcessInfo.processInfo.environment["SWITCHBOARD_API_KEY"] else {
        fatalError("Set SWITCHBOARD_API_KEY in the environment")
    }
    let client = Client(apiKey: apiKey)

    let response = try await client.inference(Inference.Request(
        model: "claude-sonnet-5",
        messages: [
            .system("You are a senior Swift engineer."),
            .user("Write a one-liner that flattens [[Int]] into [Int]."),
        ],
        user: "end-user-id"
    ))
    print(response.choices.first?.message.content ?? "")
}
```

Streaming yields `Inference.Frame` values (`textDelta`, `reasoningDelta`, `toolCall`, `usage`, `done`, `native`):

```swift
func streamSwitchboard(client: Client) async throws {
    for try await frame in client.streamInference(Inference.Request(
        model: "claude-sonnet-5",
        messages: [.user("Hello")],
        user: "end-user-id"
    )) {
        if case .textDelta(let text) = frame {
            print(text, terminator: "")
        }
    }
}
```

Model IDs are catalog IDs (`claude-sonnet-5`, `gpt-5.5`, `deepseek-v4-flash`, …); list the live catalog with `client.models()`. Provider-specific capability rides `Inference.Request.providerOptions` on the way in; pass `includeNative: true` to receive provider-native artifacts back as `native` frames.

The `user` field names the end user the request is attributed to. Usage is reported per end user; billing always draws from your company balance. Register end users in the [platform portal](https://valni.ai/platform/account/switchboard) or provision them from your backend with an admin key.

## On-device models

`SwitchboardLocal` runs open-weight models on the Mac itself (MLX, Apple Silicon, macOS 14+). A local model plugs into the same streaming interface as the remote clients, so one code path serves both — and it works with no API key and no network.

```swift
import SwitchboardLocal

@MainActor
func runLocalModel() async throws {
    let model = LocalModel(
        huggingFaceRepoID: "mlx-community/Qwen2.5-3B-Instruct-4bit",
        displayName: "Qwen 2.5 3B"
    )
    model.download()
    while !model.state.isReady { try await Task.sleep(for: .milliseconds(250)) }
    for try await chunk in model.provider.generateRaw(messages: [ChatMessage(role: .user, text: "Hello")]) {
        if case .text(let piece) = chunk { print(piece, terminator: "") }
    }
}
```

`LocalModel.state` is `@Published` — bind it to UI for download progress and readiness instead of polling. Models download once to `Application Support/SwitchboardLocal/Models` and load from disk afterwards.

## Products

| Product | What it is | Dependencies |
|---|---|---|
| `Switchboard` | Remote client and shared types. The SDK. | none |
| `SwitchboardLocal` | On-device inference: `LocalModel` downloads an open-weight model from Hugging Face, manages its lifecycle, and exposes a ready-to-use provider running on MLX. | mlx-swift, mlx-swift-lm, swift-transformers |

Most integrations need only `Switchboard`. Add `SwitchboardLocal` when you want models running on the device itself.

## License

Copyright (c) 2026 Benovi Labs, Inc. See [LICENSE](LICENSE).
