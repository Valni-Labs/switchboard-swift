# Changelog

## 0.13.0 - 2026-07-19

- **Breaking**: `GET /v1/models` moved to kind-tagged records (Switchboard-api#321, SwitchboardNative v0.5.0): `PickerModel` (`capabilities` / `wire_format` / `input_formats`) is deleted and `ModelsPage` is now `{ models: [ModelRecord], prices: [String: ModelRecordPrice] }`, built on the generated `SwitchboardNative` contract types. `ModelRecord` is identity plus the tagged profile — `id` and `kind: ProfileByKind` (`anthropic` / `openaiGeneric` / `openaiPro` / `google` / `unrecognized`) — with prices beside the records in a map keyed by model id; display metadata (`display_name`, `context_window`, `max_output_tokens`, `status`) is no longer served on this page. `ModelsPage` drops `Hashable` (the generated native types are not `Hashable`).
- **Breaking**: `Client.models()` returns the full `ModelsPage` instead of `[PickerModel]`. Migration: switch on `record.kind` instead of reading `wire_format`, and read prices from `page.prices[record.id]` or use `composed()`.
- New `ComposedModel` (`id`, `kind`, `price?`) and `ModelsPage.composed()`: the SDK-side join of records with their price by model id, `price` nil for models absent from the price map.
- The SDK absorbs the current `SwitchboardNative` `RouterBody` cases (`google`, `unrecognized`), which the contract bump makes mandatory: `NativeResponse` / `NativeStreamEvent` gain `.google(GoogleGenerateContentResponse)`, `Client.inference` decodes the `google` kind, `Client.streamInference` decodes `google` stream chunks, and `SwitchboardLocal` extracts local prompts from `google` bodies. **Breaking** for exhaustive switches over `NativeResponse` / `NativeStreamEvent`: add a `.google` arm.
- New `SwitchboardError.unsupportedKind(String)`: thrown for `unrecognized` bodies everywhere, and by `InferenceProvider` streaming a `google` body — the google stream reducer (`GenerationChunk` reduction) is deliberately not built yet; it lands with the native-routing consumer migration alongside server-side google inference, which the API's implemented-kind gate still rejects.

## 0.12.0 - 2026-07-17

- `ToolCallMode.prompt` is deprecated (deprecation only — no behavior change; the case still works and still round-trips through `Codable` and `allCases`). Native structured tool calling is the proven mode: tool-aware servers move the tool grammar out of text content into structured tool calls, which prompt-mode parsing never sees, so an agent loop in prompt mode runs blind. Migration: pass `.native` (already the `GenericProvider` default) unless the endpoint has no tool parser — a parserless endpoint is the only remaining legitimate habitat for `.prompt`, which is why `SwitchboardLocal.ModelProvider` (on-device generation, no server in the path) still prefers it.

## 0.11.0 - 2026-07-17

- **Breaking**: `UsageRecord.costMicros` is renamed `costMicroCents` (wire field `cost_micro_cents`). The unit is unchanged and was always micro-cents (10^-8 dollars, 100,000,000 per dollar); the old name misread as micro-dollars and caused a 100x misinterpretation, so the org standard now bakes the true unit into the name. Regenerated from Switchboard-api's `src/apiTypes/usage.ts`.
- **Breaking**: `PickerModel` moves into the generated apiTypes channel (`SwitchboardAPITypes.swift`). It is now `Codable` and `wireFormat` is required: the implicit `"openai-compat"` default for an absent `wire_format` is gone, matching the server contract which always sends it. `Client.models()` decodes the generated `ModelsPage` envelope.
- New generated contract types `ModelsPage` (`GET /v1/models`, the path `Client.models()` calls), `BalancePage` (`GET /v1/balance`, wire fields `company_id` / `balance_micro_cents`), and `ErrorEnvelope` (the `code` / `error` typed-error envelope every Switchboard error returns, `SWB-XXXX` codes).
- All generated apiTypes conform to `Hashable`.

## 0.10.0 - 2026-07-17

- `Client.usage(endUserID:since:until:limit:beforeAt:beforeID:)` reads the customer's per-request usage records from `GET /v1/switchboard/usage` — public `UsageRecord` (token counts incl. cache and reasoning, plus booked `costMicros`) and `UsagePage` (cursor pagination via `nextBeforeAt` / `nextBeforeId`). The types are GENERATED from Switchboard-api's `src/apiTypes/usage.ts` (`npm run codegen:swift-api` there emits `Sources/Switchboard/SwitchboardAPITypes.swift`, committed here — never hand-edit); this is the first schema in the apiTypes channel, separate from the SwitchboardNative routing contract. Additive; billed cost comes from Switchboard's own metering instead of client-side price math.

## 0.9.0 - 2026-07-16

- Regenerated `SwitchboardNative`: every generated discriminated union gains a `case unrecognized(String)` catch-all carrying the wire discriminator, re-encoding as `{"<discriminatorKey>": "<tag>"}`. Mixed unions of bare strings and keyed objects (`OpenAIToolChoice`, `OpenAIResponsesToolChoice`) split the catch-all by wire origin so re-encoding round-trips the decoded shape: `case unrecognized(String)` for an unknown bare string (re-encodes as a string) and `case unrecognizedObject(String)` for an unknown object discriminator (re-encodes as an object with the discriminator key). Unknown tags decode into these instead of throwing, so a stream carrying event types this SDK predates no longer dies with `decodingFailed` — the additive-only contract rule applied to decoding. **Breaking** for exhaustive switches over the generated unions: add an `.unrecognized` arm (plus `.unrecognizedObject` on the mixed unions).
- Regenerated `SwitchboardRouter` now matches the required envelope contract shipped in 0.8.0 (every request carries `user_id`, `time`, `idempotency_key`, `kind`): `idempotencyKey` is `String`, not `String?`, and the initializer no longer defaults it to `nil`. **Breaking** for code constructing `SwitchboardRouter` directly: pass an idempotency key (`InferenceProvider` already generates one per request). The server rejects envelopes without `idempotency_key`, so the optional only deferred the failure to the wire.
- `OpenAIResponsesStreamEvent` models nine more Responses API stream events: `response.in_progress`, `response.output_item.added`, `response.content_part.added` / `.done`, `response.output_text.done`, `response.function_call_arguments.delta` / `.done`, `response.reasoning_summary_text.delta`, and `response.incomplete` (with the `OpenAIResponsesStreamContentPart` payload union).
- `InferenceProvider` streaming an `openai_pro` body now surfaces reasoning summary deltas as `GenerationChunk.reasoning` and treats `response.incomplete` as stream completion (capturing its usage). All other newly modeled events and `.unrecognized` are skipped, not fatal.
- The `Switchboard` target re-exports `SwitchboardNative`: `import Switchboard` alone now exposes the generated contract types (`SwitchboardRouter`, `RouterBody`, `AnthropicMessagesRequest`, and the rest); a second `import SwitchboardNative` is no longer needed. The standalone `SwitchboardNative` product remains for types-only consumers.
- `GenerationUsage` gains `cacheCreationTokens` and `cacheReadTokens` (both default `0`, so existing constructions are source-compatible). The Anthropic stream reducer captures `cache_creation_input_tokens` / `cache_read_input_tokens` from `message_start`; the OpenAI chat and responses reducers map `prompt_tokens_details` / `input_tokens_details` (`cached_tokens`, `cache_write_tokens`) where present.
- The `Switchboard` target re-exports `SwitchboardNative`: `import Switchboard` alone now exposes the generated contract types (`SwitchboardRouter`, `RouterBody`, `AnthropicMessagesRequest`, and the rest); a second `import SwitchboardNative` is no longer needed.
- The generated native contract moved to the sibling `SwitchboardNative` repo, consumed as a SwiftPM path dependency (`../SwitchboardNative`) and re-exported unchanged, so `import Switchboard` still carries every contract type. This package no longer ships a standalone `SwitchboardNative` product — types-only consumers depend on the `SwitchboardNative` package directly.

## 0.8.0 - 2026-07-16

- **Breaking**: the OpenAI-core surface is removed — `Inference.Request` / `Inference.Response` / `Inference.Frame` / `Inference.JSON`, `Chat.Message` / `Chat.Tool` / `Chat.ToolCall` / `Chat.Message.Content`, `ChatMessage`, `ToolSchema`, `NativeStreamChunk`, `RawStreamChunk`, `WireFormat`, `Model`, and `GenericWireMessage` are deleted. Requests are now the provider's native body: build a `RouterBody` from the generated `SwitchboardNative` types (`AnthropicMessagesRequest`, `OpenAIChatRequest`, `OpenAIResponsesRequest`) and pass it to a provider.
- **Breaking**: `RawGenerationProvider` is now native-in: `generate(_ body: RouterBody) -> AsyncThrowingStream<GenerationChunk, Error>` replaces `generateRaw(messages:)` / `generateNative(messages:tools:)`. `GenerationChunk` carries `text`, `reasoning`, `toolCall`, and `paywall`; usage lands on `lastUsage`.
- **Breaking**: `InferenceProvider` requires a non-empty `endUserID` at construction (`ProviderError.missingEndUserID`) and no longer takes `modelID` — the model rides in the native body. Every request carries the full required envelope (`user_id`, `time`, generated `idempotency_key`).
- **Breaking**: `Client.inference(_:)` / `Client.streamInference(_:)` take a `SwitchboardRouter` and return `NativeResponse` / `NativeStreamEvent` (the provider's native response types, symmetric with the request kind).
- **Breaking**: `GenericProvider` accepts only the `openai_generic` kind and no longer takes `modelID`.
- New target `SwitchboardNative`: the generated native contract (zero dependencies) — consumable standalone by products that need the types without the SDK runtime.
- `SwitchboardLocal.ModelProvider` conforms to the native seam: it extracts the prompt from any `kind` body and runs it on-device; native `max_tokens` / `temperature` / `top_p` override `InferenceConfig` defaults.

## 0.7.0 - 2026-07-10

- **Breaking**: the legacy OpenAI chat-completions passthrough is removed. `Client.chatCompletions(_:)` / `Client.streamChatCompletions(_:)`, `SwitchboardProvider`, and the chat-completions wire types `Chat.Request` / `Chat.Response` / `Chat.StreamChunk` (with `Chat.ToolCallDelta`) are deleted. The only Switchboard-touching path is now `InferenceProvider` → `POST /v1/switchboard/inference`. Migrate any remaining `SwitchboardProvider` usage to `InferenceProvider` (same constructor shape).
- Unchanged: `InferenceProvider`, `GenericProvider`, `Client.inference(_:)` / `Client.streamInference(_:)`, `Client.models()`, and the shared semantic types `Chat.Message` / `Chat.Message.Content` / `Chat.Tool` / `Chat.ToolCall` / `ChatMessage`, which the branded path reuses.

## 0.6.0 - 2026-07-08

- **Breaking**: `AnthropicMessagesAdapter` and `OpenAIResponsesAdapter` are removed (deprecated in 0.5.0). Migrate to `InferenceProvider`: one constructor serves every model, with provider-specific capability via `Inference.Request.providerOptions`.
- `SwitchboardProvider` is deprecated; `InferenceProvider` is the replacement. Its `SwitchboardError` → `ProviderError` translation moved to an internal home unchanged.

## 0.5.0 - 2026-07-08

- `InferenceProvider`: a `RawGenerationProvider` over the unified envelope, the drop-in replacement for the wire adapters (frame mapping, tool-call assembly server-side, usage capture, same error translation).
- `AnthropicMessagesAdapter` and `OpenAIResponsesAdapter` are deprecated; migrate to `InferenceProvider`.
- New unified inference surface targeting `POST /v1/switchboard/inference`: `Client.inference(_:)` and `Client.streamInference(_:)` with `Inference.Request` (unified core + `providerOptions` verbatim passthrough + `includeNative`), the `Inference.Frame` grammar (`textDelta`, `reasoningDelta`, `toolCall`, `usage`, `done`, `native`; unknown frame kinds are skipped per the forward-compatibility contract), and `Inference.Response` (completion shape with `nativeParts` for provider artifacts).
- `Inference.JSON`: public Codable JSON value type used for `providerOptions` and native payloads.
- New `SwitchboardError.streamError(code:message:detail:)` for in-stream error frames. **Breaking** for exhaustive switches over `SwitchboardError`.

## 0.4.0 - 2026-07-08

Breaking: `SwitchboardLocal` reshaped into a product-neutral on-device inference library.

- New single entry point `LocalModel`: descriptor plus download/load state machine exposing a ready-to-use `provider` (`RawGenerationProvider`). Replaces the `LocalModelManager` + `LanguageModelManager` wiring.
- Removed Valni-app internals from the product: `LanguageModelManager`, `ModelRegistry`/`RegisteredModel`/`ModelRegistryError`, `ClassifierModelManager`, `SwitchLayer` (with bundled tokenizer resources and `training/`), `AgentEvent`, `AgentStep`, `StreamMarker`, `ValniAssembledPrompt`, `ModelManagerProtocol`/`ModelConfig`. These move to the Valni Mac app.
- `HFModelHost` no longer ships hardcoded model or classifier repo IDs; only generic list/download by Hugging Face repo ID remains.
- Model storage defaults to `Application Support/SwitchboardLocal/Models`, configurable per `LocalModel` via `storageDirectory` and `directoryName`.

## 0.1.0 - 2026-07-05

First release of the Switchboard SDK line.

- `Switchboard` product: dependency-free remote client (`Client`, `SwitchboardProvider`, `GenericProvider`, `AnthropicMessagesAdapter`) and shared chat, tool, and error types.
- `SwitchboardLocal` product: on-device MLX inference, Hugging Face model downloads, and the model registry, split out so remote-only integrations compile nothing they do not use.
- Configurable `baseURL` on every client; `GenericProvider` targets any OpenAI-compatible endpoint.
- Removed the unused `RemoteInference` target and the Forage/web-pipeline dependency.

Earlier history under the ValniAI name is unversioned; the pre-rename `v1.0.0` tag was retired.
