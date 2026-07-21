import Foundation
import SwitchboardNative

struct NativeStreamReduction {
    var chunks: [GenerationChunk] = []
    var usage: GenerationUsage?
    var completed = false
    var streamError: SwitchboardError?
}

protocol NativeStreamReducer {
    mutating func reduce(event: NativeStreamEvent) -> NativeStreamReduction
}

struct AnthropicStreamReducer: NativeStreamReducer {
    private var pendingToolID: String?
    private var pendingToolName: String?
    private var pendingToolArguments = ""
    private var pendingToolIndex: Int?
    private var inputTokens = 0
    private var cacheCreationTokens = 0
    private var cacheReadTokens = 0

    mutating func reduce(event: NativeStreamEvent) -> NativeStreamReduction {
        var reduction = NativeStreamReduction()
        guard case .anthropic(let anthropicEvent) = event else { return reduction }
        switch anthropicEvent {
        case .messageStart(let start):
            inputTokens = Int(start.message.usage.inputTokens)
            cacheCreationTokens = Int(start.message.usage.cacheCreationInputTokens ?? 0)
            cacheReadTokens = Int(start.message.usage.cacheReadInputTokens ?? 0)
        case .contentBlockStart(let start):
            if case .toolUse(let toolUse) = start.contentBlock {
                pendingToolID = toolUse.id
                pendingToolName = toolUse.name
                pendingToolArguments = ""
                pendingToolIndex = Int(start.index)
            }
        case .contentBlockDelta(let delta):
            switch delta.delta {
            case .textDelta(let text):
                reduction.chunks.append(.text(text.text))
            case .thinkingDelta(let thinking):
                reduction.chunks.append(.reasoning(thinking.thinking))
            case .inputJsonDelta(let partial):
                if pendingToolIndex == Int(delta.index) {
                    pendingToolArguments += partial.partialJson
                }
            case .signatureDelta:
                break
            case .unrecognized:
                break
            }
        case .contentBlockStop(let stop):
            if let id = pendingToolID, let name = pendingToolName, pendingToolIndex == Int(stop.index) {
                reduction.chunks.append(.toolCall(id: id, name: name, argumentsJSON: pendingToolArguments))
                pendingToolID = nil
                pendingToolName = nil
                pendingToolArguments = ""
                pendingToolIndex = nil
            }
        case .messageDelta(let delta):
            reduction.usage = GenerationUsage(
                inputTokens: inputTokens,
                outputTokens: Int(delta.usage.outputTokens),
                cacheCreationTokens: cacheCreationTokens,
                cacheReadTokens: cacheReadTokens,
            )
        case .messageStop:
            reduction.completed = true
        case .ping:
            break
        case .error(let failure):
            reduction.streamError = .streamError(code: failure.error.type, message: failure.error.message, detail: nil)
        case .unrecognized:
            break
        }
        return reduction
    }
}

struct OpenAIChatStreamReducer: NativeStreamReducer {
    private struct PendingToolCall {
        var id: String?
        var name: String?
        var arguments = ""
    }

    private var pendingToolCalls: [Int: PendingToolCall] = [:]

    mutating func reduce(event: NativeStreamEvent) -> NativeStreamReduction {
        var reduction = NativeStreamReduction()
        guard case .openaiGeneric(let chunk) = event else { return reduction }
        for choice in chunk.choices {
            if let text = choice.delta.content, !text.isEmpty {
                reduction.chunks.append(.text(text))
            }
            for toolCallDelta in choice.delta.toolCalls ?? [] {
                let index = Int(toolCallDelta.index)
                var pending = pendingToolCalls[index] ?? PendingToolCall()
                if let id = toolCallDelta.id { pending.id = id }
                if let name = toolCallDelta.function?.name { pending.name = name }
                if let fragment = toolCallDelta.function?.arguments { pending.arguments += fragment }
                pendingToolCalls[index] = pending
            }
            if choice.finishReason != nil {
                reduction.chunks.append(contentsOf: drainPendingToolCalls())
            }
        }
        if let usage = chunk.usage {
            reduction.usage = GenerationUsage(
                inputTokens: Int(usage.promptTokens),
                outputTokens: Int(usage.completionTokens),
                cacheCreationTokens: Int(usage.promptTokensDetails?.cacheWriteTokens ?? 0),
                cacheReadTokens: Int(usage.promptTokensDetails?.cachedTokens ?? 0),
            )
        }
        return reduction
    }

