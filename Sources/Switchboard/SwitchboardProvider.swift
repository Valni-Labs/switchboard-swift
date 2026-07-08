import Foundation

@available(*, deprecated, message: "Use InferenceProvider; every model is served through POST /v1/switchboard/inference.")
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
                    continuation.finish(throwing: ProviderErrorTranslation.translate(error))
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
                    continuation.finish(throwing: ProviderErrorTranslation.translate(error))
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

private struct ToolCallBuffer {
    var id: String?
    var name: String?
    var arguments: String = ""
}
