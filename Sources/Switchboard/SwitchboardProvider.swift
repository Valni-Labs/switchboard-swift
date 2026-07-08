import Foundation

public final class SwitchboardProvider: RawGenerationProvider, @unchecked Sendable {
    public let modelID: String

    public var endUserID: String?

    public let supportsVision: Bool
    public private(set) var lastUsage: GenerationUsage?

    private let client: Client
    private let typedModel: Model
    private let catalogContextWindow: Int?
    private var currentTask: Task<Void, Never>?

    public var contextLimits: ModelLimits {
        guard let window = catalogContextWindow else { return .remoteDefault }
        return ModelLimits(contextWindow: window, budgetTokens: ModelLimits.remoteDefault.budgetTokens)
    }
    public var preferredToolCallMode: ToolCallMode { .native }

    public static let defaultBaseURL = URL(string: "https://switchboard.valni.app/v1")!

    private static let nonEnvelopeBodyPreviewLimit = 256

    public init(
        modelID: String,
        apiKey: String,
        endUserID: String? = nil,
        baseURL: URL = SwitchboardProvider.defaultBaseURL,
        supportsVision: Bool = false,
        contextWindow: Int? = nil
    ) {
        self.modelID = modelID
        self.endUserID = endUserID
        self.supportsVision = supportsVision
        self.catalogContextWindow = contextWindow
        self.typedModel = Model(modelID)
        let clientBaseURL = baseURL.lastPathComponent == "v1"
            ? baseURL.deletingLastPathComponent()
            : baseURL
        self.client = Client(apiKey: apiKey, baseURL: clientBaseURL)
    }