    mutating func drainPendingToolCalls() -> [GenerationChunk] {
        let calls = pendingToolCalls
            .sorted { $0.key < $1.key }
            .compactMap { _, pending -> GenerationChunk? in
                guard let id = pending.id, let name = pending.name else { return nil }
                return .toolCall(id: id, name: name, argumentsJSON: pending.arguments)
            }
        pendingToolCalls = [:]
        return calls
    }
}

struct OpenAIResponsesStreamReducer: NativeStreamReducer {
    mutating func reduce(event: NativeStreamEvent) -> NativeStreamReduction {
        var reduction = NativeStreamReduction()
        guard case .openaiPro(let responsesEvent) = event else { return reduction }
        switch responsesEvent {
        case .responseCreated, .responseInProgress:
            break
        case .responseOutputItemAdded, .responseContentPartAdded, .responseContentPartDone:
            break
        case .responseOutputTextDelta(let delta):
            reduction.chunks.append(.text(delta.delta))
        case .responseOutputTextDone:
            break
        case .responseReasoningSummaryTextDelta(let delta):
            reduction.chunks.append(.reasoning(delta.delta))
        case .responseFunctionCallArgumentsDelta, .responseFunctionCallArgumentsDone:
            break
        case .responseOutputItemDone(let done):
            if case .functionCall(let call) = done.item {
                reduction.chunks.append(.toolCall(id: call.callId, name: call.name, argumentsJSON: call.arguments))
            }
        case .responseCompleted(let completed):
            reduction.usage = GenerationUsage(
                inputTokens: Int(completed.response.usage.inputTokens),
                outputTokens: Int(completed.response.usage.outputTokens),
                cacheCreationTokens: Int(completed.response.usage.inputTokensDetails?.cacheWriteTokens ?? 0),
                cacheReadTokens: Int(completed.response.usage.inputTokensDetails?.cachedTokens ?? 0),
            )
            reduction.completed = true
        case .responseIncomplete(let incomplete):
            if let usage = incomplete.response.usage {
                reduction.usage = GenerationUsage(
                    inputTokens: Int(usage.inputTokens),
                    outputTokens: Int(usage.outputTokens),
                )
            }
            reduction.completed = true
        case .responseFailed(let failed):
            reduction.streamError = .streamError(
                code: "response.failed",
                message: failed.response.error?.message ?? "The response failed",
                detail: nil,
            )
        case .error(let failure):
            reduction.streamError = .streamError(code: "error", message: failure.message, detail: nil)
        case .unrecognized:
            break
        }
        return reduction
    }
}

enum NativeStreamDecoding {
    static let doneSentinel = "[DONE]"

    static func reducer(for body: RouterBody) throws -> any NativeStreamReducer {
        switch body {
        case .anthropic: return AnthropicStreamReducer()
        case .openaiGeneric: return OpenAIChatStreamReducer()
        case .openaiPro: return OpenAIResponsesStreamReducer()
        case .google: throw SwitchboardError.unsupportedKind(kind: "google")
        case .unrecognized(let kind): throw SwitchboardError.unsupportedKind(kind: kind)
        }
    }

    static func decodeEvent(for body: RouterBody, payload: Data, decoder: JSONDecoder) throws -> NativeStreamEvent {
        switch body {
        case .anthropic:
            return .anthropic(try decoder.decode(AnthropicStreamEvent.self, from: payload))
        case .openaiGeneric:
            return .openaiGeneric(try decoder.decode(OpenAIChatChunk.self, from: payload))
        case .openaiPro:
            return .openaiPro(try decoder.decode(OpenAIResponsesStreamEvent.self, from: payload))
        case .google:
            return .google(try decoder.decode(GoogleGenerateContentResponse.self, from: payload))
        case .unrecognized(let kind):
            throw SwitchboardError.unsupportedKind(kind: kind)
        }
    }

    static func requiresDoneSentinel(_ body: RouterBody) -> Bool {
        if case .openaiGeneric = body { return true }
        return false
    }
}
