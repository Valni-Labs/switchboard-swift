# Switchboard

One API for every frontier model. This is the Swift SDK for [Switchboard](https://valni.ai/quickstart), the unified inference API.

> **Alpha preview.** APIs may change between 0.x releases. The package reaches 1.0.0 when it is battle-tested.

## Install

```swift
dependencies: [
    .package(url: "https://github.com/Benovi-Labs/switchboard-swift", from: "0.1.0")
],
targets: [
    .target(name: "MyApp", dependencies: [
        .product(name: "Switchboard", package: "Switchboard"),
    ])
]
```

The `Switchboard` product has no dependencies beyond Foundation.

## Quickstart

Create a key at [valni.ai/platform](https://valni.ai/platform/account?tab=switchboard). Keys start with `swb_` and are shown once at mint. Keys are server credentials: keep them in your backend's environment, never in a shipped client.

```swift
import Switchboard

func askSwitchboard() async throws {
    guard let apiKey = ProcessInfo.processInfo.environment["SWITCHBOARD_API_KEY"] else {
        fatalError("Set SWITCHBOARD_API_KEY in the environment")
    }
    let client = Client(apiKey: apiKey)

    let response = try await client.chatCompletions(Chat.Request(
        model: "anthropic/claude-sonnet-4-5",
        messages: [
            .system("You are a senior Swift engineer."),
            .user("Write a one-liner that flattens [[Int]] into [Int]."),
        ],
        user: "end-user-id"
    ))
    print(response)
}
```

Streaming:

```swift
func streamSwitchboard(client: Client) async throws {
    for try await chunk in client.streamChatCompletions(Chat.Request(
        model: "anthropic/claude-sonnet-4-5",
        messages: [.user("Hello")],
        user: "end-user-id"
    )) {
        print(chunk)
    }
}
```

The `user` field names the end user the request is attributed to for usage reporting. Register end users in the [platform portal](https://valni.ai/platform/account?tab=switchboard); balances are funded at the company level.

## Bring your own endpoint

The clients speak standard wire formats, so the same code can target infrastructure you run yourself:

- `Client(apiKey:baseURL:)` accepts any base URL; Switchboard is only the default.
- `GenericProvider` posts to any OpenAI-compatible `chat/completions` endpoint (vLLM, TGI, OpenAI) with your own key. For unauthenticated local servers pass an empty `apiKey`; the `Authorization` header is omitted.
- `AnthropicMessagesAdapter` targets any endpoint speaking the Anthropic Messages shape.

Calls to your own endpoints never touch Switchboard.

## Products

| Product | What it is | Dependencies |
|---|---|---|
| `Switchboard` | Remote client and shared types. The SDK. | none |

## License

Copyright (c) 2026 Benovi Labs, Inc. See [LICENSE](LICENSE).
