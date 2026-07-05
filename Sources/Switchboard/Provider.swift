import Foundation

public protocol Provider: AnyObject {
    var isConfigured: Bool { get }
    var modelName: String { get }
}

public protocol RawGenerationProvider: AnyObject {
    var contextLimits: ModelLimits { get }

    var preferredToolCallMode: ToolCallMode { get }

    var supportsVision: Bool { get }

    var lastUsage: GenerationUsage? { get }

    func generateRaw(messages: [ChatMessage]) -> AsyncThrowingStream<RawStreamChunk, Error>

    func generateNative(
        messages: [ChatMessage],
        tools: [ToolSchema]
    ) -> AsyncThrowingStream<NativeStreamChunk, Error>

    func abort()
}

extension RawGenerationProvider {
    public var contextLimits: ModelLimits { .remoteDefault }
    public var preferredToolCallMode: ToolCallMode { .prompt }

    public var supportsVision: Bool { false }

    public var lastUsage: GenerationUsage? { nil }

    public func generateNative(
        messages: [ChatMessage],
        tools: [ToolSchema]
    ) -> AsyncThrowingStream<NativeStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: NativeToolCallError.notSupported)
        }
    }

    public func abort() {}
}

public struct GenerationUsage: Sendable, Equatable {
    public let inputTokens: Int
    public let outputTokens: Int

    public init(inputTokens: Int, outputTokens: Int) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}

public enum GenerationError: LocalizedError {
    case emptyResponse
    case tokenLimitInThinkPhase

    public var errorDescription: String? {
        switch self {
        case .emptyResponse:
            return "The model didn't produce a response. Please try again."
        case .tokenLimitInThinkPhase:
            return "The model ran out of space before answering. Try a shorter question or reduce context."
        }
    }
}

public enum ProviderError: LocalizedError {
    case notConfigured(String)
    case unauthorized
    case sessionExpired
    case rateLimited
    case costCapExceeded(spentMicros: Int?, capMicros: Int?, retryAfterSeconds: Int?)
    case upstreamUnavailable(provider: String?)
    case modelUnavailable(modelID: String?)
    case backendMisconfigured(code: String, message: String)
    case requestInvalid(message: String)
    case serverError(status: Int, code: String?, message: String)
    case networkFailure(underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .notConfigured(let message):
            return message
        case .unauthorized:
            return "Invalid API key."
        case .sessionExpired:
            return "Your session has expired. Please sign in again."
        case .rateLimited:
            return "Too many requests right now. Please wait a moment and try again."
        case .costCapExceeded:
            return "You've reached your monthly usage cap. Wait for the cap to reset on the 1st of next month, or contact support to raise it."
        case .upstreamUnavailable(let provider):
            if let provider {
                return "\(provider) is having trouble responding. Try a different model or try again shortly."
            }
            return "The model provider is having trouble responding. Try a different model or try again shortly."
        case .modelUnavailable(let modelID):
            if let modelID {
                return "Model \"\(modelID)\" isn't available. Pick a different model from Settings → Models."
            }
            return "That model isn't available. Pick a different model from Settings → Models."
        case .backendMisconfigured(let code, let message):
            return "Backend issue (\(code)): \(message)"
        case .requestInvalid(let message):
            return "Request rejected: \(message)"
        case .serverError(let status, let code, let message):
            if let code {
                return "Server error \(status) (\(code)): \(message)"
            }
            return "Server error \(status): \(message)"
        case .networkFailure(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}
