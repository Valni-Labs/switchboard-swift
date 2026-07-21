# Switchboard

[![Release](https://img.shields.io/github/v/release/valni-labs/switchboard-swift?sort=semver)](https://github.com/valni-labs/switchboard-swift/releases) [![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org) [![Platforms](https://img.shields.io/badge/platforms-macOS%2014%2B-blue.svg)](https://github.com/valni-labs/switchboard-swift)

This is the Swift SDK for [Switchboard](https://valni.ai/quickstart): unified inference with per-end-user metering, spend controls, and billing built in.

> **Pre-1.0.** APIs may still change between 0.x releases; the package reaches 1.0.0 once it is battle-tested.

## What Switchboard does

Calling a model is the easy part. Serving inference to end users means running a whole column of jobs underneath that call, and Switchboard ships all of them behind one `swb_` key:

1. **Move the request.** One endpoint for every model in the catalog. Linecard, the configuration layer, keeps each model's wire format, parameters, and current price up to date, so one normalized request always lands correctly and provider changes never become your migration.
2. **Watch it.** Token counts, cost, and typed errors for every request, visible per end user in the platform portal as they happen.
3. **Meter it.** Billing-grade cost per request, priced exactly as the provider bills it: cache writes, cache reads, and cached-prompt discounts included, committed to the ledger before the response returns.
4. **Control it and hold the money.** Prepaid credits draw down an append-only ledger where balance is always credits minus usage, auditable per line and enforced before the call, so spend can never run past what was funded. Daily and monthly spend caps, per-end-user rate limits, and model policies stand in front of the same gate.
5. **Attribute it.** The `user` field lands every debit on that end user's ledger. Per-user economics are a query, not a data project.
6. **Bill it.** Itemized per-end-user statements come from the same ledger the requests wrote, not from a second system you reconcile.
7. **Settle it.** Every charge ties out against the provider's actual invoice on our side. The books close; you never reconcile anything.

One fee, charged on credit top-ups. Everything above is included.

## Install

```swift
dependencies: [
    .package(url: "https://github.com/valni-labs/switchboard-swift", from: "0.13.0")
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

Every model in the catalog is served through one endpoint, `POST /v1/switchboard/inference`. Requests are provider-native: you write the model's own wire format (Anthropic Messages, OpenAI Chat, OpenAI Responses) inside a routing envelope, so nothing is translated and no provider capability is out of reach:

```swift
import Switchboard

func askSwitchboard() async throws {
    guard let apiKey = ProcessInfo.processInfo.environment["SWITCHBOARD_API_KEY"] else {
        fatalError("Set SWITCHBOARD_API_KEY in the environment")
    }
    let client = Client(apiKey: apiKey)

    let response = try await client.inference(SwitchboardRouter(
        userId: "end-user-id",
        time: Date().ISO8601Format(),
        idempotencyKey: UUID().uuidString,
        kind: .anthropic(AnthropicMessagesRequest(
            model: "claude-sonnet-5",
            messages: [
                AnthropicMessage(role: .user, content: .string("Write a one-liner that flattens [[Int]] into [Int]."))
            ],
            maxTokens: 1024,
            system: .text("You are a senior Swift engineer.")
        ))
    ))

    if case .anthropic(let message) = response {
        for block in message.content {
            if case .text(let text) = block { print(text.text) }
        }
    }
}
```

Streaming yields the provider's own stream events, decoded and typed:

```swift
func streamSwitchboard(client: Client) async throws {
    let router = SwitchboardRouter(
        userId: "end-user-id",
        time: Date().ISO8601Format(),
        idempotencyKey: UUID().uuidString,
        kind: .anthropic(AnthropicMessagesRequest(
            model: "claude-sonnet-5",
            messages: [AnthropicMessage(role: .user, content: .string("Hello"))],
            maxTokens: 1024
        ))
    )
    for try await event in client.streamInference(router) {
        if case .anthropic(.contentBlockDelta(let delta)) = event,
           case .textDelta(let text) = delta.delta {
            print(text.text, terminator: "")
        }
    }
}
```

Model IDs are catalog IDs (`claude-sonnet-5`, `gpt-5.5`, …). `client.models()` returns the live catalog as kind-tagged records with current prices beside them; `page.composed()` joins each record with its price. The record's `kind` tells you which native request type the model speaks.

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

    let body = RouterBody.anthropic(AnthropicMessagesRequest(
        model: model.displayName,
        messages: [AnthropicMessage(role: .user, content: .string("Hello"))],
        maxTokens: 512
    ))
    for try await chunk in model.provider.generate(body) {
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