    public func generateRaw(messages: [ChatMessage]) -> AsyncThrowingStream<RawStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                self.lastUsage = nil
                do {
                    try self.refuseVisionWhenUnsupported(messages: messages)
                    let request = Chat.Request(
                        model: typedModel,
                        messages: messages.map(Chat.Message.init(internal:)),
                        user: endUserID,
                    )
                    var captured: GenerationUsage?
                    for try await chunk in client.streamChatCompletions(request) {
                        try Task.checkCancellation()
                        if let usage = chunk.usage {
                            captured = GenerationUsage(
                                inputTokens: usage.promptTokens,
                                outputTokens: usage.completionTokens
                            )
                            continue
                        }
                        if let content = chunk.choices.first?.delta.content, !content.isEmpty {
                            continuation.yield(.text(content))
                        }
                    }
                    self.lastUsage = captured
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch let error as SwitchboardError {
                    continuation.finish(throwing: Self.translate(error))
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            self.currentTask = task
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func generateNative(
        messages: [ChatMessage],
        tools: [ToolSchema]
    ) -> AsyncThrowingStream<NativeStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                self.lastUsage = nil
                do {
                    try self.refuseVisionWhenUnsupported(messages: messages)
                    let request = Chat.Request(
                        model: typedModel,
                        messages: messages.map(Chat.Message.init(internal:)),
                        tools: tools.map(Chat.Tool.init(internal:)),
                        user: endUserID,
                    )
                    var buffer: [Int: ToolCallBuffer] = [:]
                    var captured: GenerationUsage?

                    for try await chunk in client.streamChatCompletions(request) {
                        try Task.checkCancellation()
                        if let usage = chunk.usage {
                            captured = GenerationUsage(
                                inputTokens: usage.promptTokens,
                                outputTokens: usage.completionTokens
                            )
                        }
                        guard let choice = chunk.choices.first else { continue }
                        if let content = choice.delta.content, !content.isEmpty {
                            continuation.yield(.text(content))
                        }
                        if let deltas = choice.delta.toolCalls {
                            for delta in deltas {
                                var entry = buffer[delta.index] ?? ToolCallBuffer()
                                if let id = delta.id { entry.id = id }
                                if let name = delta.function?.name { entry.name = name }
                                if let args = delta.function?.arguments { entry.arguments += args }
                                buffer[delta.index] = entry
                            }
                        }
                    }
                    for index in buffer.keys.sorted() {
                        let entry = buffer[index]!
                        guard let id = entry.id, let name = entry.name else { continue }
                        continuation.yield(.toolCall(id: id, name: name, argumentsJSON: entry.arguments))
                    }
                    self.lastUsage = captured
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch let error as SwitchboardError {
                    continuation.finish(throwing: Self.translate(error))
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            self.currentTask = task
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func abort() {
        currentTask?.cancel()
        currentTask = nil
    }

    private func refuseVisionWhenUnsupported(messages: [ChatMessage]) throws {
        if !supportsVision, messages.contains(where: \.hasNonTextContent) {
            throw RoutingError.imagesNotSupportedByModel(modelID: modelID)
        }
    }

    static func translate(_ error: SwitchboardError) -> ProviderError {
        switch error {
        case .serverError(let status, let code, let message, _):
            if code != nil {
                return mapError(status: status, envelope: envelope(from: error), rawBody: Data())
            }
            return .serverError(status: status, code: nil, message: message)
        case .transportError(let underlying):
            return .serverError(status: 0, code: nil, message: underlying.localizedDescription)
        case .decodingFailed(let underlying), .encodingFailed(let underlying):
            return .serverError(status: 0, code: nil, message: "Switchboard SDK round-trip failed: \(underlying.localizedDescription)")
        case .missingAPIKey:
            return .backendMisconfigured(code: "SWB-1001", message: "Switchboard API key missing")
        case .streamTruncated:
            return .serverError(status: 0, code: nil, message: "Switchboard stream ended before a final completion was produced")
        case .streamError(let code, let message, let detail):
            return .serverError(status: 0, code: code, message: detail.map { "\(message) (\($0))" } ?? message)
        }
    }

    private static func envelope(from error: SwitchboardError) -> ErrorEnvelope? {
        guard case let .serverError(_, code, message, context) = error, let code else { return nil }
        return ErrorEnvelope(
            code: code,
            error: message,
            model: context?.model,
            provider: context?.provider,
            spentMicros: context?.spentMicros,
            capMicros: context?.capMicros,
            retryAfterSeconds: context?.retryAfterSeconds,
        )
    }

    static func mapError(
        status: Int,
        envelope: ErrorEnvelope?,
        rawBody: Data,
    ) -> ProviderError {
        guard let envelope else {
            let message: String
            if rawBody.isEmpty {
                message = "Empty body"
            } else if let utf8 = String(data: rawBody, encoding: .utf8) {
                message = String(utf8.prefix(Self.nonEnvelopeBodyPreviewLimit))
            } else {
                message = "Non-UTF-8 body (\(rawBody.count) bytes)"
            }
            return .serverError(status: status, code: nil, message: message)
        }
        switch envelope.code {
        case "VALNI-1001":
            return .sessionExpired

        case "SWB-1001":
            return .backendMisconfigured(code: envelope.code, message: envelope.error)

        case "SWB-1003", "SWB-1004", "VALNI-1003", "SWB-5204":
            return .rateLimited

        case "SWB-1005":
            return .costCapExceeded(
                spentMicros: envelope.spentMicros,
                capMicros: envelope.capMicros,
                retryAfterSeconds: envelope.retryAfterSeconds,
            )

        case "SWB-3001", "SWB-3005", "VALNI-3001", "SWB-5202":
            return .modelUnavailable(modelID: envelope.model)

        case "SWB-5201", "SWB-5203", "SWB-5205":
            return .upstreamUnavailable(provider: envelope.provider)

        case let code where code.hasPrefix("SWB-5"):
            return .backendMisconfigured(code: code, message: envelope.error)

        case let code where code.hasPrefix("SWB-2") || code.hasPrefix("VALNI-2"):
            return .requestInvalid(message: envelope.error)

        default:
            return .serverError(status: status, code: envelope.code, message: envelope.error)
        }
    }
}

extension Chat.Message {
    init(internal message: ChatMessage) {
        let role: Chat.Message.Role = switch message.role {
        case .system:    .system
        case .user:      .user
        case .assistant: .assistant
        case .tool:      .tool
        }
        let content: Chat.Message.Content = switch message.content {
        case .text(let text):    .text(text)
        case .blocks(let blocks): .parts(blocks.map(Chat.Message.Content.Part.init(internal:)))
        }
        self.init(role: role, content: content, toolCallId: message.toolCallID, toolCalls: message.toolCalls)
    }
}

extension Chat.Message.Content.Part {
    init(internal block: ContentBlock) {
        switch block {
        case .text(let text):
            self = .text(text)
        case .image(let image):
            self = .image(.init(mediaType: image.mediaType, base64: image.base64))
        }
    }
}

extension Chat.Tool {
    init(internal schema: ToolSchema) {
        self.init(
            name: schema.name,
            description: schema.description,
            parameters: .init(
                properties: Dictionary(
                    uniqueKeysWithValues: schema.parameters.map { parameter in
                        (parameter.name, Chat.Tool.PropertySchema(type: parameter.type, description: parameter.description))
                    }
                ),
                required: schema.parameters.filter(\.required).map(\.name),
            )
        )
    }
}

internal struct ErrorEnvelope: Decodable {
    let code: String
    let error: String
    let model: String?
    let provider: String?
    let spentMicros: Int?
    let capMicros: Int?
    let retryAfterSeconds: Int?

    init(
        code: String,
        error: String,
        model: String? = nil,
        provider: String? = nil,
        spentMicros: Int? = nil,
        capMicros: Int? = nil,
        retryAfterSeconds: Int? = nil,
    ) {
        self.code = code
        self.error = error
        self.model = model
        self.provider = provider
        self.spentMicros = spentMicros
        self.capMicros = capMicros
        self.retryAfterSeconds = retryAfterSeconds
    }
}

private struct ToolCallBuffer {
    var id: String?
    var name: String?
    var arguments: String = ""
}
