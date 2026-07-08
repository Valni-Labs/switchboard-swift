import Foundation

public final class InferenceProvider: RawGenerationProvider, @unchecked Sendable {
    public let modelID: String

    public var endUserID: String?

    public let supportsVision: Bool
    public private(set) var lastUsage: GenerationUsage?

    private let client: Client
    private let typedModel: Model
    private let catalogContextWindow: Int?
    private var currentTask: Task<Void, Never>?

    private static let defaultMaxTokens = 8_192

    public var contextLimits: ModelLimits {
        guard let window = catalogContextWindow else { return .remoteDefault }
        return ModelLimits(contextWindow: window, budgetTokens: ModelLimits.remoteDefault.budgetTokens)
    }
    public var preferredToolCallMode: ToolCallMode { .native }

    public init(
        modelID: String,
        apiKey: String,
        endUserID: String? = nil,
        baseURL: URL = Client.defaultBaseURL,
        supportsVision: Bool = false,
        contextWindow: Int? = nil,
        urlSession: URLSession = .shared
    ) {
        self.modelID = modelID
        self.endUserID = endUserID
        self.supportsVision = supportsVision
        self.catalogContextWindow = contextWindow
        self.typedModel = Model(modelID)
        let clientBaseURL = baseURL.lastPathComponent == "v1"
            ? baseURL.deletingLastPathComponent()
            : baseURL
        self.client = Client(apiKey: apiKey, baseURL: clientBaseURL, urlSession: urlSession)
    }

    public func generateRaw(messages: [ChatMessage]) -> AsyncThrowingStream<RawStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                self.lastUsage = nil
                do {
                    try self.refuseVisionWhenUnsupported(messages: messages)
                    var captured: GenerationUsage?
                    for try await frame in self.client.streamInference(self.buildRequest(messages: messages, tools: nil)) {
                        try Task.checkCancellation()
                        switch frame {
                        case .textDelta(let text):
                            if !text.isEmpty { continuation.yield(.text(text)) }
                        case .usage(let inputTokens, let outputTokens):
                            captured = GenerationUsage(inputTokens: inputTokens, outputTokens: outputTokens)
                        case .reasoningDelta, .toolCall, .done, .native, .error:
                            continue
                        }
                    }
                    self.lastUsage = captured
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch let error as SwitchboardError {
                    continuation.finish(throwing: SwitchboardProvider.translate(error))
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
                    var captured: GenerationUsage?
                    for try await frame in self.client.streamInference(self.buildRequest(messages: messages, tools: tools)) {
                        try Task.checkCancellation()
                        switch frame {
                        case .textDelta(let text):
                            if !text.isEmpty { continuation.yield(.text(text)) }
                        case .toolCall(let id, let name, let argumentsJSON):
                            continuation.yield(.toolCall(id: id, name: name, argumentsJSON: argumentsJSON))
                        case .usage(let inputTokens, let outputTokens):
                            captured = GenerationUsage(inputTokens: inputTokens, outputTokens: outputTokens)
                        case .reasoningDelta, .done, .native, .error:
                            continue
                        }
                    }
                    self.lastUsage = captured
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch let error as SwitchboardError {
                    continuation.finish(throwing: SwitchboardProvider.translate(error))
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

    private func buildRequest(messages: [ChatMessage], tools: [ToolSchema]?) -> Inference.Request {
        let translatedTools = tools.flatMap { schemas -> [Chat.Tool]? in
            schemas.isEmpty ? nil : schemas.map(Chat.Tool.init(internal:))
        }
        return Inference.Request(
            model: typedModel,
            messages: messages.map(Chat.Message.init(internal:)),
            maxTokens: Self.defaultMaxTokens,
            tools: translatedTools,
            user: endUserID,
        )
    }

    private func refuseVisionWhenUnsupported(messages: [ChatMessage]) throws {
        if !supportsVision, messages.contains(where: \.hasNonTextContent) {
            throw RoutingError.imagesNotSupportedByModel(modelID: modelID)
        }
    }
}
