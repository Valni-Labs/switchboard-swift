# Changelog

## 0.4.0 - 2026-07-08

- New `SwitchboardLocal` product: on-device inference with MLX behind the same streaming seam as the remote clients. Optional — `import Switchboard` alone still compiles nothing beyond Foundation.
- `LocalModel` is the single entry point: point it at a Hugging Face repo ID, observe its download/load state machine (`notDownloaded` → `downloading` → `downloaded` → `loading` → `ready`), and read tokens from its `provider` exactly as you would from a remote model. No API key required.
- Storage defaults to `Application Support/SwitchboardLocal/Models`; override per model via `storageDirectory` and `directoryName`.
- Requires Apple Silicon (MLX); macOS 14+.

## 0.3.0 - 2026-07-07

- `OpenAIResponsesAdapter` speaks the OpenAI Responses API (`POST /v1/responses`) natively: `input` items, `max_output_tokens`, `reasoning.effort`, function tools, `response.output_text.delta` / `response.function_call_arguments.*` streaming, and usage capture from `response.completed`.
- `WireFormat.openAIResponses` (`openai-responses`) names the new transport; models tagged with it in the picker route through the new adapter.
- `ReasoningEffort` (`minimal` / `low` / `medium` / `high`) is passed per-adapter; omitted from the request when unset.
- **Breaking:** `Client.supportedProviders()` and `SupportedProvider` are removed. The picker model list (`Client.models()`) is the single source for what an account can reach; route on each model's `wire_format` instead.

## 0.2.0 - 2026-07-07

- `Client.models()` returns the server-filtered picker model list (`PickerModel`), including each model's `wire_format`.
- `Client.supportedProviders()` returns the providers the account can reach.
- `WireFormat` constants (`openai-compat`, `anthropic-messages`) name the transport a model speaks, so callers route without inferring from model IDs.
- `anthropic-messages` models go through `AnthropicMessagesAdapter` (`POST /v1/messages`); `openai-compat` models through `SwitchboardProvider` (`POST /v1/chat/completions`).

## 0.1.0 - 2026-07-05

First release of the Switchboard SDK.

- `Switchboard` product: dependency-free remote client (`Client`, `SwitchboardProvider`, `GenericProvider`, `AnthropicMessagesAdapter`) and shared chat, tool, and error types.
- Configurable `baseURL` on every client; `GenericProvider` targets any OpenAI-compatible endpoint.
