# Changelog

## 0.2.0 - 2026-07-07

- `Client.models()` returns the server-filtered picker model list (`PickerModel`), including each model's `wire_format`.
- `Client.supportedProviders()` returns the providers the account can reach.
- `WireFormat` constants (`openai-compat`, `anthropic-messages`) name the transport a model speaks, so callers route without inferring from model IDs.
- `anthropic-messages` models go through `AnthropicMessagesAdapter` (`POST /v1/messages`); `openai-compat` models through `SwitchboardProvider` (`POST /v1/chat/completions`).

## 0.1.0 - 2026-07-05

First release of the Switchboard SDK.

- `Switchboard` product: dependency-free remote client (`Client`, `SwitchboardProvider`, `GenericProvider`, `AnthropicMessagesAdapter`) and shared chat, tool, and error types.
- Configurable `baseURL` on every client; `GenericProvider` targets any OpenAI-compatible endpoint.
